#!/usr/bin/env bash
# Unit tests for scripts/check-verbs.sh.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"
script="$(cd "$(dirname "$0")/../../scripts" && pwd)/check-verbs.sh"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cd "$workdir" || exit 1
# Isolate from a calling make and from CI's USE_NIX (see test-run-make.sh).
unset MAKEFLAGS MFLAGS MAKELEVEL USE_NIX

cat >Makefile <<'MAKEFILE'
VERBS := lint test
.PHONY: help install
help:
	@echo help
install dev format:
	@echo never-run >ran
format-check: ; @echo never-run >ran
$(VERBS) typecheck:
	@echo never-run >ran
fix: format
check: format-check lint typecheck test
MAKEFILE

run "$script"
assert_status 0 "accepts a Makefile with every standard verb"
assert_output "" "prints nothing when every verb is there"
if [[ -e ran ]]; then fail "runs no recipe"; else pass "runs no recipe"; fi

cat >Makefile <<'MAKEFILE'
VERBS := lint test
typecheck := not-a-target
help install dev format format-check $(VERBS):
	@echo never-run >ran
check: format-check lint test
MAKEFILE
run "$script"
assert_status 1 "fails when verbs are missing"
assert_contains "::error::The Makefile lacks the standard verbs: typecheck fix" "names every missing verb, variables do not count"
assert_contains "docs/contract.md" "points to the contract"

# A verb listed in .PHONY but without a rule is still missing (the template lists all of them).
cat >Makefile <<'MAKEFILE'
.PHONY: help install dev format format-check lint typecheck test fix check
help install dev format format-check lint test fix:
	@echo "$@: nothing to do"
check: format-check lint typecheck test
MAKEFILE
run "$script"
assert_status 1 "fails when a verb is only declared phony"
assert_contains "lacks the standard verbs: typecheck." "does not count a .PHONY entry as a rule"

# A Makefile make cannot read is reported as such, not as missing verbs.
cat >Makefile <<'MAKEFILE'
$(error boom from the Makefile)
MAKEFILE
run "$script"
assert_status 1 "fails when make cannot read the Makefile"
assert_contains "::error::make could not read the Makefile" "reports a read failure"
assert_contains "boom from the Makefile" "shows make's message"
assert_not_contains "lacks the standard verbs" "does not blame the verbs on a read failure"

rm Makefile
run "$script"
assert_status 1 "fails without a Makefile"
assert_contains "lacks the standard verbs: help install" "reports every verb without a Makefile"

finish
