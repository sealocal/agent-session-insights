# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A local read-only Sinatra web app that parses CLI agent JSONL conversation logs and visualizes token/context usage over time in a browser UI. Supports two providers:

- **Claude Code** — `~/.claude/projects/[encoded-dir]/[session-id].jsonl`
- **Codex CLI** — `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`

The frontend has a provider toggle in the sidebar; the backend uses a `Providers` registry so new sources can be added by implementing the four-method storage interface (`list`, `sessions`, `session_path`, parser `parse_file`).

## Ruby setup

Ruby is provided by [mise](https://mise.jdx.dev/). Activate it before running any commands:

```bash
eval "$(mise activate zsh)"   # or bash/fish variant
```

## Commands

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

# Lint
bundle exec standardrb
# or: bundle exec rubocop
```

## Architecture

Four layers — keep them separate:

**Providers (`lib/providers.rb`):** Registry mapping provider id → `{root, projects, parser}`. Routes look up a provider by id and delegate.

**Parsers** (`lib/parser.rb` for Claude, `lib/codex_parser.rb` for Codex): Convert JSONL into shared `Parser::Session`/`Parser::Turn` structs. No web concerns. All format fragility lives here. Must handle: missing fields, malformed lines (skip + log, don't crash), empty files, sessions with zero assistant turns.

**Project stores** (`lib/projects.rb` for Claude, `lib/codex_projects.rb` for Codex): Discover projects, list their sessions, resolve a session id to a file path. Each store decides how to map its on-disk layout to the shared "project → session" model.

**Server (`app.rb`):** Sinatra routes exposing a JSON API:
- `GET /api/providers` — list providers and whether their data dir exists
- `GET /api/providers/:provider/projects`
- `GET /api/providers/:provider/projects/:project_id/sessions`
- `GET /api/providers/:provider/projects/:project_id/sessions/:session_id`

Legacy unprefixed routes (`GET /api/projects/...`) are kept as Claude aliases for backwards compatibility.

**Frontend (static files served by Sinatra):** Consumes the JSON API. Plain JS + Chart.js. Provider toggle at top of sidebar; active provider is held in a single module-level variable.

## Data Sources

**Claude:** `~/.claude/projects/[encoded-dir]/[session-id].jsonl`. The `[encoded-dir]` is the project path with slashes replaced — decode for display, treat as opaque key otherwise. Configurable via `CLAUDE_PROJECTS_DIR`.

**Codex:** `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`. Sessions are date-partitioned, not project-partitioned: the first line of each file is a `session_meta` record carrying `cwd`. `CodexProjects` groups sessions by `cwd` to synthesize the "project" concept. Project IDs are url-safe base64 of the cwd. Configurable via `CODEX_SESSIONS_DIR`.

Never hardcode an absolute home path.

## Token Semantics — Critical Correctness Requirement

Both providers expose the same shared shape on `Parser::Turn`: `context_tokens` (per-turn snapshot, NOT additive), `output_tokens` (additive), `cache_read_tokens`, `cache_creation_tokens`. The mapping differs per provider:

**Claude:** Assistant records have `message.usage` with `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`.
- `input_tokens` is the *fresh* portion only; full context = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.

**Codex:** `event_msg/token_count` records carry `info.last_token_usage` with `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`.
- OpenAI-style: `input_tokens` is *already* the full prompt size; `cached_input_tokens` is a subset (the portion that hit cache). So `context_tokens = last_token_usage.input_tokens` directly. There is no separate `cache_creation` field.
- `total_token_usage` is cumulative across the whole session — informational only; do not plot per turn.

In all cases: **context_tokens is a snapshot, not additive**. Summing per-turn context across turns produces a meaningless number. Getting this right is the core correctness requirement.

## Tests & Fixtures

- Unit test each parser independently of the server.
- Fixtures go in `spec/fixtures/` — small synthetic JSONL files covering: normal sessions, missing `usage`, malformed lines, empty files, no assistant turns.
  - Claude fixtures live at the top of `spec/fixtures/`.
  - Codex fixtures live under `spec/fixtures/codex/YYYY/MM/DD/` to mirror the real layout.
  - A synthetic Claude data root lives at `spec/fixtures/claude_projects_root/` for the HTTP-level app spec.
- `spec/app_spec.rb` exercises the HTTP layer through rack-test and points the providers at fixture roots via `CLAUDE_PROJECTS_DIR` / `CODEX_SESSIONS_DIR`.
- Do not depend on the developer's real `~/.claude` or `~/.codex` data in tests.
