#!/usr/bin/env bash
# Coverage: parse_rerun_from, phase_completed, phase_duration_seconds,
# review_file_passed, infer_rerun_start_from_phases, infer_original_start_stage,
# infer_start_ref_from_run.

source "$(dirname -- "${BASH_SOURCE[0]}")/_helpers.sh"

tmp="$TEST_TMP"

# parse_rerun_from sets RERUN_STAGE + RERUN_ITERATION on valid input.
RERUN_STAGE=""; RERUN_ITERATION=""
parse_rerun_from "development-3"
assert_eq "development" "$RERUN_STAGE" "parse_rerun_from stage"
assert_eq "3" "$RERUN_ITERATION" "parse_rerun_from iteration"

RERUN_STAGE=""; RERUN_ITERATION=""
parse_rerun_from "review-12"
assert_eq "review" "$RERUN_STAGE" "parse_rerun_from review stage"
assert_eq "12" "$RERUN_ITERATION" "parse_rerun_from review iter"

# Invalid forms exit 2; run in subshell so we can capture.
assert_fail "(parse_rerun_from 'oops' 2>/dev/null)"                "parse_rerun_from rejects garbage"
assert_fail "(parse_rerun_from 'development-' 2>/dev/null)"        "parse_rerun_from rejects missing iter"

# Build an artifacts dir with a phases.tsv and review files.
ARTIFACTS="$tmp/run-1"
mkdir -p "$ARTIFACTS"
PHASES_TSV="$ARTIFACTS/phases.tsv"
{
  printf 'stage\titeration\tagent\tlog\tduration_seconds\n'
  printf 'development\t0\tclaude\tdev0.log\t12\n'
  printf 'review\t0\tcodex\trev0.log\t30\n'
  printf 'development\t1\tclaude\tdev1.log\t9\n'
} >"$PHASES_TSV"

assert_ok   "phase_completed development 0"  "phase_completed dev0"
assert_ok   "phase_completed review 0"       "phase_completed review0"
assert_fail "phase_completed review 1"       "phase_completed missing review1"
assert_eq   "12" "$(phase_duration_seconds development 0)" "phase_duration dev0"
assert_eq   "30" "$(phase_duration_seconds review 0)"      "phase_duration rev0"
assert_eq   ""   "$(phase_duration_seconds review 9)"      "phase_duration missing"

# review_file_passed needs review-N.md ending with the sentinel.
pass_md="$ARTIFACTS/_pass.md"
printf 'looks good\n\nREVIEW_PASSED\n' >"$pass_md"
fail_md="$ARTIFACTS/_fail.md"
printf 'oops\n\nREVIEW_FAILED\n' >"$fail_md"

# Stage as review-0.md / review-1.md for the helper to find.
cp "$pass_md" "$ARTIFACTS/review-0.md"
assert_ok "review_file_passed 0" "review_file_passed pass"
cp "$fail_md" "$ARTIFACTS/review-1.md"
assert_fail "review_file_passed 1" "review_file_passed fail"

# A bare prose mention of REVIEW_PASSED earlier in the file should NOT count.
{
  printf 'I would say REVIEW_PASSED earlier\n'
  for i in {1..20}; do printf 'more lines %s\n' "$i"; done
  printf 'REVIEW_FAILED\n'
} >"$ARTIFACTS/review-2.md"
assert_fail "review_file_passed 2" "review_file_passed prose mention"

# infer_rerun_start_from_phases picks the first missing slot. With review-0
# failing and no review-1 yet, the resume point is review-1.
cp "$fail_md" "$ARTIFACTS/review-0.md"
rm -f "$ARTIFACTS/review-1.md" "$ARTIFACTS/review-2.md"
MAX=10
ORIGINAL_START_STAGE="development"
read -r stage iter < <(infer_rerun_start_from_phases)
assert_eq "review" "$stage" "rerun infer stage"
assert_eq "1"      "$iter"  "rerun infer iteration"

# When the latest review passed, the loop is "done".
printf 'stage\titeration\tagent\tlog\tduration_seconds\n' >"$PHASES_TSV"
printf 'development\t0\tclaude\tdev0.log\t12\n' >>"$PHASES_TSV"
printf 'review\t0\tcodex\trev0.log\t30\n' >>"$PHASES_TSV"
printf 'looks good\nREVIEW_PASSED\n' >"$ARTIFACTS/review-0.md"
read -r stage iter < <(infer_rerun_start_from_phases)
assert_eq "done" "$stage" "rerun infer done"
assert_eq "1"    "$iter"  "rerun infer done iter"

# infer_original_start_stage prefers run.env, else falls back to artifacts.
metadata_file="$ARTIFACTS/run.env"
printf 'START_STAGE=review\n' >"$metadata_file"
assert_eq "review" "$(infer_original_start_stage "$ARTIFACTS")" "infer original from run.env"

rm -f "$metadata_file"
# development-0 was recorded in phases.tsv, so fallback says development.
assert_eq "development" "$(infer_original_start_stage "$ARTIFACTS")" "infer original from phases"

# infer_start_ref_from_run prefers run.env -> summary.md -> review log scan.
printf 'START_REF=deadbeef\n' >"$metadata_file"
START_REF_OVERRIDE=""
assert_eq "deadbeef" "$(infer_start_ref_from_run "$ARTIFACTS")" "infer start ref run.env"

START_REF_OVERRIDE="abc1234"
assert_eq "abc1234" "$(infer_start_ref_from_run "$ARTIFACTS")" "infer start ref override wins"
START_REF_OVERRIDE=""

rm -f "$metadata_file"
cat >"$ARTIFACTS/summary.md" <<'EOF'
# develop-review-loop summary

- Task file: task.md
- Iterations used: 1 / 10
- Verdict: PASSED
- Start ref: cafebabe
EOF
assert_eq "cafebabe" "$(infer_start_ref_from_run "$ARTIFACTS")" "infer start ref summary"

rm -f "$ARTIFACTS/summary.md"
printf 'codex says: git diff feedface00\n' >"$ARTIFACTS/review-0.log"
assert_eq "feedface00" "$(infer_start_ref_from_run "$ARTIFACTS")" "infer start ref log scan"

finish
