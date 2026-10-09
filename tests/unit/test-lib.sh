#!/usr/bin/env bash
# Checks the assertion helpers themselves.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"

run bash -c 'echo out; echo err >&2; exit 3'
assert_status 3 "run captures the exit code"
assert_contains "out" "run captures stdout"
assert_contains "err" "run captures stderr"

run true
assert_status 0 "run reports success"
assert_output "" "run captures empty output"
assert_not_contains "anything" "assert_not_contains passes on absent text"

finish
