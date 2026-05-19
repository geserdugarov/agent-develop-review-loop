# shellcheck shell=bash
# shellcheck disable=SC2317  # functions are called via eval from tests
# Shared helpers for develop-review-loop tests. Source from each test file.

set -uo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
LOOP_SCRIPT="$ROOT_DIR/develop-review-loop"

# Source the script so we can call internal helpers. The script's source guard
# returns before executing any main logic when sourced.
# shellcheck disable=SC1090
source "$LOOP_SCRIPT"

TEST_NAME="$(basename "${BASH_SOURCE[1]:-$0}")"
_failures=0

_fail() {
  printf '  FAIL [%s]: %s\n' "$TEST_NAME" "$*" >&2
  _failures=$((_failures + 1))
}

assert_eq() {
  local expected="$1" actual="$2" label="${3:-assert_eq}"
  if [[ "$expected" != "$actual" ]]; then
    _fail "$label: expected [$expected] got [$actual]"
  fi
}

assert_ok() {
  local label="${2:-assert_ok}"
  if ! eval "$1"; then
    _fail "$label: command failed: $1"
  fi
}

assert_fail() {
  local label="${2:-assert_fail}"
  if eval "$1"; then
    _fail "$label: command unexpectedly succeeded: $1"
  fi
}

finish() {
  if (( _failures > 0 )); then
    exit 1
  fi
  exit 0
}

# Per-test scratch dir. Cleaned up on EXIT. Use $TEST_TMP/foo for sub-paths.
if ! TEST_TMP="$(mktemp -d)" || [[ -z "$TEST_TMP" || ! -d "$TEST_TMP" ]]; then
  printf '  FAIL [%s]: could not create temp dir\n' "$TEST_NAME" >&2
  exit 1
fi
trap '[[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"' EXIT
