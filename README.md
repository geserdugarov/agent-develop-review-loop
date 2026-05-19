# agent-develop-review-loop
Simple loop for development > review loop with HITL in the end.

## Setup (one time)

Create stable command links in `~/bin` so `develop-review-loop` resolves from
any cwd without putting this checkout path in your shell config:

```bash
mkdir -p "$HOME/bin"
ln -sfn "$PWD/develop-review-loop" "$HOME/bin/develop-review-loop"
ln -sfn "$PWD/develop-review-loop-watch" "$HOME/bin/develop-review-loop-watch"
```

Make sure `~/bin` is on `$PATH`:

```bash
# add to ~/.bashrc (or ~/.zshrc) once, if not already present
export PATH="$HOME/bin:$PATH"
```

Then `source ~/.bashrc` and confirm:

```bash
command -v develop-review-loop
```

If you move this checkout later, rerun the two `ln -sfn` commands from the new
checkout directory. The shell `PATH` entry can stay unchanged.

### Bash tab completion

Optional Bash completion can complete flags, `--start-stage` values,
`--rerun-from` values, task files, and `.develop-review-loop/run-*` directories
after `--manual-rerun`.

Create `~/.local/share/bash-completion/completions/develop-review-loop` with the
completion function from [docs/README.md](docs/README.md#bash-tab-completion),
then open a new shell or source the file:

```bash
source ~/.local/share/bash-completion/completions/develop-review-loop
```

If your Bash setup does not load that directory automatically, add the `source`
line above to `~/.bashrc`.

The command name in this repo is `develop-review-loop`. If you also expose it as
`development-review-loop`, register that name in the completion file too.

## Usage

```bash
cd /path/to/target/repo
develop-review-loop ./task.md [--max N] [--start-stage development|review]
develop-review-loop --manual-rerun .develop-review-loop/run-YYYYMMDD-HHMMSS-PID [--max N]
```

- `<task-file>`: markdown / plain-text describing the task.
- `--max N`: iteration cap (default `10`).
- `--start-stage development|review`: stage to start from (default `development`). Use `review` when changes are already present in the work tree from a separate agent run. `--start-review` and `--review-first` are aliases for `--start-stage review`.
- `--manual-rerun <run-dir>`: reuse an interrupted run directory after an agent limit reset. The loop infers the first incomplete stage from `phases.tsv`; override with `--rerun-from development-N|review-N` when needed. For older runs without metadata, pass `--start-ref <commit>` if the start commit cannot be recovered from the review logs.
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
- `task.md`: saved task text for future reruns that need to replay `development-0`.
- `run.env`: original start ref and run metadata used by manual reruns.
- `summary.md`: final verdict, loop metadata, and post-run usage/cost estimate tables for the development and review agents.

When started with `--start-stage review`, iteration `0` skips `development-0.log` and reviews the existing work tree diff against `HEAD`. If that review fails, iteration `1` continues with the normal fix stage using `review-0.md` as feedback.

When resumed with `--manual-rerun`, the existing run directory is reused. If a Claude limit interrupts `development-4`, leaving `review-3.md` and a partial `development-4.log` but no completed `development-4` row in `phases.tsv`, the inferred rerun point is `development-4`.

Cost estimates are derived from JSON usage metadata when agent logs expose it. Reported CLI costs are preferred; otherwise the script applies known first-party API token rates as a best-effort estimate. For Codex logs that omit the model name, the estimate falls back to `CODEX_MODEL` and then the configured Codex model in `$CODEX_HOME/config.toml` or `~/.codex/config.toml`. Subscription plans, third-party providers, regional pricing, long-context modes, priority processing, and separate tool fees can differ.

See `docs/README.md` for the full project documentation and architecture notes.
