#!/usr/bin/env bash
# Unit tests for scripts/push-image.sh, with a fake docker on PATH that logs its calls.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"
script="$(dirname "$0")/../../scripts/push-image.sh"
bin=$(mktemp -d)
trap 'rm -rf "$bin"' EXIT
GITHUB_OUTPUT="$bin/output"
export GITHUB_OUTPUT
# The fake docker logs every call and answers `image inspect` with $FAKE_DIGESTS.
cat >"$bin/docker" <<'FAKE'
#!/usr/bin/env bash
echo "docker $*" >>"$FAKE_LOG"
if [[ $1 == image && $2 == inspect ]]; then printf '%s' "${FAKE_DIGESTS:-}"; fi
FAKE
chmod +x "$bin/docker"
PATH="$bin:$PATH"
export FAKE_LOG="$bin/calls"
nl=$'\n'
image=ghcr.io/o/r
build=ghcr.io/o/r:sha-0123456

: >"$FAKE_LOG"
export FAKE_DIGESTS="other.io/x@sha256:000${nl}ghcr.io/o/r@sha256:abc${nl}"
run "$script" "$image" "$build" sha-0123456 latest
assert_status 0 "pushes every tag"
output=$(cat "$FAKE_LOG")
assert_contains "docker tag $build $image:latest" "tags the build reference"
assert_contains "docker push $image:sha-0123456${nl}" "pushes the sha tag"
assert_contains "docker push $image:latest" "pushes the extra tag"
output=$(cat "$GITHUB_OUTPUT")
assert_contains "digest=sha256:abc" "outputs the digest of this image"
assert_contains "tags<<METRIFY_TAGS${nl}$image:sha-0123456${nl}$image:latest${nl}METRIFY_TAGS" "outputs the pushed references"

: >"$GITHUB_OUTPUT"
export FAKE_DIGESTS=""
run "$script" "$image" "$build" sha-0123456
assert_status 0 "does not fail after pushing when no digest is reported"
assert_contains "::warning::" "warns when no digest is reported"
output=$(cat "$GITHUB_OUTPUT")
assert_contains "digest=${nl}" "outputs an empty digest"

run "$script" "$image" "$build"
assert_status 1 "requires at least one tag"

finish
