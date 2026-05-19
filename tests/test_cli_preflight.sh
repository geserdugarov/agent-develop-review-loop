#!/usr/bin/env bash
# End-to-end CLI preflight tests: run the actual script binary and verify that
# usage errors exit with code 2 before any agent invocation.

set -uo pipefail
ROOT_DIR="${ROOT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
TEST_NAME="$(basename "${BASH_SOURCE[0]}")"
LOOP="$ROOT_DIR/develop-review-loop"
_failures=0

_fail() { printf '  FAIL [%s]: %s\n' "$TEST_NAME" "$*" >&2; _failures=$((_failures + 1)); }

expect_exit() {
  local expected="$1"; shift
  local label="$1"; shift
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    _fail "$label: expected exit $expected, got $actual (cmd: $*)"
  fi
}

if ! tmp="$(mktemp -d)" || [[ -z "$tmp" || ! -d "$tmp" ]]; then
  _fail "could not create temp dir"
  exit 1
fi
trap '[[ -n "${tmp:-}" && -d "$tmp" ]] && rm -rf "$tmp"' EXIT
cd "$tmp" || { _fail "could not cd to temp dir $tmp"; exit 1; }
git init -q . || { _fail "git init failed in $tmp"; exit 1; }
git -c user.email=x@example.com -c user.name=x commit -q --allow-empty -m "seed" \
  || { _fail "seed commit failed in $tmp"; exit 1; }

expect_exit 2 "no args"                    "$LOOP"
expect_exit 2 "missing task file"          "$LOOP" ./not-a-real-file
printf 'do stuff\n' >task.md
expect_exit 2 "bad --max (zero)"           "$LOOP" task.md --max 0
expect_exit 2 "bad --max (negative)"       "$LOOP" task.md --max -3
expect_exit 2 "bad --max (word)"           "$LOOP" task.md --max abc
expect_exit 2 "bad --start-stage"          "$LOOP" task.md --start-stage banana
expect_exit 2 "unknown flag"               "$LOOP" task.md --frobnicate
expect_exit 2 "rerun-from without rerun"   "$LOOP" task.md --rerun-from development-1
expect_exit 2 "start-ref without rerun"    "$LOOP" task.md --start-ref deadbeef
expect_exit 2 "manual-rerun missing dir"   "$LOOP" --manual-rerun "$tmp/no-such-dir"
expect_exit 2 "start-ref bad chars"        "$LOOP" --manual-rerun "$tmp" --start-ref 'evil; rm -rf /'
expect_exit 2 "--max missing value"        "$LOOP" task.md --max
expect_exit 2 "--start-stage missing val"  "$LOOP" task.md --start-stage

# Outside a git work tree, even a valid task file fails preflight.
cd "$tmp" || { _fail "could not cd to temp dir $tmp"; exit 1; }
if [[ -n "${tmp:-}" && -d "$tmp/.git" && "$(pwd -P)" == "$(cd -- "$tmp" && pwd -P)" ]]; then
  rm -rf "$tmp/.git"
else
  _fail "refusing to remove .git: cwd or tmp not as expected (tmp=$tmp, pwd=$(pwd -P))"
  exit 1
fi
expect_exit 2 "not a git work tree"        "$LOOP" task.md

# Confirm -h prints help and exits 2 (current usage() convention).
expect_exit 2 "-h returns 2"               "$LOOP" -h

if (( _failures > 0 )); then
  exit 1
fi
exit 0
