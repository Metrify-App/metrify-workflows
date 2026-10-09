#!/usr/bin/env bash
# Reads KEY=VALUE lines on stdin, masks every value and appends the pairs to $GITHUB_ENV.
# Usage: printf '%s\n' "$MAKE_ENV" | export-make-env.sh
#   Blank lines and lines starting with '#' are skipped. Nothing is exported unless every
#   line is valid. Errors name the line number, never its content.
set -euo pipefail

: "${GITHUB_ENV:?GITHUB_ENV is not set}"

# Escapes a value for the data part of a workflow command.
escape() {
  local value=${1//%/%25}
  value=${value//$'\r'/%0D}
  printf '%s' "${value//$'\n'/%0A}"
}

pairs=()
number=0
while IFS= read -r line || [[ -n $line ]]; do
  number=$((number + 1))
  line=${line%$'\r'}
  [[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
  if [[ ! $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    echo "::error::make-env line $number is not KEY=VALUE (KEY: letters, digits and '_', not starting with a digit)" >&2
    exit 1
  fi
  value=${BASH_REMATCH[2]}
  [[ -z $value ]] || echo "::add-mask::$(escape "$value")"
  pairs+=("$line")
done

if ((${#pairs[@]} > 0)); then
  printf '%s\n' "${pairs[@]}" >>"$GITHUB_ENV"
fi
