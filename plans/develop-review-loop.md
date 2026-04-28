# Claude × Codex Review Loop

## Context

You want to drive a "implement → review → fix" loop where Claude does the work and Codex acts as the reviewer, repeating until Codex is satisfied (or a hard cap is hit). Today this means manually copying review comments back into Claude after each round. The wrapper automates that handoff so you can kick off a task in any project and walk away.

This is intentionally project-agnostic — the script is invocation-agnostic of which repo it edits; `$PWD` decides that. The script itself lives in **this** repository (`agent-develop-review-loop`) so its own change history is preserved under git here, rather than as a loose file in `~/bin`. One-time setup: add this repo's checkout directory to `$PATH` so `develop-review-loop` resolves from anywhere.

## CLI

```
develop-review-loop <task-file> [--max N]
```

- `<task-file>` — path to a markdown/plain-text file describing the task. The contents are passed verbatim to Claude on iteration 0. May be a relative path (resolved against `$PWD`, i.e. the target repo) or absolute.
- `--max N` — optional override of the iteration cap (default 10).
- Project = `$PWD` (the target repo you cd into before running). The script does **not** take a `--project` flag — even though the script itself is hosted in `agent-develop-review-loop`, that is irrelevant at runtime; only `$PWD` matters for which tree gets edited.
- Exit code: `0` if review passed, `1` if cap was hit without passing, `2` for usage/IO errors.

## Loop semantics (corrected from your pseudocode)

```
review_passed=false
review_num=0
while [[ $review_passed == false && $review_num -lt $MAX ]]; do
  if (( review_num == 0 )); then
    run claude with the task
  else
    run claude with the previous codex review
  fi
  run codex; capture review; check sentinel
  review_num++
done
```

Note the condition is `&&`, not `||` — your original `||` would loop forever once `review_num >= 10` if review never passes.

## Iteration behavior

**Iteration 0 — implement.** Send Claude a prompt of the form:

> Implement the task below. Make code changes directly in the working tree of the current repo. Do not commit. Task:\n\n<contents of task file>

Run via `claude -p "<prompt>"` (print/non-interactive mode). Tee stdout+stderr to `.develop-review-loop/claude-0.log`.

**Iteration N≥1 — fix.** Send Claude:

> Codex reviewed your previous changes and flagged the issues below. Edit the code to address them. Do not revert unrelated work. Review:\n\n<contents of `review-{N-1}.md`>

Same `claude -p` invocation; log to `claude-{N}.log`.

**After each Claude run — review.** Capture the starting commit once at script start (`START_REF=$(git rev-parse HEAD)`), then on each iteration run:

```
codex exec "<review prompt>" > .develop-review-loop/review-{N}.md 2>&1
```

The review prompt instructs Codex to:
1. Inspect changes via `git diff $START_REF` (so it sees the cumulative delta, not just the latest fix).
2. Check correctness, edge cases, style, security, regressions.
3. End its output with **exactly one** of `REVIEW_PASSED` or `REVIEW_FAILED` on the final line.

**Pass detection.** `tail -n 3 review-{N}.md | grep -q '^REVIEW_PASSED$'` — anchored, on the last few lines only, so a mention of "REVIEW_PASSED" in prose elsewhere can't trigger a false pass. Anything else (including missing sentinel, or `REVIEW_FAILED`) is treated as failed.

## Artifacts (written to `.develop-review-loop/` in cwd)

- `review-{N}.md` — full Codex output for iteration N (the source of truth fed back into Claude on N+1).
- `claude-{N}.log` — tee'd stdout+stderr of the Claude run for iteration N, for post-mortem when something goes sideways.
- `summary.md` — written at the end:
  - Task file path
  - Iterations used / max
  - Final verdict (PASSED / FAILED)
  - Start ref (so you can `git diff $START_REF` after the run)
  - Wall-clock duration

The script should `mkdir -p` this directory but not gitignore it automatically — the plan notes that you may want to add `.develop-review-loop/` to your global gitignore once.

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

1. **Arg parsing & preflight.** Validate `<task-file>` exists and is readable. Confirm `claude` and `codex` are on `PATH` (`command -v`). Confirm `$PWD` is inside a git work tree (`git rev-parse --is-inside-work-tree`); fail with a clear message if not — the diff-based review depends on it.
2. **Setup.** `mkdir -p .develop-review-loop`. Capture `START_REF`, `START_TIME`, read task file into a variable.
3. **Loop.** As described above. Use `tee` for Claude logs; redirect Codex output straight to the review file.
4. **Pass check.** Anchored `grep` on `tail -n 3` of the review file.
5. **Summary + exit.** Write `summary.md`, exit `0` on pass / `1` on cap-without-pass.

No Python, no extra deps — bash + `git` + `claude` + `codex` is the entire surface.

## Verification

End-to-end, in a throwaway repo:

0. One-time: add `export PATH="$HOME/git/agent-develop-review-loop:$PATH"` to `~/.bashrc`, `source ~/.bashrc`, then `command -v develop-review-loop` should resolve to this repo's checkout.
1. `mkdir /tmp/loop-test && cd /tmp/loop-test && git init && git commit --allow-empty -m init`
2. Write a small task: `echo "Create hello.py that prints 'hello'" > task.md`
3. Run: `develop-review-loop ./task.md --max 3`
4. Confirm: `hello.py` exists with reasonable content under `/tmp/loop-test`; `.develop-review-loop/review-0.md` ends with `REVIEW_PASSED` or `REVIEW_FAILED`; `summary.md` records the verdict. Confirm nothing was written under `~/git/agent-develop-review-loop` — the script must only touch `$PWD`.
5. Negative test — give an intentionally underspecified task to force at least one failed review, and check that iteration 1 receives the review file as context (visible in `claude-1.log`).
6. Cap test — set `--max 1` on a task you expect to fail review, and confirm exit code `1` and a `FAILED` summary.
7. Commit the script + README change in this repo so the change history is preserved here (the whole point of moving it out of `~/bin`).

Manual sanity checks during development:
- `tail -n 3 review-0.md | grep -q '^REVIEW_PASSED$'` behaves as expected against handcrafted review files.
- `claude -p "echo hi"` and `codex exec "echo hi"` both produce non-interactive output in your environment (sanity-check the exact subcommand syntax before wiring it in — if `codex exec` isn't the right invocation on your machine, the script needs the actual non-interactive form instead).

## Open follow-ups (not part of this plan, just flagged)

- If Codex's non-interactive subcommand differs from `codex exec`, that one line in the script changes — everything else is invocation-agnostic.
- If you later want concurrency across multiple projects, this script is the per-project unit; a higher-level driver could fan out over a list of `(repo, task-file)` pairs.
- If the repo location ever moves, the `$PATH` line in `~/.bashrc` needs to be updated. A symlink-in-`~/bin` indirection would avoid that, but adds a setup step we're explicitly avoiding right now.
