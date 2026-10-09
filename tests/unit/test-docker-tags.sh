#!/usr/bin/env bash
# Unit tests for scripts/docker-tags.sh.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"
script="$(dirname "$0")/../../scripts/docker-tags.sh"
sha=0123456789abcdef0123456789abcdef01234567
nl=$'\n'

# auto
run "$script" pull_request refs/pull/7/merge "$sha" auto
assert_status 0 "auto: pull request succeeds"
assert_output "" "auto: pull request pushes nothing"

run "$script" push refs/heads/main "$sha" auto
assert_output "sha-0123456${nl}latest" "auto: main pushes sha and latest"

run "$script" push refs/heads/develop "$sha" auto
assert_output "sha-0123456${nl}develop" "auto: develop pushes sha and develop"

run "$script" push refs/tags/v1.2.3 "$sha" auto
assert_output "sha-0123456${nl}v1.2.3" "auto: release tag pushes sha and version"

run "$script" push refs/heads/feature/x "$sha" auto
assert_output "" "auto: other branch pushes nothing"

run "$script" workflow_dispatch refs/heads/main "$sha" auto
assert_output "" "auto: other events push nothing"

# always
run "$script" pull_request refs/pull/7/merge "$sha" always
assert_output "sha-0123456" "always: pull request pushes sha"

run "$script" push refs/heads/feature/x "$sha" always
assert_output "sha-0123456" "always: other branch pushes sha"

run "$script" workflow_dispatch refs/heads/feature/x "$sha" always
assert_output "sha-0123456" "always: other events push sha"

run "$script" push refs/heads/main "$sha" always
assert_output "sha-0123456${nl}latest" "always: main behaves like auto"

# never
run "$script" push refs/heads/main "$sha" never
assert_status 0 "never: succeeds"
assert_output "" "never: main pushes nothing"

run "$script" push refs/tags/not-a-version "$sha" never
assert_status 0 "never: ignores tag format since nothing is pushed"

# errors
run "$script" push refs/tags/v1.2 "$sha" auto
assert_status 1 "rejects a non-release tag"
assert_contains "::error::Git tag 'v1.2' is not a release tag (expected vX.Y.Z)" "explains the tag error"

run "$script" push refs/tags/1.2.3 "$sha" auto
assert_status 1 "rejects a tag without the v prefix"

run "$script" push refs/heads/main "$sha" sometimes
assert_status 1 "rejects an unknown push mode"
assert_contains "::error::unknown push mode 'sometimes'" "explains the push mode error"

run "$script" push refs/heads/main "" auto
assert_status 1 "rejects an empty SHA"
assert_contains "::error::invalid commit SHA" "explains the SHA error"

finish
