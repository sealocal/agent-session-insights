# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A local read-only Sinatra web app that parses Claude Code JSONL conversation logs from `~/.claude/projects/` and visualizes token/context usage over time in a browser UI.

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

Three distinct layers — keep them separate:

**Parser (`lib/parser.rb` or similar):** Converts JSONL files into structured Ruby objects. No web concerns. All format fragility lives here. Must handle: missing fields, malformed lines (skip + log, don't crash), empty files, sessions with zero assistant turns.

**Server (`app.rb`):** Sinatra routes exposing a JSON API:
- `GET /api/projects` — list projects (decoded directory names)
- `GET /api/projects/:project_id/sessions` — list sessions for a project
- `GET /api/projects/:project_id/sessions/:session_id` — full parsed session

**Frontend (static files served by Sinatra):** Consumes the JSON API. Plain JS + a charting library (Chart.js, uPlot, or similar). No heavy framework.

## Data Source

Logs at `~/.claude/projects/[encoded-dir]/[session-id].jsonl`. The `[encoded-dir]` is the project path with slashes replaced — decode for display, treat as opaque key otherwise.

Data directory defaults to `~/.claude/projects/` and must be configurable via env var or config file. Never hardcode an absolute home path.

## Token Semantics — Critical Correctness Requirement

Assistant records have `message.usage` with: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`.

- **`input_tokens` is a per-turn snapshot of the full context sent to the model** — do NOT sum across turns. Plot it directly as "context size over time".
- **`output_tokens` is additive** — sum across turns for cumulative output/cost.
- Total context per turn = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.

Summing per-turn `input_tokens` across turns produces a meaningless number. Getting this right is the core correctness requirement.

## Tests & Fixtures

- Unit test the parser independently of the server.
- Fixtures go in `spec/fixtures/` — small synthetic JSONL files covering: normal sessions, missing `usage`, malformed lines, empty files, no assistant turns.
- Do not depend on the developer's real `~/.claude` data in tests.
