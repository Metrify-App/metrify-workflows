#!/usr/bin/env bash
# Runs every tests/unit/test-*.sh file and fails if any of them fails.
set -uo pipefail

cd "$(dirname "$0")" || exit 1
status=0
for test in test-*.sh; do
  printf '# %s\n' "$test"
  bash "$test" || status=1
done
exit "$status"
