#!/usr/bin/env bash
# Prints the image tags to push, one per line (nothing when nothing must be pushed).
# Usage: docker-tags.sh EVENT REF SHA MODE
#   EVENT  github.event_name (push, pull_request, ...)
#   REF    github.ref (refs/heads/main, refs/tags/v1.2.3, ...)
#   SHA    full commit SHA the image is built from
#   MODE   auto, always or never
set -euo pipefail

event=${1:-}
ref=${2:-}
sha=${3:-}
mode=${4:-}

error() {
  echo "::error::$1" >&2
  exit 1
}

case $mode in
  auto | always | never) ;;
  *) error "unknown push mode '$mode' (expected auto, always or never)" ;;
esac
[[ $sha =~ ^[0-9a-f]{7,40}$ ]] || error "invalid commit SHA '$sha'"
[[ $mode == never ]] && exit 0

sha_tag="sha-${sha:0:7}"
extra=""
if [[ $event == push ]]; then
  case $ref in
    refs/heads/main) extra=latest ;;
    refs/heads/develop) extra=develop ;;
    refs/tags/*)
      version=${ref#refs/tags/}
      [[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        error "Git tag '$version' is not a release tag (expected vX.Y.Z)"
      extra=$version
      ;;
  esac
fi

if [[ -n $extra ]]; then
  printf '%s\n%s\n' "$sha_tag" "$extra"
elif [[ $mode == always ]]; then
  printf '%s\n' "$sha_tag"
fi
