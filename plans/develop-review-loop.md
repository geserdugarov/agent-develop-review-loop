# Configurable Agent Review Loop

## Context

You want to drive an "implement → review → fix" loop where one agent does the work and another agent acts as the reviewer, repeating until review passes (or a hard cap is hit). By default Claude handles development and Codex handles review, matching the original workflow. The wrapper automates that handoff so you can kick off a task in any project and walk away.

This is intentionally project-agnostic — the script is invocation-agnostic of which repo it edits; `$PWD` decides that. The script itself lives in **this** repository (`agent-develop-review-loop`) so its own change history is preserved under git here, rather than as a loose file in `~/bin`. One-time setup: add this repo's checkout directory to `$PATH` so `develop-review-loop` resolves from anywhere.

## CLI

```
develop-review-loop <task-file> [--max N] [--start-stage development|review]
```

- `<task-file>` — path to a markdown/plain-text file describing the task. The contents are passed verbatim to the configured development agent on iteration 0. May be a relative path (resolved against `$PWD`, i.e. the target repo) or absolute.
- `--max N` — optional override of the iteration cap (default 10).
- `--start-stage development|review` — optional starting stage (default `development`). Use `review` when another agent run already left changes in the work tree. `--start-review` and `--review-first` are aliases for `--start-stage review`.
- Project = `$PWD` (the target repo you cd into before running). The script does **not** take a `--project` flag — even though the script itself is hosted in `agent-develop-review-loop`, that is irrelevant at runtime; only `$PWD` matters for which tree gets edited.
- Exit code: `0` if review passed, `1` if cap was hit without passing, `2` for usage/IO errors.

## Loop semantics (corrected from your pseudocode)

```
review_passed=false
review_num=0
while [[ $review_passed == false && $review_num -lt $MAX ]]; do
  if start stage is review and review_num == 0; then
    skip development and review the existing work tree changes
  elif (( review_num == 0 )); then
    run development agent with the task
  else
    run development agent with the previous review
  fi
  run review agent; capture review; check sentinel
  review_num++
done
```

Note the condition is `&&`, not `||` — your original `||` would loop forever once `review_num >= 10` if review never passes.

## Iteration behavior

**Iteration 0 — implement.** Send the development agent a prompt of the form:

> Implement the task below. Make code changes directly in the working tree of the current repo. Do not commit. Task:\n\n<contents of task file>

The default `DEV_AGENT=claude` runs via `claude -p` (print/non-interactive mode). If `DEV_AGENT=codex`, the script uses `codex exec -s workspace-write --json`. Write stdout+stderr to `.develop-review-loop/<run-id>/development-0.log`.

**Review-first mode.** With `--start-stage review`, iteration 0 skips the development agent and immediately reviews the existing work tree diff against the start ref. No `development-0.log` is written for this mode. If review 0 fails, iteration 1 runs the normal fix stage using `review-0.md` as feedback.

**Iteration N≥1 — fix.** Send the development agent:

> The review stage flagged the issues below. Edit the code to address them. Do not revert unrelated work. Do not commit. Review:\n\n<contents of `review-{N-1}.md`>

Same configured development-agent invocation; log to `development-{N}.log`.

**After each development run — review.** Capture the starting commit once at script start (`START_REF=$(git rev-parse HEAD)`), then on each iteration run the configured review agent.

```
codex exec --json --output-last-message .develop-review-loop/<run-id>/review-{N}.md "<review prompt>" > .develop-review-loop/<run-id>/review-{N}.log 2>&1
```

The default `REVIEW_AGENT=codex` uses the command above with `-s read-only`. If `REVIEW_AGENT=claude`, the script writes Claude's final response to `review-{N}.md` and records stderr plus the final response in `review-{N}.log`.

The review prompt instructs the reviewer to:
1. Inspect changes via `git diff $START_REF` (so it sees the cumulative delta, not just the latest fix).
2. Check correctness, edge cases, style, security, regressions.
3. End its output with **exactly one** of `REVIEW_PASSED` or `REVIEW_FAILED` on the final line.

**Pass detection.** `tail -n 3 review-{N}.md | grep -q '^REVIEW_PASSED$'` — anchored, on the last few lines only, so a mention of "REVIEW_PASSED" in prose elsewhere can't trigger a false pass. Anything else (including missing sentinel, or `REVIEW_FAILED`) is treated as failed.

## Artifacts (written to `.develop-review-loop/<run-id>/` in cwd)

- `review-{N}.md` — final review text for iteration N (the source of truth fed back into the development agent on N+1).
- `review-{N}.log` — stdout+stderr of the review run for iteration N, for post-mortem and any usage/cost analysis supported by the selected agent.
- `development-{N}.log` — stdout+stderr of the development run for iteration N, for post-mortem when something goes sideways.
- `phases.tsv` — one row per development/review phase with stage, iteration, agent, log path, and elapsed seconds.
- `summary.md` — written at the end:
  - Task file path
  - Iterations used / max
  - Final verdict (PASSED / FAILED)
  - Start ref (so you can `git diff $START_REF` after the run)
  - Wall-clock duration
  - Final review file and review log paths
  - Development-agent usage/cost estimates from `development-{N}.log`
  - Review-agent usage/cost estimates from `review-{N}.log`

The usage section is appended after the verdict summary is written. It parses JSONL usage metadata with `jq` when available. Reported CLI costs such as Claude's `total_cost_usd` are preferred; otherwise known first-party API token rates are applied as best-effort estimates. For Codex logs that omit the model name, the estimate falls back to `CODEX_MODEL` and then the configured Codex model in `$CODEX_HOME/config.toml` or `~/.codex/config.toml`. When logs do not expose usage metadata, or a model has no built-in API rate, affected fields are written as `n/a`.

The script should `mkdir -p` `.develop-review-loop/`, create a fresh `run-*` subdirectory per invocation, update `.develop-review-loop/latest`, and prune older `run-*` directories after summary generation. The number of retained run directories is configured by `DEVELOP_REVIEW_LOOP_KEEP_RUNS` in `./.env` and defaults to `3`. `DEV_AGENT`, `REVIEW_AGENT`, `CODEX_BIN`, `CODEX_MODEL`, and `CLAUDE_BIN` are also read from `./.env`, with exported shell variables taking precedence. The plan notes that you may want to add `.develop-review-loop/` to your global gitignore once.

## Files to create

- `develop-review-loop` at the **root of this repo** — single bash script, `set -euo pipefail`, `chmod +x`. No file extension, so users invoke it as `develop-review-loop` (not `.sh`).
- Update this repo's `README.md` with a one-time setup snippet:

  ```bash
  # add to ~/.bashrc (or ~/.zshrc) once
  export PATH="$HOME/git/agent-develop-review-loop:$PATH"
  ```

  After sourcing, `develop-review-loop` resolves from inside any target repo. (If the user clones this repo elsewhere, they substitute the actual path.)

No changes to any target/project repo at runtime. Nothing in `~/.claude/`. Nothing in `~/bin/`.

## Implementation outline

Single bash file, roughly:

1. **Arg parsing & preflight.** Validate `<task-file>` exists and is readable. Read `./.env` configuration. Confirm the selected agent binaries are on `PATH` or executable at their configured paths (`command -v`). Confirm `$PWD` is inside a git work tree (`git rev-parse --is-inside-work-tree`); fail with a clear message if not — the diff-based review depends on it.
2. **Setup.** `mkdir -p .develop-review-loop`. Capture `START_REF`, `START_TIME`, read task file into a variable.
3. **Loop.** As described above. Redirect development-agent output to its log; redirect review-agent output to a review log while writing the final review file.
4. **Pass check.** Anchored `grep` on `tail -n 3` of the review file.
5. **Summary + usage estimates + exit.** Write the base `summary.md`, append development/review usage and cost estimate tables from the captured logs, then exit `0` on pass / `1` on cap-without-pass.

No Python. The required surface is bash + `git` + the selected agent CLIs; `jq` is optional and enables structured Claude review capture plus usage/cost parsing.

## Verification

End-to-end, in a throwaway repo:

0. One-time: add `export PATH="$HOME/git/agent-develop-review-loop:$PATH"` to `~/.bashrc`, `source ~/.bashrc`, then `command -v develop-review-loop` should resolve to this repo's checkout.
1. `mkdir /tmp/loop-test && cd /tmp/loop-test && git init && git commit --allow-empty -m init`
2. Write a small task: `echo "Create hello.py that prints 'hello'" > task.md`
3. Run: `develop-review-loop ./task.md --max 3`
4. Confirm: `hello.py` exists with reasonable content under `/tmp/loop-test`; `.develop-review-loop/latest/review-0.md` ends with `REVIEW_PASSED` or `REVIEW_FAILED`; `.develop-review-loop/latest/summary.md` records the verdict and usage/cost estimate sections; `.develop-review-loop/latest/phases.tsv` records development/review timings. Confirm nothing was written under `~/git/agent-develop-review-loop` — the script must only touch `$PWD`.
5. Negative test — give an intentionally underspecified task to force at least one failed review, and check that iteration 1 receives the review file as context (visible in `development-1.log`).
6. Cap test — set `--max 1` on a task you expect to fail review, and confirm exit code `1` and a `FAILED` summary.
7. Commit the script + README change in this repo so the change history is preserved here (the whole point of moving it out of `~/bin`).

Manual sanity checks during development:
- `tail -n 3 review-0.md | grep -q '^REVIEW_PASSED$'` behaves as expected against handcrafted review files.
- `claude -p "echo hi"` and `codex exec "echo hi"` both produce non-interactive output in your environment (sanity-check the exact subcommand syntax before wiring it in — if `codex exec` isn't the right invocation on your machine, the script needs the actual non-interactive form instead).

## Open follow-ups (not part of this plan, just flagged)

- If Codex's non-interactive subcommand differs from `codex exec`, that one line in the script changes — everything else is invocation-agnostic.
- If you later want concurrency across multiple projects, this script is the per-project unit; a higher-level driver could fan out over a list of `(repo, task-file)` pairs.
- If the repo location ever moves, the `$PATH` line in `~/.bashrc` needs to be updated. A symlink-in-`~/bin` indirection would avoid that, but adds a setup step we're explicitly avoiding right now.
