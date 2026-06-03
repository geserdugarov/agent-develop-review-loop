#!/usr/bin/env bash
# Coverage: validate_agent, agent_bin.

source "$(dirname -- "${BASH_SOURCE[0]}")/_helpers.sh"

CLAUDE_BIN="/usr/local/bin/claude-test"
CODEX_BIN="/usr/local/bin/codex-test"

assert_eq "$CLAUDE_BIN" "$(agent_bin claude)" "agent_bin claude"
assert_eq "$CODEX_BIN"  "$(agent_bin codex)"  "agent_bin codex"

assert_eq "claude" "$(agent_spec_name "claude --model claude-opus-4-7 --effort xhigh")" \
  "agent_spec_name strips inline args"
assert_eq "--model claude-opus-4-7 --effort xhigh" \
  "$(agent_spec_args "claude --model claude-opus-4-7 --effort xhigh")" \
  "agent_spec_args keeps inline args"
assert_eq "codex" "$(agent_spec_name "  codex  ")" "agent_spec_name trims whitespace"
assert_eq ""      "$(agent_spec_args "codex")"      "agent_spec_args empty without args"

parsed=()
split_cli_args parsed "-c 'model_reasoning_effort=\"xhigh\"' --label \"two words\""
assert_eq $'-c\nmodel_reasoning_effort="xhigh"\n--label\ntwo words' \
  "$(printf '%s\n' "${parsed[@]}")" \
  "split_cli_args preserves quoted Codex config values"

mock_claude="$TEST_TMP/claude-mock"
cat >"$mock_claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CAPTURE_ARGS"
printf '{"type":"result","result":"done"}\n'
EOF
chmod +x "$mock_claude"

CLAUDE_BIN="$mock_claude"
# shellcheck disable=SC2034  # run_development_agent/run_review_agent read this global.
CLAUDE_MODEL="claude-opus-4-7"
# shellcheck disable=SC2034  # run_development_agent/run_review_agent read this global.
CLAUDE_ARGS="--effort xhigh"
export CAPTURE_ARGS="$TEST_TMP/claude.args"
run_development_agent claude "--session foo" "prompt" "$TEST_TMP/development.md" "$TEST_TMP/development.log"
assert_eq $'--model\nclaude-opus-4-7\n--effort\nxhigh\n--session\nfoo' \
  "$(sed -n '1,6p' "$CAPTURE_ARGS")" \
  "run_development_agent passes configured and inline Claude args"

export CAPTURE_ARGS="$TEST_TMP/claude-review.args"
run_review_agent claude "--review-session bar" "prompt" "$TEST_TMP/review.md" "$TEST_TMP/review.log"
assert_eq $'--model\nclaude-opus-4-7\n--effort\nxhigh\n--review-session\nbar' \
  "$(sed -n '1,6p' "$CAPTURE_ARGS")" \
  "run_review_agent passes configured and inline Claude args"

mock_codex="$TEST_TMP/codex-mock"
cat >"$mock_codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CAPTURE_ARGS"
EOF
chmod +x "$mock_codex"

CODEX_BIN="$mock_codex"
CODEX_MODEL="gpt-5.5"
CODEX_ARGS="-c 'model_reasoning_effort=\"xhigh\"'"
export CAPTURE_ARGS="$TEST_TMP/codex.args"
run_development_agent codex "" "prompt" "$TEST_TMP/codex-development.md" "$TEST_TMP/codex-development.log"
assert_eq $'exec\n-m\ngpt-5.5\n-c\nmodel_reasoning_effort="xhigh"\n-s\nworkspace-write\n--json' \
  "$(sed -n '1,8p' "$CAPTURE_ARGS")" \
  "run_development_agent passes configured Codex args"

# shellcheck disable=SC2034  # run_review_agent reads this global.
CODEX_MODEL=""
# shellcheck disable=SC2034  # run_review_agent reads this global.
CODEX_ARGS=""
export CAPTURE_ARGS="$TEST_TMP/codex-review.args"
run_review_agent codex "-m gpt-5.5 -c 'model_reasoning_effort=\"xhigh\"'" \
  "prompt" "$TEST_TMP/codex-review.md" "$TEST_TMP/codex-review.log"
assert_eq $'exec\n-m\ngpt-5.5\n-c\nmodel_reasoning_effort="xhigh"\n-s\nread-only\n--json' \
  "$(sed -n '1,8p' "$CAPTURE_ARGS")" \
  "run_review_agent passes inline Codex args"

# validate_agent succeeds silently for supported values.
( validate_agent "DEV_AGENT" "claude" ) || _fail "validate_agent claude rejected"
( validate_agent "REVIEW_AGENT" "codex" ) || _fail "validate_agent codex rejected"

# Unsupported value exits 2.
status=0
( validate_agent "DEV_AGENT" "ollama" 2>/dev/null ) || status=$?
assert_eq "2" "$status" "validate_agent unsupported exit 2"

finish
