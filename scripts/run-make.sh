#!/usr/bin/env bash
# Runs a Makefile rule, inside `nix develop` when USE_NIX is true.
# Usage: USE_NIX=true|false run-make.sh RULE [VAR=VALUE...]
#   Fails with a contract error annotation when the Makefile has no such rule.
set -euo pipefail

rule=${1:?usage: run-make.sh RULE [VAR=VALUE...]}
shift

runner=()
[[ ${USE_NIX:-false} != true ]] || runner=(nix develop --command)

dry_run=$(mktemp)
trap 'rm -f "$dry_run"' EXIT
if ! "${runner[@]}" make -n "$rule" "$@" >"$dry_run" 2>&1 &&
  grep -qF "No rule to make target '$rule'" "$dry_run"; then
  echo "::error::The Makefile has no '$rule' rule. Add it, or stop calling the $rule workflow (see docs/contract.md in Metrify-App/metrify-workflows)." >&2
  exit 1
fi

"${runner[@]}" make "$rule" "$@"
