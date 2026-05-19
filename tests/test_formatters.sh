#!/usr/bin/env bash
# Coverage: fmt_count, fmt_cost, fmt_models, fmt_elapsed, add_decimal,
# extract_iteration, expand_tilde_path.

source "$(dirname -- "${BASH_SOURCE[0]}")/_helpers.sh"

assert_eq "n/a"        "$(fmt_count "")"            "fmt_count empty"
assert_eq "0"          "$(fmt_count 0)"             "fmt_count zero"
assert_eq "1,234"      "$(fmt_count 1234)"          "fmt_count thousand"
assert_eq "1,234,567"  "$(fmt_count 1234567)"       "fmt_count million"

assert_eq 'n/a'        "$(fmt_cost "")"             "fmt_cost empty"
assert_eq '$1.23'      "$(fmt_cost 1.234 reported)" "fmt_cost reported"
assert_eq '≈ $1.23'    "$(fmt_cost 1.234 estimated)" "fmt_cost estimated"
assert_eq '≈ $0.00'    "$(fmt_cost 0 estimated)"    "fmt_cost zero estimated"

assert_eq 'n/a'                       "$(fmt_models "")"                       "fmt_models empty"
assert_eq 'claude-opus-4-7'           "$(fmt_models 'claude-opus-4-7')"        "fmt_models single"
assert_eq 'claude-opus-4-7, gpt-5'    "$(fmt_models 'claude-opus-4-7,gpt-5')"  "fmt_models multi"

assert_eq "0s"      "$(fmt_elapsed 0)"      "fmt_elapsed zero"
assert_eq "59s"     "$(fmt_elapsed 59)"     "fmt_elapsed sub-minute"
assert_eq "1m00s"   "$(fmt_elapsed 60)"     "fmt_elapsed minute"
assert_eq "2m05s"   "$(fmt_elapsed 125)"    "fmt_elapsed multi-minute"

# add_decimal returns 10 decimal places by design.
sum="$(add_decimal 1.5 2.25)"
assert_eq "3.7500000000" "$sum" "add_decimal sums"
sum="$(add_decimal "" 0.25)"
assert_eq "0.2500000000" "$sum" "add_decimal empty left"

assert_eq "3"  "$(extract_iteration /tmp/runs/development-3.log development)" "extract_iteration development"
assert_eq "12" "$(extract_iteration runs/review-12.log review)"               "extract_iteration review"

# expand_tilde_path uses HOME at call time.
HOME="/home/user"
assert_eq "/home/user"          "$(expand_tilde_path "~")"            "expand bare tilde"
assert_eq "/home/user/runs"     "$(expand_tilde_path "~/runs")"       "expand tilde path"
assert_eq "/abs/path"           "$(expand_tilde_path "/abs/path")"    "expand absolute pass-through"
assert_eq "rel/path"            "$(expand_tilde_path "rel/path")"     "expand relative pass-through"

finish
