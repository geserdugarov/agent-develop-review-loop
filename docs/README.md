# agent-develop-review-loop documentation

## Purpose

`agent-develop-review-loop` is a small Bash tool that runs an automated
development and review cycle in any Git repository. One configured agent edits
the working tree, another configured agent reviews the cumulative diff, and the
loop repeats until the review passes or an iteration cap is reached.

The tool is intentionally project-agnostic. The repository that matters at
runtime is the current working directory where `develop-review-loop` is invoked,
not the repository that contains this script.

Default roles:

- Development agent: `claude`
- Review agent: `codex`

Supported agents for either role:

- `claude`
- `codex`

## Setup

Create stable command links in `~/bin`:

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

If this tool repository moves, rerun the two `ln -sfn` commands from the new
checkout directory. The shell `PATH` entry can stay unchanged.

## Bash Tab Completion

Install the bundled `completions/develop-review-loop.bash` to complete flags,
task files, `.develop-review-loop/run-*` directories after `--manual-rerun`,
allowed `--start-stage` values, and common `--rerun-from` values.

Symlink it into the standard bash-completion directory:

```bash
mkdir -p ~/.local/share/bash-completion/completions
ln -sfn "$PWD/completions/develop-review-loop.bash" \
  ~/.local/share/bash-completion/completions/develop-review-loop
```

Open a new shell or load it immediately:

```bash
source ~/.local/share/bash-completion/completions/develop-review-loop
```

If your Bash setup does not load files from that directory automatically, add
the `source` line above to `~/.bashrc`.

The bundled file registers completion for both `develop-review-loop` and the
alias `development-review-loop`, so no extra `complete` call is needed when you
maintain the alias.

## Commands

### `develop-review-loop`

```bash
develop-review-loop <task-file> [--max N] [--start-stage development|review]
develop-review-loop --manual-rerun <run-dir> [--max N] [--rerun-from development-N|review-N]
```

Arguments and options:

- `<task-file>`: readable markdown or plain-text task description.
- `--max N`: maximum review iterations. Defaults to `10`.
- `--start-stage development|review`: stage to start from. Defaults to
  `development`.
- `--start-review`, `--review-first`: aliases for `--start-stage review`.
- `--manual-rerun <run-dir>`: resume an interrupted run in an existing
  `.develop-review-loop/run-*` directory.
- `--rerun-from development-N|review-N`: override the inferred resume point for
  `--manual-rerun`.
- `--start-ref <commit>`: override the original start commit for
  `--manual-rerun` when it cannot be recovered from run metadata or review logs.

Exit codes:

- `0`: review passed.
- `1`: iteration cap was reached without a passing review.
- `2`: usage, configuration, IO, or preflight failure.

The command must run inside a Git work tree because the review prompt is based
on `git diff <start-ref>`.

### `develop-review-loop-watch`

```bash
develop-review-loop-watch [interval-seconds] [tail-lines]
```

This helper watches the current repository's `.develop-review-loop/latest`
directory and repeatedly tails the newest generated artifact. It follows the run
as files appear, typically moving through:

```text
development-N.log -> development-N.md -> review-N.log -> review-N.md
```

It requires the system `watch` command.

## Runtime Architecture

The scripts are thin orchestration around existing non-interactive agent CLIs.
They do not implement model logic themselves. They build prompts, invoke the
selected CLIs, capture logs, detect the review sentinel, and summarize the run.

```text
              target repository ($PWD)
                      |
                      v
              develop-review-loop
                      |
        +-------------+-------------+
        |                           |
        v                           v
  development agent            review agent
  claude or codex              claude or codex
        |                           |
        v                           v
  working tree edits          review-N.md verdict
        |                           |
        +-------------+-------------+
                      |
                      v
          .develop-review-loop/run-*/
          logs, reviews, phases, summary
```

### Main Components

- `develop-review-loop`: main orchestration script.
- `develop-review-loop-watch`: terminal watcher for the newest run artifact.
- `completions/develop-review-loop.bash`: Bash tab completion file.
- `tests/`: pure-bash unit tests (no extra runtime dependency). Run with
  `tests/run.sh`.
- `.github/workflows/ci.yml`: GitHub Actions workflow that runs ShellCheck and
  the test suite on pull requests and on pushes to `main`.
- `.env.example`: runtime configuration template for target repositories.
- `README.md`: quick setup and usage.
- `docs/README.md`: project behavior and architecture reference.

### State Boundaries

The script reads configuration from the target repository's `./.env` file and
writes artifacts under the target repository's `.develop-review-loop/`
directory. It does not write artifacts into this tool repository unless this
tool repository is also the current target repository.

The script captures `START_REF` once at startup with:

```bash
git rev-parse HEAD
```

Every review uses that same start ref, so reviewers inspect the cumulative diff
from the beginning of the loop rather than only the last fix.

## Control Flow

Normal mode starts with implementation. Review-first mode starts by reviewing
changes that already exist in the working tree.

```text
start
  |
  v
preflight and config
  |
  v
create run directory and record START_REF
  |
  v
+-----------------------------+
| review_passed=false         |
| review_num < max iterations |
+-----------------------------+
  |
  v
is review-first iteration 0?
  | yes
  v
skip development
  |
  +----------------------+
                         |
  no                     v
  |               run review agent
  v                     |
run development agent   v
  |               write review-N.md
  v                     |
write development-N.log
and development-N.md    v
  |               sentinel passed?
  +----------->----------+
                         |
              yes        | no
              v          v
            summary   next iteration
              |
              v
            exit
```

Loop condition:

```bash
while [[ "$review_passed" == false && "$review_num" -lt "$MAX" ]]; do
  ...
done
```

The loop stops as soon as the review passes or the configured iteration limit is
reached.

## Agent Invocation

### Development Stage

On iteration `0`, the development agent receives the task file contents:

```text
Implement the task below. Make code changes directly in the working tree of the
current repo. Do not commit.

Task:

<task file contents>
```

On later iterations, it receives the previous review:

```text
The review stage flagged the issues below. Edit the code to address them. Do not
revert unrelated work. Do not commit.

Review:

<review-(N-1).md contents>
```

Configured invocations:

- Claude with `jq` available: Claude writes stream JSON to `development-N.log`;
  `jq` extracts the final result into `development-N.md`.
- Claude without `jq`: Claude writes the final development message directly to
  `development-N.md`, with stderr and the final message copied into
  `development-N.log`.
- Codex: `codex exec -s workspace-write --json --output-last-message development-N.md`

If `CODEX_MODEL` is set, Codex invocations include `-m "$CODEX_MODEL"`.

Development output is captured in `development-N.log`; the final development
message is saved in `development-N.md`.

### Review Stage

The review agent receives a prompt instructing it to:

- inspect `git diff <START_REF>`;
- evaluate correctness, edge cases, style, security, and regressions;
- avoid modifying files or committing;
- end with exactly one final-line sentinel.

Valid final-line sentinels:

```text
REVIEW_PASSED
REVIEW_FAILED
```

The pass check is intentionally narrow:

```bash
tail -n 3 review-N.md | grep -q '^REVIEW_PASSED$'
```

This avoids treating a prose mention of `REVIEW_PASSED` elsewhere as success.
Anything other than a matching sentinel near the end is treated as a failed
review.

Configured invocations:

- Claude with `jq` available: Claude writes stream JSON to `review-N.log`; `jq`
  extracts the final result into `review-N.md`.
- Claude without `jq`: Claude writes the final review directly to
  `review-N.md`, with stderr and the final message copied into `review-N.log`.
- Codex: `codex exec -s read-only --json --output-last-message review-N.md`.

Review command failures do not immediately stop the loop. If the review file is
empty, the script creates a blocking review that points to the raw review log and
ends with `REVIEW_FAILED`.

## Configuration

Runtime configuration is read from `./.env` in the target repository. Exported
environment variables take precedence over values in `./.env`.

Supported variables:

| Variable | Default | Description |
| --- | --- | --- |
| `DEV_AGENT` | `claude` | Agent for implementation and fix stages. Supported values: `claude`, `codex`. |
| `REVIEW_AGENT` | `codex` | Agent for review stages. Supported values: `claude`, `codex`. |
| `CODEX_BIN` | `codex` | Codex CLI executable or path. |
| `CODEX_MODEL` | empty | Optional model passed to `codex exec -m`. Also used as a usage-summary fallback when logs omit the model. |
| `CLAUDE_BIN` | `claude` | Claude CLI executable or path. |
| `DEVELOP_REVIEW_LOOP_KEEP_RUNS` | `3` | Number of `.develop-review-loop/run-*` directories to retain, including the current run. |

Configuration parsing supports plain `KEY=value` lines, optional `export`,
single or double wrapping quotes, whitespace around values, full-line `#`
comments, and inline `#` comments preceded by whitespace. Inside quoted values
the `#` character is preserved literally (so `URL=http://x.example/#frag`
keeps the fragment). Blank lines are ignored. The first matching `KEY=` line
wins. The file is parsed, never `source`d.

## Artifacts

Each run writes to:

```text
.develop-review-loop/run-YYYYMMDD-HHMMSS-PID/
```

The script also updates:

```text
.develop-review-loop/latest -> run-YYYYMMDD-HHMMSS-PID
```

Generated files:

| File | Description |
| --- | --- |
| `development-N.log` | Development-stage log for iteration `N`. Not written for review-first iteration `0`. |
| `development-N.md` | Final development-stage message for iteration `N`. Not written for review-first iteration `0`. |
| `review-N.log` | Review-stage stdout and stderr for iteration `N`. |
| `review-N.md` | Final review text and sentinel for iteration `N`. Fed back into the next development stage when review fails. |
| `phases.tsv` | Tab-separated timing metadata: stage, iteration, agent, log path, duration seconds. |
| `task.md` | Saved task text for future reruns that need to replay `development-0`. |
| `run.env` | Original start ref and run metadata used by manual reruns. |
| `summary.md` | Final verdict, metadata, final review paths, and usage/cost estimate tables. |

Retention cleanup happens after summary generation. The current run counts toward
`DEVELOP_REVIEW_LOOP_KEEP_RUNS`.

## Usage and Cost Summaries

After the final verdict is written, the script appends usage and cost tables to
`summary.md`.

Data sources:

- `phases.tsv` for duration.
- `development-*.log` for development-agent usage.
- `review-*.log` for review-agent usage.

`jq` is optional but recommended. When available, it lets the script parse JSONL
metadata from agent logs and extract structured Claude review output. Without
`jq`, the loop still runs, but fields that require JSON parsing are reported as
`n/a`.

Cost handling:

- Reported CLI cost fields such as `total_cost_usd` are preferred.
- If no reported cost exists, known first-party API token rates are used as a
  best-effort estimate.
- If a model is unknown or has no built-in rate, affected costs are `n/a`.
- For Codex logs that omit model names, the fallback order is `CODEX_MODEL`,
  then `$CODEX_HOME/config.toml`, then `~/.codex/config.toml`.

The summary notes when fields are unavailable because `jq` is missing, usage
metadata is absent, parsing failed, or a model price is unknown.

Cost estimates are operational guidance, not billing authority. Subscription
plans, third-party providers, regional pricing, long-context modes, priority
processing, and separate tool fees can differ.

## Review-First Mode

Use review-first mode when another agent or manual edit already changed the
working tree and you want this loop to start with review:

```bash
develop-review-loop ./task.md --start-stage review
```

Behavior:

- Iteration `0` skips development.
- The review agent reviews the existing cumulative diff from `START_REF`.
- No `development-0.log` is written.
- If `review-0.md` fails, iteration `1` runs the normal fix stage using that
  review as feedback.

## Manual Rerun Mode

Use manual rerun mode after an agent-side interruption, such as a Claude usage
limit, when the working tree should continue from the existing run artifacts:

```bash
develop-review-loop --manual-rerun .develop-review-loop/run-YYYYMMDD-HHMMSS-PID
```

The runner reuses the run directory instead of creating a new one. It reads
`phases.tsv` and starts at the first phase that has no completed row. For
example, if `review-3.md` exists and `phases.tsv` has rows through `review 3`,
but `development-4.log` is only a rate-limit failure and no `development 4` row
was recorded, the next run starts at `development-4`.

Override the inference when needed:

```bash
develop-review-loop --manual-rerun .develop-review-loop/run-YYYYMMDD-HHMMSS-PID --rerun-from development-4
```

Future runs store `run.env` and `task.md` at creation time. Older interrupted
runs may not have those files; in that case the rerun code recovers the original
start commit from `summary.md` or the `git diff <commit>` command captured in
review logs. If that recovery fails, pass `--start-ref <commit>`.

## Failure Behavior

Preflight failures exit with code `2`. Examples:

- missing task file for a normal run;
- non-positive `--max`;
- unsupported `DEV_AGENT` or `REVIEW_AGENT`;
- missing selected agent executable;
- current directory is not inside a Git work tree;
- invalid `DEVELOP_REVIEW_LOOP_KEEP_RUNS`.

Review failures are part of normal loop behavior. A failed review advances to
the next development iteration until the cap is hit.

Development-agent command failures are not masked by the script. Because the
main script uses `set -euo pipefail`, a development command failure stops the
run instead of asking the reviewer to evaluate incomplete work. Resume those
runs later with `--manual-rerun`.

## Design Constraints

- Bash-only implementation; no Python runtime dependency.
- Git work tree required.
- The current working directory is the target project.
- Agents are non-interactive CLI processes.
- The development agent may edit files; the review agent is configured for
  read-only operation when using Codex and explicitly instructed not to edit.
- Generated artifacts live under `.develop-review-loop/`.
- This tool does not commit changes.

## Testing

The repo ships a small pure-bash test suite under `tests/`. Each `test_*.sh`
file is a self-contained bash script; the runner discovers and executes them:

```bash
tests/run.sh
```

The tests source `develop-review-loop` so they can call internal helpers
directly. A guard in the main script returns early when the script is sourced
instead of executed, so no side effects run during tests. Tests rely only on
`bash`, `awk`, `grep`, `git`, `mktemp`, and (for `tests/test_cli_preflight.sh`)
the ability to `git init` in `mktemp`-created directories.

GitHub Actions runs the same suite plus `shellcheck --severity=warning` on
pull requests and on pushes to `main`. See `.github/workflows/ci.yml`.

## Security Notes

The loop is a thin wrapper around two long-running AI CLIs that edit the
working tree. A few specifics are worth calling out:

- **`--dangerously-skip-permissions` for Claude.** Both stages invoke `claude`
  with this flag so the run can complete non-interactively. The dev stage
  agent has full write access to the working tree; the review stage does too
  when `REVIEW_AGENT=claude`, even though the prompt instructs it not to edit
  files. Only run the loop inside a repository you would let an unattended
  agent modify, and inspect `git status` after each run.
- **Codex review uses `-s read-only`.** When `REVIEW_AGENT=codex`, Codex is
  restricted by its own sandbox. The dev stage runs with
  `-s workspace-write`, which limits Codex to the current workspace.
- **`.env` is read from the target repo, not this tool repo.** Values like
  `CLAUDE_BIN`, `CODEX_BIN`, and `CODEX_MODEL` are read from the target's
  `./.env` and used as executable paths or as a model name passed to the CLI.
  Treat target repositories the same way you treat their shell `PATH`: if you
  cd into an untrusted repo, do not run `develop-review-loop` there without
  first inspecting `.env`. The parser only recognizes a fixed list of keys
  (see the configuration table) and never `source`s the file.
- **`--start-ref` is validated.** The override is restricted to characters git
  permits in commits, refs, and short SHAs before being passed to
  `git rev-parse` and embedded in the review prompt.
- **`.develop-review-loop/` is gitignored upstream but not in target repos.**
  Add it to your target repo's ignore policy so logs (which can contain
  arbitrary review/dev-agent output) are not committed.

## Operational Notes

- Add `.develop-review-loop/` to target repo ignore policy if generated
  artifacts should not be tracked.
- Keep task files specific enough for the development agent to act without
  additional clarification.
- Inspect `summary.md` first after a run; then inspect the final `review-N.md`
  and corresponding logs if the run failed.
- Use `develop-review-loop-watch` from another terminal to monitor long runs.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](../LICENSE) for
the full text.
