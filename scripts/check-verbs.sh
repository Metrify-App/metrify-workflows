#!/usr/bin/env bash
# Fails with a contract error annotation when the Makefile lacks a standard Metrify verb.
# Usage: USE_NIX=true|false check-verbs.sh   (run in the directory of the Makefile)
#   Reads make's rule database (`make -pRrq`): no verb recipe runs, but make still parses the
#   Makefile ($(shell ...)) and may regenerate included makefiles.
set -euo pipefail

verbs=(help install dev format format-check lint typecheck test fix check)
probe=.metrify-no-such-target

use_nix=${USE_NIX:-false}
unset USE_NIX
runner=()
[[ $use_nix != true ]] || runner=(nix develop --command)

errors=$(mktemp)
trap 'rm -f "$errors"' EXIT
# The probe target cannot exist: -q only prints the database, then stops on the probe.
database=$("${runner[@]}" make -pRrq "$probe" 2>"$errors" || true)
if ! grep -qF "No rule to make target '$probe'" "$errors"; then
  echo "::error::make could not read the Makefile: $(tr '\n' ' ' <"$errors")" >&2
  exit 1
fi

# A verb counts when it has a rule: prerequisites or a recipe. A name that only appears in
# .PHONY, or as a "Not a target" entry, does not.
targets=$(awk '
  function flush() { if (name != "" && (deps || recipe)) print name; name = "" }
  /^# Not a target:/ { flush(); skip = 1; next }
  /^[A-Za-z0-9_.-]+::?([^=]|$)/ {
    flush()
    if (skip) { skip = 0; next }
    name = $0; sub(/:.*/, "", name)
    rest = $0; sub(/^[^:]*::?/, "", rest); deps = (rest ~ /[^ \t|]/)
    recipe = 0; next
  }
  /^\t/ { recipe = 1; next }
  /^$/ { flush(); skip = 0 }
  END { flush() }' <<<"$database")

missing=()
for verb in "${verbs[@]}"; do
  grep -qxF "$verb" <<<"$targets" || missing+=("$verb")
done

if ((${#missing[@]} > 0)); then
  echo "::error::The Makefile lacks the standard verbs: ${missing[*]}. Every Metrify repo has ${verbs[*]} (see docs/contract.md in Metrify-App/metrify-workflows)." >&2
  exit 1
fi
