#!/usr/bin/env bash
# Unit tests for scripts/check-image.sh, with a fake docker on PATH.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"
script="$(dirname "$0")/../../scripts/check-image.sh"
bin=$(mktemp -d)
trap 'rm -rf "$bin"' EXIT
# The fake docker knows exactly one image.
cat >"$bin/docker" <<'FAKE'
#!/usr/bin/env bash
[[ $1 == image && $2 == inspect && $3 == known:tag ]]
FAKE
chmod +x "$bin/docker"
PATH="$bin:$PATH"

run "$script" known:tag
assert_status 0 "accepts an existing image"
assert_output "" "prints nothing on success"

run "$script" ghcr.io/o/r:sha-0123456
assert_status 1 "fails when the image is missing"
assert_contains "::error::make docker-build did not produce 'ghcr.io/o/r:sha-0123456'" "names the missing image"
assert_contains "\$(IMAGE)" "points to the IMAGE contract"

finish
