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
develop-review-loop ./task.md [--max N]
```

- `<task-file>`: markdown / plain-text describing the task.
- `--max N`: iteration cap (default `10`).
- Project = `$PWD` (the repo you cd into). Artifacts land in a per-run subdirectory under `.develop-review-loop/`.
- Exit codes: `0` review passed, `1` cap hit without passing, `2` usage / preflight error.

### Configuration

Optional runtime configuration is read from `./.env` in the target repo. Copy this repo's `.env.example` to the target repo as a starting point.

- `DEV_AGENT`: development/fix-stage agent. Supported values: `claude`, `codex`. Defaults to `claude`.
- `REVIEW_AGENT`: review-stage agent. Supported values: `claude`, `codex`. Defaults to `codex`.
- `CODEX_BIN`: path to the Codex CLI. Defaults to `codex`.
- `CLAUDE_BIN`: path to the Claude CLI. Defaults to `claude`.
- `DEVELOP_REVIEW_LOOP_KEEP_RUNS`: number of `.develop-review-loop/run-*` artifact directories to keep, including the current run. Defaults to `3`.

Example:

```dotenv
DEV_AGENT=claude
REVIEW_AGENT=codex

# Path to the codex CLI. Override only if not on $PATH.
CODEX_BIN=codex

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
- `summary.md`: final verdict and loop metadata.

See `plans/develop-review-loop.md` for the full design.
