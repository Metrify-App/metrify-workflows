#!/usr/bin/env bash
# Unit tests for scripts/export-make-env.sh.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"
script="$(dirname "$0")/../../scripts/export-make-env.sh"
GITHUB_ENV=$(mktemp)
export GITHUB_ENV
trap 'rm -f "$GITHUB_ENV"' EXIT
nl=$'\n'

export_env() { printf '%s' "$1" | "$script"; }

run export_env "API_URL=https://example.test${nl}TOKEN=s3cr%t${nl}"
assert_status 0 "accepts KEY=VALUE lines"
assert_contains "::add-mask::https://example.test" "masks the first value"
assert_contains "::add-mask::s3cr%25t" "escapes % in masked values"
assert_not_contains "TOKEN=" "never prints a pair"
output=$(cat "$GITHUB_ENV")
assert_output "API_URL=https://example.test${nl}TOKEN=s3cr%t" "appends the pairs to GITHUB_ENV"

: >"$GITHUB_ENV"
run export_env "${nl}# comment${nl}   ${nl}EMPTY=${nl}A_1=x=y"
assert_status 0 "skips blank and comment lines"
assert_not_contains "::add-mask::${nl}" "does not mask empty values"
output=$(cat "$GITHUB_ENV")
assert_output "EMPTY=${nl}A_1=x=y" "keeps '=' inside values and empty values"

: >"$GITHUB_ENV"
run export_env "B=1"
assert_status 0 "accepts a last line without newline"
output=$(cat "$GITHUB_ENV")
assert_output "B=1" "exports the last line without newline"

: >"$GITHUB_ENV"
run export_env $'C=1\r\n'
output=$(cat "$GITHUB_ENV")
assert_output "C=1" "strips Windows line endings"

: >"$GITHUB_ENV"
run export_env "GOOD=1${nl}not a pair secret-value${nl}"
assert_status 1 "rejects a line without '='"
assert_contains "::error::make-env line 2 is not KEY=VALUE" "names the bad line"
assert_not_contains "secret-value" "never prints the bad line"
output=$(cat "$GITHUB_ENV")
assert_output "" "exports nothing when a line is invalid"

run export_env "1BAD=x"
assert_status 1 "rejects a key starting with a digit"

run export_env "BAD KEY=x"
assert_status 1 "rejects a key with a space"

run env -u GITHUB_ENV bash -c "printf 'A=1' | '$script'"
assert_status 1 "requires GITHUB_ENV"

finish
