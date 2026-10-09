#!/usr/bin/env bash
# Unit tests for scripts/image-name.sh.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"
script="$(dirname "$0")/../../scripts/image-name.sh"

run "$script" Metrify-App/metrify-api
assert_status 0 "defaults to the repository name"
assert_output "ghcr.io/metrify-app/metrify-api" "lowercases the owner"

run "$script" Metrify-App/metrify-api Metrify-API-Worker
assert_output "ghcr.io/metrify-app/metrify-api-worker" "uses and lowercases the image name"

run "$script" Metrify-App/metrify-api ""
assert_output "ghcr.io/metrify-app/metrify-api" "treats an empty image name as unset"

run "$script" metrify-api
assert_status 1 "rejects a repository without owner"
assert_contains "::error::invalid repository" "explains the repository error"

run "$script" Metrify-App/metrify-api "bad/name"
assert_status 1 "rejects an image name with a slash"
assert_contains "::error::invalid image name 'bad/name'" "explains the image name error"

finish
