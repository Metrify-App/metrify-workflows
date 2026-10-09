#!/usr/bin/env bash
# Tags BUILD_REF with every TAG, pushes them, and writes the `tags` and `digest` step outputs.
# Usage: push-image.sh IMAGE BUILD_REF TAG...
#   An empty digest only warns: the image is already pushed at that point.
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
image=${1:?usage: push-image.sh IMAGE BUILD_REF TAG...}
build_ref=${2:?usage: push-image.sh IMAGE BUILD_REF TAG...}
shift 2
if (($# == 0)); then
  echo "::error::push-image.sh needs at least one tag" >&2
  exit 1
fi

refs=()
for tag in "$@"; do
  docker tag "$build_ref" "$image:$tag"
  docker push "$image:$tag"
  refs+=("$image:$tag")
done

digest=""
while IFS= read -r repo_digest; do
  if [[ $repo_digest == "$image@"* ]]; then
    digest=${repo_digest#*@}
    break
  fi
done < <(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$build_ref")
[[ -n $digest ]] || echo "::warning::pushed $image but Docker reported no digest for it; the digest output is empty." >&2

{
  echo "digest=$digest"
  echo "tags<<METRIFY_TAGS"
  printf '%s\n' "${refs[@]}"
  echo "METRIFY_TAGS"
} >>"$GITHUB_OUTPUT"
