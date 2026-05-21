# Agent Session Insights

A local, read-only web app that parses CLI agent conversation logs and visualizes
token and context usage over time in your browser. Single-user, localhost-only,
and entirely read-only — it never writes to your log files.

Supports two providers:

- **Claude Code** — `~/.claude/projects/[encoded-dir]/[session-id].jsonl`
- **Codex CLI** — `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`

Pick a provider in the sidebar, choose a project and session, and view a dual-axis
chart of per-turn context size (snapshot) against cumulative output tokens.

## Requirements

Ruby 4.0.4, managed via [mise](https://mise.jdx.dev/) (`.tool-versions` in the repo root):

```bash
eval "$(mise activate zsh)"   # or the bash/fish variant
```

## Setup

```bash
bundle install
```

## Running

```bash
bundle exec ruby app.rb
```

Then open http://localhost:4567. The server binds to `127.0.0.1` only.

| Env var | Default | Purpose |
|---------|---------|---------|
| `PORT` | `4567` | HTTP port |
| `CLAUDE_PROJECTS_DIR` | `~/.claude/projects` | Claude log root |
| `CODEX_SESSIONS_DIR` | `~/.codex/sessions` | Codex log root |

## Development

```bash
bundle exec rspec        # run the test suite
bundle exec standardrb   # lint (authoritative)
```

## How it works

Four separate layers:

- **Providers** (`lib/providers.rb`) — registry mapping a provider id to its store and parser.
- **Parsers** (`lib/parser.rb`, `lib/codex_parser.rb`) — turn JSONL into shared `Session`/`Turn` structs. All format fragility lives here.
- **Project stores** (`lib/projects.rb`, `lib/codex_projects.rb`) — discover projects, list sessions, and resolve a session id to a file path (path-traversal safe).
- **Server** (`app.rb`) — a thin Sinatra JSON API; the frontend (`public/index.html`) is vanilla JS + Chart.js with no build step.

See [CLAUDE.md](CLAUDE.md) for the full architecture notes, token semantics, and test-fixture reference.
