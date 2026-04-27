# agent-develop-review-loop
Simple loop for development > review loop with HITL in the end.

## Setup (one time)

Add this repo's checkout directory to `$PATH` so `claude-review-loop` resolves from any cwd:

```bash
# add to ~/.bashrc (or ~/.zshrc) once
export PATH="$HOME/git/agent-develop-review-loop:$PATH"
```

Then `source ~/.bashrc` and confirm:

```bash
command -v claude-review-loop
```

If you cloned this repo elsewhere, substitute the actual path.

## Usage

```bash
cd /path/to/target/repo
claude-review-loop ./task.md [--max N]
```

- `<task-file>`: markdown / plain-text describing the task.
- `--max N`: iteration cap (default `10`).
- Project = `$PWD` (the repo you cd into). Artifacts land in `.claude-review-loop/`.
- Exit codes: `0` review passed, `1` cap hit without passing, `2` usage / preflight error.

### Watching progress

In another terminal in the same target repo:

```bash
claude-review-loop-watch              # 1s interval, 20 lines
claude-review-loop-watch 2 40         # 2s interval, 40 lines
```

Tracks the newest file in `.claude-review-loop/` and re-tails it each tick, so the view follows the loop automatically as `claude-N.log` → `review-N.md` → `claude-(N+1).log`.

See `plans/develop-review-loop.md` for the full design.
