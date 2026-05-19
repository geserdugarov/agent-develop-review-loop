#!/usr/bin/env bash
# Coverage: trim_spaces, strip_wrapping_quotes, read_env_value, read_config_value.

source "$(dirname -- "${BASH_SOURCE[0]}")/_helpers.sh"

tmp="$TEST_TMP"
envfile="$tmp/.env"

cat >"$envfile" <<'EOF'
# comment line
DEV_AGENT=claude
REVIEW_AGENT="codex"
  export QUOTED_SINGLE='value with spaces'
WITH_TRAILING=foo   # inline comment
MULTI_HASH=claude # local # default
EMPTY=
EMPTY_WITH_COMMENT= # use default
QUOTED_DOUBLE="quoted-with-#hash"
LAST_WINS=first
LAST_WINS=second
NO_SPACE_HASH=http://example.com/path#frag
FRAG_WITH_COMMENT=http://x.example/#frag # trailing comment
LITERAL_HASH=#nocomment
TRAILING_AFTER_QUOTE="value" # trailing
EOF

assert_eq "abc"   "$(trim_spaces "   abc   ")"               "trim_spaces simple"
assert_eq ""      "$(trim_spaces "   ")"                     "trim_spaces all whitespace"
assert_eq "abc"   "$(strip_wrapping_quotes '"abc"')"         "strip double quotes"
assert_eq "abc"   "$(strip_wrapping_quotes "'abc'")"         "strip single quotes"
assert_eq "abc"   "$(strip_wrapping_quotes 'abc')"           "strip none"
assert_eq '"abc'  "$(strip_wrapping_quotes '"abc')"          "strip unbalanced left"

assert_eq "claude"            "$(read_env_value DEV_AGENT "$envfile")"             "DEV_AGENT plain"
assert_eq "codex"             "$(read_env_value REVIEW_AGENT "$envfile")"          "REVIEW_AGENT double quoted"
assert_eq "value with spaces" "$(read_env_value QUOTED_SINGLE "$envfile")"         "QUOTED_SINGLE export+quoted"
assert_eq "foo"               "$(read_env_value WITH_TRAILING "$envfile")"         "WITH_TRAILING inline comment stripped"
assert_eq "claude"            "$(read_env_value MULTI_HASH "$envfile")"            "Inline comment splits at first whitespace-#"
assert_eq ""                  "$(read_env_value EMPTY "$envfile")"                 "EMPTY returns empty"
assert_eq ""                  "$(read_env_value EMPTY_WITH_COMMENT "$envfile")"    "EMPTY_WITH_COMMENT returns empty (comment after =)"
assert_eq "quoted-with-#hash" "$(read_env_value QUOTED_DOUBLE "$envfile")"         "Quoted hash preserved"
assert_eq "first"             "$(read_env_value LAST_WINS "$envfile")"             "First occurrence wins"
assert_eq "http://example.com/path#frag" \
                              "$(read_env_value NO_SPACE_HASH "$envfile")"         "Hash without leading space is preserved"
assert_eq "http://x.example/#frag" \
                              "$(read_env_value FRAG_WITH_COMMENT "$envfile")"     "Fragment with trailing whitespace-# comment is stripped"
assert_eq "#nocomment"        "$(read_env_value LITERAL_HASH "$envfile")"          "Literal # at start of value preserved when no preceding whitespace"
assert_eq "value"             "$(read_env_value TRAILING_AFTER_QUOTE "$envfile")"  "Trailing comment after closing quote stripped"
assert_fail "read_env_value MISSING '$envfile' >/dev/null"                          "Missing key returns 1"
assert_fail "read_env_value DEV_AGENT '$tmp/does-not-exist' >/dev/null"             "Missing file returns 1"

# read_config_value layering: exported env > .env > default.
CONFIG_FILE="$envfile"
unset DEV_AGENT
assert_eq "claude"  "$(read_config_value DEV_AGENT fallback)"  "config: from .env"

DEV_AGENT=codex
assert_eq "codex"   "$(read_config_value DEV_AGENT fallback)"  "config: exported wins"
unset DEV_AGENT

CONFIG_FILE="$tmp/does-not-exist"
assert_eq "fallback" "$(read_config_value DEV_AGENT fallback)" "config: default when no .env"

finish
