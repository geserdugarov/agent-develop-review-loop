#!/usr/bin/env bash
# Coverage: validate_agent, agent_bin.

source "$(dirname -- "${BASH_SOURCE[0]}")/_helpers.sh"

CLAUDE_BIN="/usr/local/bin/claude-test"
CODEX_BIN="/usr/local/bin/codex-test"

assert_eq "$CLAUDE_BIN" "$(agent_bin claude)" "agent_bin claude"
assert_eq "$CODEX_BIN"  "$(agent_bin codex)"  "agent_bin codex"

# validate_agent succeeds silently for supported values.
( validate_agent "DEV_AGENT" "claude" ) || _fail "validate_agent claude rejected"
( validate_agent "REVIEW_AGENT" "codex" ) || _fail "validate_agent codex rejected"

# Unsupported value exits 2.
status=0
( validate_agent "DEV_AGENT" "ollama" 2>/dev/null ) || status=$?
assert_eq "2" "$status" "validate_agent unsupported exit 2"

finish
