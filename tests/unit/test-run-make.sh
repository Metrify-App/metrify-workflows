#!/usr/bin/env bash
# Unit tests for scripts/run-make.sh.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"
script="$(cd "$(dirname "$0")/../../scripts" && pwd)/run-make.sh"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cd "$workdir" || exit 1
# Isolate from a calling make (`make test`), which would add "Entering directory" lines.
unset MAKEFLAGS MFLAGS MAKELEVEL
# Same for USE_NIX, which CI sets when the library tests itself through run-make.
unset USE_NIX

cat >Makefile <<'MAKEFILE'
hello:
	@echo hello
show:
	@echo "image=$(IMAGE)"
env:
	@echo "use_nix=$$USE_NIX"
broken:
	@exit 4
MAKEFILE

run "$script" hello
assert_status 0 "runs an existing rule"
assert_output "hello" "prints the rule output"

run "$script" show IMAGE=ghcr.io/o/r:sha-0123456
assert_output "image=ghcr.io/o/r:sha-0123456" "passes make variables"

run env USE_NIX=false "$script" env
assert_output "use_nix=" "does not leak USE_NIX to the rules"

run "$script" missing
assert_status 1 "fails on a missing rule"
assert_contains "::error::The Makefile has no 'missing' rule" "explains the missing rule"

run "$script" install
assert_status 1 "fails when install is missing"
assert_contains "::error::The Makefile has no 'install' rule. Every Metrify repo has one" "explains that install is mandatory"
assert_not_contains "stop calling the install workflow" "does not mention a workflow that does not exist"

run "$script" broken
assert_status 2 "propagates make's failure"
assert_not_contains "::error::" "does not blame the contract when the rule fails"

run "$script"
assert_status 1 "requires a rule"

finish
