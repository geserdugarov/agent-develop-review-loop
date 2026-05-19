#!/usr/bin/env bash
# Plain-bash test runner. Discovers tests/test_*.sh, runs each in a subshell,
# and reports a pass/fail summary. Fails the whole run on the first failure.

set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$ROOT_DIR/tests"

pass=0
fail=0
failed_files=()

shopt -s nullglob
mapfile -t files < <(printf '%s\n' "$TESTS_DIR"/test_*.sh | sort)
shopt -u nullglob

if (( ${#files[@]} == 0 )); then
  echo "no tests found in $TESTS_DIR" >&2
  exit 2
fi

for file in "${files[@]}"; do
  name="$(basename "$file")"
  if ( ROOT_DIR="$ROOT_DIR" bash "$file" ); then
    pass=$((pass + 1))
    printf 'PASS %s\n' "$name"
  else
    fail=$((fail + 1))
    failed_files+=("$name")
    printf 'FAIL %s\n' "$name"
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failed: %s\n' "${failed_files[*]}"
  exit 1
fi
