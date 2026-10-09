#!/usr/bin/env bash
# Fails with a contract error annotation when IMAGE_REF does not exist in the local Docker daemon.
# Usage: check-image.sh IMAGE_REF
set -euo pipefail

image=${1:?usage: check-image.sh IMAGE_REF}

if ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "::error::make docker-build did not produce '$image'. The docker-build rule must tag its image with \$(IMAGE) (see docs/contract.md in Metrify-App/metrify-workflows)." >&2
  exit 1
fi
