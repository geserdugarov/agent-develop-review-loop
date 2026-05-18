# agent-develop-review-loop
Simple loop for development > review loop with HITL in the end.

## Setup (one time)

Add this repo's checkout directory to `$PATH` so `develop-review-loop` resolves from any cwd:

```bash
# add to ~/.bashrc (or ~/.zshrc) once
export PATH="$HOME/git/agent-develop-review-loop:$PATH"
```

Then `source ~/.bashrc` and confirm:

```bash
command -v develop-review-loop
```

If you cloned this repo elsewhere, substitute the actual path.

## Usage

```bash
cd /path/to/target/repo
develop-review-loop ./task.md [--max N] [--start-stage development|review]
```

- `<task-file>`: markdown / plain-text describing the task.
- `--max N`: iteration cap (default `10`).
- `--start-stage development|review`: stage to start from (default `development`). Use `review` when changes are already present in the work tree from a separate agent run. `--start-review` and `--review-first` are aliases for `--start-stage review`.
- Project = `$PWD` (the repo you cd into). Artifacts land in a per-run subdirectory under `.develop-review-loop/`.
- Exit codes: `0` review passed, `1` cap hit without passing, `2` usage / preflight error.

### Configuration

Optional runtime configuration is read from `./.env` in the target repo. Copy this repo's `.env.example` to the target repo as a starting point.

- `DEV_AGENT`: development/fix-stage agent. Supported values: `claude`, `codex`. Defaults to `claude`.
- `REVIEW_AGENT`: review-stage agent. Supported values: `claude`, `codex`. Defaults to `codex`.
- `CODEX_BIN`: path to the Codex CLI. Defaults to `codex`.
- `CODEX_MODEL`: optional model passed to `codex exec -m`. When unset, Codex uses its own default/configured model; the usage summary will still try to read that configured model from `$CODEX_HOME/config.toml` or `~/.codex/config.toml` if JSON logs omit it.
- `CLAUDE_BIN`: path to the Claude CLI. Defaults to `claude`.
- `DEVELOP_REVIEW_LOOP_KEEP_RUNS`: number of `.develop-review-loop/run-*` artifact directories to keep, including the current run. Defaults to `3`.

`jq` is a command-line JSON processor. It is optional but recommended. When present, the loop can parse JSONL usage metadata for the final cost tables and can capture Claude review runs as structured logs. Without `jq`, the loop still runs, but unsupported usage fields are reported as `n/a`.

Install it with your system package manager, for example `sudo apt install jq` on Debian/Ubuntu or `brew install jq` on macOS.

Example:

```dotenv
DEV_AGENT=claude
REVIEW_AGENT=codex

# Path to the codex CLI. Override only if not on $PATH.
CODEX_BIN=codex

# Optional explicit Codex model. Leave empty to use Codex's own default/config.
# CODEX_MODEL=gpt-5.5

# Path to the claude CLI. Override only if not on $PATH.
CLAUDE_BIN=claude
```

### Watching progress

In another terminal in the same target repo:

```bash
develop-review-loop-watch              # 1s interval, 20 lines
develop-review-loop-watch 2 40         # 2s interval, 40 lines
```

Tracks the newest file in `.develop-review-loop/latest` and re-tails it each tick, so the view follows the loop automatically as `development-N.log` → `review-N.log` → `review-N.md` → `development-(N+1).log`.

### Artifacts

Each invocation writes to `.develop-review-loop/run-YYYYMMDD-HHMMSS-PID/`. The script also updates `.develop-review-loop/latest` to point at the newest run directory and prunes older `run-*` directories according to `DEVELOP_REVIEW_LOOP_KEEP_RUNS`.

- `development-N.log`: development-stage stdout/stderr for iteration `N`.
- `review-N.log`: review-stage stdout/stderr for iteration `N`. Codex review logs are JSONL and include any usage events emitted by Codex.
- `review-N.md`: final review text for iteration `N`, used as feedback for the next development pass.
- `phases.tsv`: per-stage timing metadata used by the summary.
- `summary.md`: final verdict, loop metadata, and post-run usage/cost estimate tables for the development and review agents.

When started with `--start-stage review`, iteration `0` skips `development-0.log` and reviews the existing work tree diff against `HEAD`. If that review fails, iteration `1` continues with the normal fix stage using `review-0.md` as feedback.

Cost estimates are derived from JSON usage metadata when agent logs expose it. Reported CLI costs are preferred; otherwise the script applies known first-party API token rates as a best-effort estimate. For Codex logs that omit the model name, the estimate falls back to `CODEX_MODEL` and then the configured Codex model in `$CODEX_HOME/config.toml` or `~/.codex/config.toml`. Subscription plans, third-party providers, regional pricing, long-context modes, priority processing, and separate tool fees can differ.

See `docs/README.md` for the full project documentation and architecture notes.
