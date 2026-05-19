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

Install this optional Bash completion to complete flags, task files,
`.develop-review-loop/run-*` directories after `--manual-rerun`, allowed
`--start-stage` values, and common `--rerun-from` values.

Create `~/.local/share/bash-completion/completions/develop-review-loop`:

```bash
mkdir -p ~/.local/share/bash-completion/completions
```

File contents:

```bash
_develop_review_loop() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local opts="
    --max
    --start-stage
    --start-review
    --review-first
    --manual-rerun
    --resume-run
    --rerun-run
    --rerun-from
    --start-ref
    --help
    -h
  "

  case "$prev" in
    --manual-rerun|--resume-run|--rerun-run)
      COMPREPLY=( $(compgen -d -- "${cur:-.develop-review-loop/run-}") )
      [[ ${#COMPREPLY[@]} -gt 0 ]] || COMPREPLY=( $(compgen -d -- "$cur") )
      return
      ;;
    --start-stage)
      COMPREPLY=( $(compgen -W "development review" -- "$cur") )
      return
      ;;
    --rerun-from)
      local stages="" i
      for i in {0..20}; do
        stages+=" development-$i review-$i"
      done
      COMPREPLY=( $(compgen -W "$stages" -- "$cur") )
      return
      ;;
    --max)
      return
      ;;
  esac

  if [[ "$cur" == --* ]]; then
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    return
  fi

  COMPREPLY=( $(compgen -f -- "$cur") )
}

complete -o filenames -F _develop_review_loop develop-review-loop
```

Open a new shell or load it immediately:

```bash
source ~/.local/share/bash-completion/completions/develop-review-loop
```

If your Bash setup does not load files from that directory automatically, add
the `source` line above to `~/.bashrc`.

The repository command is named `develop-review-loop`. If you maintain an
additional alias or symlink named `development-review-loop`, register both names:

```bash
complete -o filenames -F _develop_review_loop develop-review-loop development-review-loop
```

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
development-N.log -> review-N.log -> review-N.md -> development-(N+1).log
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
write development-N.log v
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

- Claude: `claude -p --dangerously-skip-permissions --output-format stream-json --include-partial-messages --verbose`
- Codex: `codex exec -s workspace-write --json`

If `CODEX_MODEL` is set, Codex invocations include `-m "$CODEX_MODEL"`.

Development stdout and stderr are captured in `development-N.log`.

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
single or double wrapping quotes, whitespace around values, comments, and blank
lines.

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
| `development-N.log` | Development-stage stdout and stderr for iteration `N`. Not written for review-first iteration `0`. |
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

## Operational Notes

- Add `.develop-review-loop/` to target repo ignore policy if generated
  artifacts should not be tracked.
- Keep task files specific enough for the development agent to act without
  additional clarification.
- Inspect `summary.md` first after a run; then inspect the final `review-N.md`
  and corresponding logs if the run failed.
- Use `develop-review-loop-watch` from another terminal to monitor long runs.
