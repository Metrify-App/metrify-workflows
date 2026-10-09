#!/usr/bin/env bash
# Prints the GHCR image name (without tag) for a repository.
# Usage: image-name.sh OWNER/REPO [IMAGE_NAME]
#   IMAGE_NAME defaults to REPO. Owner and name are lowercased, as GHCR requires.
set -euo pipefail

repository=${1:-}
name=${2:-}

if [[ ! $repository =~ ^[^/]+/[^/]+$ ]]; then
  echo "::error::invalid repository '$repository' (expected OWNER/REPO)" >&2
  exit 1
fi
owner=${repository%%/*}
[[ -n $name ]] || name=${repository#*/}
owner=${owner,,}
name=${name,,}

if [[ ! $name =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
  echo "::error::invalid image name '$name' (lowercase letters, digits, '.', '_' and '-' only)" >&2
  exit 1
fi
printf 'ghcr.io/%s/%s\n' "$owner" "$name"
