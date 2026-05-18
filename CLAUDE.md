# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A local read-only Sinatra web app that parses CLI agent JSONL conversation logs and visualizes token/context usage over time in a browser UI. Single-user, localhost-only, and entirely read-only — it never writes to log files. Supports two providers:

- **Claude Code** — `~/.claude/projects/[encoded-dir]/[session-id].jsonl`
- **Codex CLI** — `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`

The frontend has a provider toggle in the sidebar; the backend uses a `Providers` registry so new sources can be added by implementing the four-method storage interface (`list`, `sessions`, `session_path`, parser `parse_file`).

## Ruby Setup

Ruby 4.0.4 is managed via [mise](https://mise.jdx.dev/) (`.tool-versions` in repo root). Activate before running any commands:

```bash
eval "$(mise activate zsh)"   # or bash/fish variant
```

## Commands

Always invoke `rspec`, `standardrb`, and `ruby app.rb` through `bundle exec` so they resolve to the gem versions pinned in `Gemfile.lock`. Bare invocations may pick up a different installed version.

```bash
# Install dependencies
bundle install

# Run the app (default: http://localhost:4567)
bundle exec ruby app.rb

# Run all tests
bundle exec rspec

# Run a single test file
bundle exec rspec spec/parser_spec.rb

# Run a specific example by line number
bundle exec rspec spec/parser_spec.rb:42

# Lint (standardrb is the canonical linter)
bundle exec standardrb
# equivalent:
bundle exec rubocop
```

## Key Dependencies

| Gem | Purpose |
|-----|---------|
| `sinatra ~> 4.0` | Web framework |
| `sinatra-contrib ~> 4.0` | `json()` helper for JSON responses |
| `puma ~> 6.0` | Threaded HTTP server |
| `rackup ~> 2.0` | Rack runner |
| `rspec ~> 3.13` | Test framework |
| `rack-test ~> 2.1` | HTTP integration testing |
| `standard ~> 1.40` | Linter (rubocop + standardrb rules) |

## Architecture

Four layers — keep them separate:

**Providers (`lib/providers.rb`):** Registry mapping provider id → `{root, projects, parser}`. Routes look up a provider by id and delegate.

**Parsers** (`lib/parser.rb` for Claude, `lib/codex_parser.rb` for Codex): Convert JSONL into shared `Parser::Session`/`Parser::Turn` structs. No web concerns. All format fragility lives here. Must handle: missing fields, malformed lines (skip + log, don't crash), empty files, sessions with zero assistant turns.

Shared structs:

```ruby
Parser::Turn = Struct.new(
  :index, :role, :timestamp,
  :context_tokens,        # per-turn snapshot — NOT additive
  :output_tokens,         # additive across turns
  :cache_read_tokens,
  :cache_creation_tokens,
  :text_preview,          # first 140 chars of message content
  keyword_init: true
)

Parser::Session = Struct.new(
  :session_id, :project, :started_at,
  :turn_count, :turns, :totals,
  keyword_init: true
)
```

**Project stores** (`lib/projects.rb` for Claude, `lib/codex_projects.rb` for Codex): Discover projects, list their sessions, resolve a session id to a file path. Each store decides how to map its on-disk layout to the shared "project → session" model. Session file resolution via `session_path` uses `File.realpath` with a prefix check to prevent directory traversal.

**Server (`app.rb`):** Sinatra routes exposing a JSON API. Minimal logic — delegates entirely to providers/parsers/stores.
- `GET /api/providers` — list providers and whether their data dir exists
- `GET /api/providers/:provider/projects`
- `GET /api/providers/:provider/projects/:project_id/sessions`
- `GET /api/providers/:provider/projects/:project_id/sessions/:session_id`

Legacy unprefixed routes (`GET /api/projects/...`) are kept as Claude aliases for backwards compatibility.

**Frontend (`public/index.html`):** Single-page app. Vanilla JS + Chart.js. Dark theme. No build step, no framework. Provider toggle at top of sidebar; active provider is held in a single module-level variable. Dual-axis chart: left Y-axis context tokens (blue, area fill), right Y-axis cumulative output tokens (green, line), X-axis turn timestamps.

## Data Sources

**Claude:** `~/.claude/projects/[encoded-dir]/[session-id].jsonl`. The `[encoded-dir]` is the project path with slashes replaced — decode for display, treat as opaque key otherwise. Configurable via `CLAUDE_PROJECTS_DIR`.

Claude JSONL record shape:
```jsonc
{
  "type": "user" | "assistant" | "permission-mode" | ...,
  "message": {
    "role": "user" | "assistant",
    "content": "string" | [{"type": "text", "text": "..."}],
    "usage": {                          // assistant turns only
      "input_tokens": 512,
      "output_tokens": 42,
      "cache_creation_input_tokens": 8000,
      "cache_read_input_tokens": 0
    }
  },
  "uuid": "...",
  "timestamp": "2025-05-10T14:23:00.000Z",
  "cwd": "/path/to/project",
  "sessionId": "abc123-...",
  "isMeta": false                        // true → internal harness record, skip
}
```

**Codex:** `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`. Sessions are date-partitioned, not project-partitioned: the first line of each file is a `session_meta` record carrying `cwd`. `CodexProjects` groups sessions by `cwd` to synthesize the "project" concept. Project IDs are url-safe base64 of the cwd. Configurable via `CODEX_SESSIONS_DIR`.

Never hardcode an absolute home path.

## Token Semantics — Critical Correctness Requirement

Both providers expose the same shared shape on `Parser::Turn`: `context_tokens` (per-turn snapshot, NOT additive), `output_tokens` (additive), `cache_read_tokens`, `cache_creation_tokens`. The mapping differs per provider:

**Claude:** `input_tokens` is the *fresh* portion only; full context = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.

| Field | Semantics |
|-------|-----------|
| `input_tokens` | Fresh context this turn (not cache) |
| `output_tokens` | New tokens generated — **sum across turns** |
| `cache_creation_input_tokens` | Tokens written to prompt cache |
| `cache_read_input_tokens` | Tokens read from prompt cache |

**Total context per turn** = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`

**Codex:** `event_msg/token_count` records carry `info.last_token_usage` with `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`.
- OpenAI-style: `input_tokens` is already the full prompt size; `cached_input_tokens` is a subset. So `context_tokens = last_token_usage.input_tokens` directly. There is no separate `cache_creation` field.
- `total_token_usage` is cumulative across the whole session — informational only; do not plot per turn.

In all cases: **context_tokens is a snapshot, not additive**. **Peak context** = `max` of per-turn values, not `sum`. Summing per-turn context across turns produces a meaningless number. Getting this right is the core correctness requirement.

## Tests & Fixtures

- Unit test each parser independently of the server.
- Fixtures go in `spec/fixtures/` — small synthetic JSONL files. Never depend on real `~/.claude` or `~/.codex` data.
  - Claude fixtures live at the top of `spec/fixtures/`.
  - Codex fixtures live under `spec/fixtures/codex/YYYY/MM/DD/` to mirror the real layout.
  - A synthetic Claude data root lives at `spec/fixtures/claude_projects_root/` for the HTTP-level app spec.
- `spec/app_spec.rb` exercises the HTTP layer through rack-test and points the providers at fixture roots via `CLAUDE_PROJECTS_DIR` / `CODEX_SESSIONS_DIR`.

| Claude Fixture | Purpose |
|----------------|---------|
| `normal_session.jsonl` | 2 user + 2 assistant turns; tests context calc, cache hits, output totals |
| `malformed_lines.jsonl` | Mix of valid JSON and garbage; parser must skip bad lines and continue |
| `missing_usage.jsonl` | Assistant turns with absent or empty `usage` block |
| `no_assistant_turns.jsonl` | User-only session; all token fields should be nil |
| `empty.jsonl` | Empty file (0 bytes); returns session with 0 turns |

When adding new parser behavior, add a corresponding fixture and spec context.

## Conventions

- **No comments** unless the why is non-obvious. Well-named identifiers are documentation enough.
- **No database** — read-only file I/O only.
- **No frontend framework** — vanilla JS + Chart.js only. No build step.
- **Linter is authoritative** — run `bundle exec standardrb` before committing.
- **Path safety** — session file resolution goes through each store's `session_path` which validates and uses `File.realpath`.
- **Layer separation** — parsers have no HTTP/Rack concerns; server has no parsing logic; frontend consumes the API only.
