#!/usr/bin/env bash
# Fails with a contract error annotation when the Makefile lacks a standard Metrify verb.
# Usage: USE_NIX=true|false check-verbs.sh   (run in the directory of the Makefile)
#   Reads make's rule database (`make -pRrq`), so no recipe runs.
set -euo pipefail

verbs=(help install dev format format-check lint typecheck test fix check)

use_nix=${USE_NIX:-false}
unset USE_NIX
runner=()
[[ $use_nix != true ]] || runner=(nix develop --command)

# A target that cannot exist, so -q only prints the database and fails harmlessly.
targets=$("${runner[@]}" make -pRrq .metrify-no-such-target 2>/dev/null | awk '
  /^# Not a target:/ { skip = 1; next }
  /^[A-Za-z0-9_.-]+:/ { name = $0; sub(/:.*/, "", name); if (!skip) print name }
  { skip = 0 }' || true)

missing=()
for verb in "${verbs[@]}"; do
  grep -qxF "$verb" <<<"$targets" || missing+=("$verb")
done

if ((${#missing[@]} > 0)); then
  echo "::error::The Makefile lacks the standard verbs: ${missing[*]}. Every Metrify repo has ${verbs[*]} (see docs/contract.md in Metrify-App/metrify-workflows)." >&2
  exit 1
fi
