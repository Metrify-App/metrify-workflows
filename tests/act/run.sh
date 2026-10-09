#!/usr/bin/env bash
# Runs the library's CI locally with act, on a copy of the working tree.
# Usage: tests/act/run.sh [act arguments...]   e.g. tests/act/run.sh -j fixture-test
#   act 0.2.x does not support the self-repository syntax (`uses: $/...`, nektos/act#6189).
#   In this repository `$/` and `./` resolve to the same code, so the copy rewrites one into
#   the other. Jobs that install Nix (library / lint, library / test) need a systemd host and
#   are better checked with `make check` directly.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
copy=$(mktemp -d)
trap 'rm -rf "$copy"' EXIT

git -C "$root" ls-files -z --cached --others --exclude-standard |
  (cd "$root" && xargs -0 cp --parents -t "$copy")
git -C "$copy" init -q
find "$copy/.github" -name '*.yml' -exec sed -i 's#uses: \$/#uses: ./#' {} +

cd "$copy"
act pull_request -P ubuntu-latest=catthehacker/ubuntu:act-latest "$@"
