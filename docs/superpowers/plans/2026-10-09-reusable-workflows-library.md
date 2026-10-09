# Metrify Reusable Workflows Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `Metrify-App/metrify-workflows`, a library of reusable GitHub Actions workflows (`lint`, `test`, `build`, `docker`). Each one runs one standard Makefile rule of the calling repository, and `docker` pushes images to GHCR with a shared tag convention.

**Architecture:** One public reusable workflow (`workflow_call`) per Makefile rule. Each one loads its internal composites (`setup-env`, `run-make`, and for Docker `image-meta`, `image-push`) with GitHub's self-repository syntax `uses: $/...`, which resolves to this repository at the commit of the running workflow, whatever ref the consumer referenced. All non-trivial logic lives in `scripts/*.sh` and is unit-tested in plain bash. The library dogfoods its own contract (`flake.nix` + `Makefile`), runs self-tests on fixture consumers in `ci.yml`, and releases with release-please plus a floating major tag `vX`.

**Tech Stack:** GitHub Actions (reusable workflows, composite actions), bash 5, GNU make, Nix flakes, actionlint 1.7.12, zizmor, shellcheck, release-please-action v5, GHCR.

**Spec:** `docs/superpowers/specs/2026-10-09-reusable-workflows-library-design.md`

## Global Constraints

- All repository content is in English (code, comments, docs, commit messages).
- Commit messages: Conventional Commits, `type(scope): imperative summary`. Every commit ends with the trailer `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Never commit on `main`. Implementation happens on branch `reusable-workflows`, created from `design-spec`.
- `nix develop --command make lint` and `nix develop --command make test` pass at every commit, starting from Task 1.
- Third-party actions are pinned by full commit SHA with a version comment, using exactly these:
  - `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`
  - `actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0`
  - `actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0`
  - `actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97 # v7.0.0`
  - `actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0`
  - `DeterminateSystems/nix-installer-action@3138316df39ed29be04236d7ffc686fa525866aa # v23` (always with `determinate: false`)
  - `nix-community/cache-nix-action@7df957e333c1e5da7721f60227dbba6d06080569 # v7`
  - `docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0`
  - `googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7 # v5.0.0`
- Workflows: `permissions: {}` at the top level, minimal permissions per job, `persist-credentials: false` on every checkout, and untrusted values passed through `env:` (never `${{ }}` inside `run:`).
- Image names: `ghcr.io/<lowercase owner>/<lowercase image-name>`. The build tag is always `sha-<first 7 chars of commit>`.
- Push tags (`push: auto`): PR → none; `main` → `sha-<short>` + `latest`; `develop` → `sha-<short>` + `develop`; tag `vX.Y.Z` → `sha-<short>` + `vX.Y.Z`; anything else → none.
- Architecture: `linux/amd64` only.
- Internal composites and in-repo workflows are referenced with `uses: $/...` (self-repository syntax), never `./...` and never a checkout of the library.
- Outward-facing actions (changing repository visibility or settings, the first push, opening or merging pull requests, publishing releases, pushing to another repository) need an explicit "yes" from the user at execution time, even when this plan lists them.

## Script interfaces

Every task that writes or calls a script uses exactly these contracts. Errors are printed as `::error::<message>` on **stderr**, and the exit code is 1.

| Script | Arguments | Environment | stdout on success |
|--------|-----------|-------------|-------------------|
| `scripts/image-name.sh` | `OWNER/REPO [IMAGE_NAME]` (an empty `IMAGE_NAME` means REPO) | none | `ghcr.io/<owner>/<name>`, lowercased |
| `scripts/docker-tags.sh` | `EVENT REF SHA MODE` (`MODE` is `auto`, `always` or `never`) | none | tags to push, one per line, nothing if none (for example `sha-0123456`, then `latest`) |
| `scripts/export-make-env.sh` | none; `KEY=VALUE` lines on stdin | `GITHUB_ENV` (required) | one `::add-mask::<escaped value>` per non-empty value; the pairs are appended to `$GITHUB_ENV` only when every line is valid |
| `scripts/run-make.sh` | `RULE [VAR=VALUE...]` | `USE_NIX` (`true` runs `nix develop --command make ...`) | make's output; exit code is make's own on rule failure, or 1 with the missing-rule error |
| `scripts/check-image.sh` | `IMAGE_REF` | none | nothing; exit 1 with the contract error if `docker image inspect` fails |

Composite interfaces (Task 6), used by Tasks 7 and 8:

- `.github/actions/setup-env`: inputs `working-directory` (`.`), `cache-scope` (required), `node-version`, `python-version`, `go-version`, `cache-paths`, `cache-key-files` (all default `""`). Output `use-nix` (`'true'` or `'false'`).
- `.github/actions/run-make`: inputs `rule` (required), `working-directory` (`.`), `use-nix` (`"false"`), `make-args` (space-separated `VAR=VALUE`, default `""`), `make-env` (default `""`).
- `.github/actions/image-meta` (Task 8): inputs `image-name` (`""`), `push` (`auto`). Outputs `image`, `build-ref` (`<image>:sha-<short>`), `tag-list` (space-separated, empty when nothing is pushed).
- `.github/actions/image-push` (Task 8): inputs `image`, `build-ref` (required), `tag-list` (`""`: check only). Outputs `tags` (newline-separated pushed references), `digest`.

## Review Focus

These five risks are implied by the spec but not covered by any unit test. Each one has a check pinned in the task that owns it.

1. **Pull request runs and cross-repository calls resolve `$/` to the library commit.** Checked in Task 2 (in-repo PR run and a throwaway caller in `Metrify-App/test-app`, both green on 2026-10-09).
2. **Masking `make-env` values when make prints them.** A value echoed by a rule must show as `***` in the log. Pinned in Task 7, Step 9 (the fixture test rule echoes `FIXTURE_TOKEN`, and the log is inspected).
3. **A consumer in another repository** calling `@<branch>` (full workflows, not just the smoke composite). The in-repo self-tests cannot cover this. Pinned in Task 11, Step 3 (a throwaway consumer branch, run only after a "yes").
4. **Nix consumers whose devShell lacks `gnumake`** get `make: command not found`, not the contract error. This is documented as a known error in Task 10 (`docs/workflows.md`, "Common errors"). Dogfooding (Task 7) proves the happy path.
5. **First release and the floating tag.** `release-please` must create `v1.0.0`, and `major-tag` must create `v1` through the API with `GITHUB_TOKEN`. Pinned in Task 11, Steps 5 and 6.

---

### Task 0: Publish the repository skeleton

The remote `Metrify-App/metrify-workflows` is empty and private. It must have a `main` branch to open pull requests against, and it must be public for consumers (spec §1). Local branch `design-spec` holds the approved spec (4 commits).

**Files:** none.

- [ ] **Step 1: Ask the user for a "yes"** to all three actions below, in one message: (a) push `design-spec` as the initial `main`, which contains only the approved spec; (b) make the repository public; (c) push the `reusable-workflows` branch as work progresses. Do not continue without it.

- [ ] **Step 2: Push the spec as `main`**

Run: `git push origin design-spec:main`
Expected: `* [new branch]      design-spec -> main`

- [ ] **Step 3: Make the repository public**

Run: `gh repo edit Metrify-App/metrify-workflows --visibility public --accept-visibility-change-consequences`
Then run: `gh api repos/Metrify-App/metrify-workflows --jq .visibility`
Expected: `public`

- [ ] **Step 4: Create the implementation branch**

Run: `git checkout -b reusable-workflows design-spec`
Expected: `Switched to a new branch 'reusable-workflows'`

### Task 1: Dev shell, Makefile and unit-test harness

**Files:**
- Create: `flake.nix`, `flake.lock` (generated), `.envrc`, `.gitignore`, `Makefile`
- Create: `tests/unit/lib.sh`, `tests/unit/run.sh`, `tests/unit/test-lib.sh`

**Interfaces:**
- Produces: `make lint`, `make test` and the test helpers `run`, `assert_status`, `assert_output`, `assert_contains`, `assert_not_contains` and `finish` (from `tests/unit/lib.sh`). `run` stores combined stdout+stderr in `$output` and the exit code in `$status`. Test files are `tests/unit/test-*.sh`.

- [ ] **Step 1: Write `flake.nix`**

```nix
{
  description = "Metrify reusable GitHub Actions workflows: development shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            gnumake
            actionlint
            zizmor
            shellcheck
            act
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
```

- [ ] **Step 2: Write `.envrc` and `.gitignore`**

`.envrc`:
```
use flake
```

`.gitignore`:
```
.direnv/
tests/fixtures/plain/.cache/
```

- [ ] **Step 3: Write `Makefile`** (actionlint and zizmor are added in Task 2, when there is a first workflow to analyse: both tools fail when they have no input)

```make
# Checks of the library itself. Run inside the dev shell: `nix develop --command make <rule>`
# (direnv users: `use flake`). CI runs the same rules through the library's own workflows.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-6s\033[0m %s\n", $$1, $$2}'

.PHONY: lint
lint: ## Static analysis of scripts
	shellcheck -x $(wildcard scripts/*.sh tests/unit/*.sh)

.PHONY: test
test: ## Unit tests of the scripts
	tests/unit/run.sh
```

- [ ] **Step 4: Write the failing self-test `tests/unit/test-lib.sh`**

```bash
#!/usr/bin/env bash
# Checks the assertion helpers themselves.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"

run bash -c 'echo out; echo err >&2; exit 3'
assert_status 3 "run captures the exit code"
assert_contains "out" "run captures stdout"
assert_contains "err" "run captures stderr"

run true
assert_status 0 "run reports success"
assert_output "" "run captures empty output"
assert_not_contains "anything" "assert_not_contains passes on absent text"

finish
```

- [ ] **Step 5: Write `tests/unit/run.sh` and make it executable**

```bash
#!/usr/bin/env bash
# Runs every tests/unit/test-*.sh file and fails if any of them fails.
set -uo pipefail

cd "$(dirname "$0")" || exit 1
status=0
for test in test-*.sh; do
  printf '# %s\n' "$test"
  bash "$test" || status=1
done
exit "$status"
```

Run: `chmod +x tests/unit/run.sh && git add flake.nix && nix flake lock && nix develop --command make test` (Nix only sees files tracked by git, hence the `git add`)
Expected: FAIL, because `lib.sh` is missing (`lib.sh: No such file or directory`) and `make` exits non-zero.

- [ ] **Step 6: Write `tests/unit/lib.sh`**

```bash
#!/usr/bin/env bash
# Minimal assertion helpers for the unit tests (sourced, not executed).
# Usage: run <command...>, then assert_* on $status and $output, and call finish at the end.

failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

# Runs a command, storing its combined stdout and stderr in $output and its exit code in $status.
run() {
  if output=$("$@" 2>&1); then status=0; else status=$?; fi
}

assert_status() {
  if [[ $status == "$1" ]]; then pass "$2"; else fail "$2 (expected status $1, got $status; output: $output)"; fi
}

assert_output() {
  if [[ $output == "$1" ]]; then pass "$2"; else fail "$2 (expected output '$1', got '$output')"; fi
}

assert_contains() {
  if [[ $output == *"$1"* ]]; then pass "$2"; else fail "$2 (expected output to contain '$1', got '$output')"; fi
}

assert_not_contains() {
  if [[ $output != *"$1"* ]]; then pass "$2"; else fail "$2 (output must not contain '$1', got '$output')"; fi
}

finish() {
  if ((failures > 0)); then
    printf '%d failure(s)\n' "$failures"
    exit 1
  fi
}
```

- [ ] **Step 7: Run tests and lint**

Run: `nix develop --command make test`
Expected: six `ok   ...` lines under `# test-lib.sh`, and exit code 0.

Run: `nix develop --command make lint`
Expected: `shellcheck -x tests/unit/lib.sh tests/unit/run.sh tests/unit/test-lib.sh`, with no findings and exit code 0.

- [ ] **Step 8: Commit**

```bash
git add flake.nix flake.lock .envrc .gitignore Makefile tests/unit
git commit -m "build(ci): add dev shell, Makefile and unit-test harness"
```

### Task 2: Prove how a called workflow reaches its own commit (done, 2026-10-09)

This task de-risked the one assumption no local tool can check. It ran with a deviation recorded in the ledger. The flake's zizmor 1.30.1 flagged the `./` syntax (audit `self-repository`) and pointed to GitHub's self-repository syntax `uses: $/...` (July 2026). The smoke test therefore compared both mechanisms: the `job.workflow_sha` checkout and a composite loaded through `$/`. Both passed in-repo on PR #1, and from a throwaway caller in `Metrify-App/test-app`. In the cross-repository run, `$/` downloaded `Metrify-App/metrify-workflows@<workflow commit>` with the whole tree. The user then chose `$/`, and spec §4.2 was rewritten.

**Commits:** `8e742eb..b64b88b` (`ci(ci): smoke-test self checkout and the self-repository syntax`). They added:
- `.github/actionlint.yaml`;
- `.github/zizmor.yml`;
- `.github/workflows/smoke.yml`;
- `.github/actions/smoke/action.yml`;
- a `ci.yml` calling `$/.github/workflows/smoke.yml`;
- `actionlint` and `zizmor` in `make lint`.

**Remaining step:** in Task 7, `.github/actionlint.yaml` is replaced (it drops the `job.workflow_*` ignores and keeps the `$/` ones), and the smoke files are deleted.

### Task 3: Image name and tag computation

**Files:**
- Create: `tests/unit/test-image-name.sh`, `tests/unit/test-docker-tags.sh`
- Create: `scripts/image-name.sh`, `scripts/docker-tags.sh`

**Interfaces:**
- Produces: `image-name.sh OWNER/REPO [IMAGE_NAME]` and `docker-tags.sh EVENT REF SHA MODE`, exactly as in "Script interfaces".

- [ ] **Step 1: Write the failing tests**

`tests/unit/test-image-name.sh`:
```bash
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
```

`tests/unit/test-docker-tags.sh`:
```bash
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
```

- [ ] **Step 2: Run them and watch them fail**

Run: `nix develop --command make test`
Expected: FAIL lines such as `FAIL defaults to the repository name (expected status 0, got 127; ...)`, because the scripts do not exist yet.

- [ ] **Step 3: Write `scripts/image-name.sh`**

```bash
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
```

- [ ] **Step 4: Write `scripts/docker-tags.sh`**

```bash
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
```

Run: `chmod +x scripts/image-name.sh scripts/docker-tags.sh`

- [ ] **Step 5: Run tests and lint**

Run: `nix develop --command make test && nix develop --command make lint`
Expected: every line under `# test-docker-tags.sh` and `# test-image-name.sh` starts with `ok`, and both commands exit with 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/image-name.sh scripts/docker-tags.sh tests/unit/test-image-name.sh tests/unit/test-docker-tags.sh
git commit -m "feat(scripts): compute GHCR image name and tags"
```

### Task 4: `make-env` export

**Files:**
- Create: `tests/unit/test-export-make-env.sh`, `scripts/export-make-env.sh`

**Interfaces:**
- Produces: `export-make-env.sh` (lines on stdin, needs `GITHUB_ENV`), exactly as in "Script interfaces".

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# Unit tests for scripts/export-make-env.sh.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"
script="$(dirname "$0")/../../scripts/export-make-env.sh"
GITHUB_ENV=$(mktemp)
export GITHUB_ENV
trap 'rm -f "$GITHUB_ENV"' EXIT
nl=$'\n'

export_env() { printf '%s' "$1" | "$script"; }

run export_env "API_URL=https://example.test${nl}TOKEN=s3cr%t${nl}"
assert_status 0 "accepts KEY=VALUE lines"
assert_contains "::add-mask::https://example.test" "masks the first value"
assert_contains "::add-mask::s3cr%25t" "escapes % in masked values"
assert_not_contains "TOKEN=" "never prints a pair"
output=$(cat "$GITHUB_ENV")
assert_output "API_URL=https://example.test${nl}TOKEN=s3cr%t" "appends the pairs to GITHUB_ENV"

: >"$GITHUB_ENV"
run export_env "${nl}# comment${nl}   ${nl}EMPTY=${nl}A_1=x=y"
assert_status 0 "skips blank and comment lines"
assert_not_contains "::add-mask::${nl}" "does not mask empty values"
output=$(cat "$GITHUB_ENV")
assert_output "EMPTY=${nl}A_1=x=y" "keeps '=' inside values and empty values"

: >"$GITHUB_ENV"
run export_env "B=1"
assert_status 0 "accepts a last line without newline"
output=$(cat "$GITHUB_ENV")
assert_output "B=1" "exports the last line without newline"

: >"$GITHUB_ENV"
run export_env $'C=1\r\n'
output=$(cat "$GITHUB_ENV")
assert_output "C=1" "strips Windows line endings"

: >"$GITHUB_ENV"
run export_env "GOOD=1${nl}not a pair secret-value${nl}"
assert_status 1 "rejects a line without '='"
assert_contains "::error::make-env line 2 is not KEY=VALUE" "names the bad line"
assert_not_contains "secret-value" "never prints the bad line"
output=$(cat "$GITHUB_ENV")
assert_output "" "exports nothing when a line is invalid"

run export_env "1BAD=x"
assert_status 1 "rejects a key starting with a digit"

run export_env "BAD KEY=x"
assert_status 1 "rejects a key with a space"

run env -u GITHUB_ENV bash -c "printf 'A=1' | '$script'"
assert_status 1 "requires GITHUB_ENV"

finish
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nix develop --command make test`
Expected: FAIL lines under `# test-export-make-env.sh` (status 127, script not found).

- [ ] **Step 3: Write `scripts/export-make-env.sh`**

```bash
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
```

Run: `chmod +x scripts/export-make-env.sh`

- [ ] **Step 4: Run tests and lint**

Run: `nix develop --command make test && nix develop --command make lint`
Expected: every line starts with `ok`, and both commands exit with 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/export-make-env.sh tests/unit/test-export-make-env.sh
git commit -m "feat(scripts): validate, mask and export make-env lines"
```

### Task 5: Run a rule and check the built image

**Files:**
- Create: `tests/unit/test-run-make.sh`, `tests/unit/test-check-image.sh`
- Create: `scripts/run-make.sh`, `scripts/check-image.sh`

**Interfaces:**
- Produces: `USE_NIX=... run-make.sh RULE [VAR=VALUE...]` and `check-image.sh IMAGE_REF`, exactly as in "Script interfaces".

- [ ] **Step 1: Write the failing tests**

`tests/unit/test-run-make.sh`. It unsets `MAKEFLAGS`, `MFLAGS` and `MAKELEVEL`: under `make test`, the nested make would otherwise print `Entering directory` lines and break the exact-output assertions.
```bash
#!/usr/bin/env bash
# Unit tests for scripts/run-make.sh.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"
script="$(cd "$(dirname "$0")/../../scripts" && pwd)/run-make.sh"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cd "$workdir" || exit 1
# Isolate from a calling make (`make test`), which would add "Entering directory" lines.
unset MAKEFLAGS MFLAGS MAKELEVEL

cat >Makefile <<'MAKEFILE'
hello:
	@echo hello
show:
	@echo "image=$(IMAGE)"
broken:
	@exit 4
MAKEFILE

run "$script" hello
assert_status 0 "runs an existing rule"
assert_output "hello" "prints the rule output"

run "$script" show IMAGE=ghcr.io/o/r:sha-0123456
assert_output "image=ghcr.io/o/r:sha-0123456" "passes make variables"

run "$script" missing
assert_status 1 "fails on a missing rule"
assert_contains "::error::The Makefile has no 'missing' rule" "explains the missing rule"

run "$script" broken
assert_status 2 "propagates make's failure"
assert_not_contains "::error::" "does not blame the contract when the rule fails"

run "$script"
assert_status 1 "requires a rule"

finish
```

`tests/unit/test-check-image.sh` (it uses a fake `docker` on `PATH`, so no Docker daemon is needed):
```bash
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
```

- [ ] **Step 2: Run them and watch them fail**

Run: `nix develop --command make test`
Expected: FAIL lines under `# test-check-image.sh` and `# test-run-make.sh`.

- [ ] **Step 3: Write `scripts/run-make.sh`**

```bash
#!/usr/bin/env bash
# Runs a Makefile rule, inside `nix develop` when USE_NIX is true.
# Usage: USE_NIX=true|false run-make.sh RULE [VAR=VALUE...]
#   Fails with a contract error annotation when the Makefile has no such rule.
set -euo pipefail

rule=${1:?usage: run-make.sh RULE [VAR=VALUE...]}
shift

runner=()
[[ ${USE_NIX:-false} != true ]] || runner=(nix develop --command)

dry_run=$(mktemp)
trap 'rm -f "$dry_run"' EXIT
if ! "${runner[@]}" make -n "$rule" "$@" >"$dry_run" 2>&1 &&
  grep -qF "No rule to make target '$rule'" "$dry_run"; then
  echo "::error::The Makefile has no '$rule' rule. Add it, or stop calling the $rule workflow (see docs/contract.md in Metrify-App/metrify-workflows)." >&2
  exit 1
fi

"${runner[@]}" make "$rule" "$@"
```

- [ ] **Step 4: Write `scripts/check-image.sh`**

```bash
#!/usr/bin/env bash
# Fails with a contract error annotation when IMAGE_REF does not exist in the local Docker daemon.
# Usage: check-image.sh IMAGE_REF
set -euo pipefail

image=${1:?usage: check-image.sh IMAGE_REF}

if ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "::error::make docker-build did not produce '$image'. The docker-build rule must tag its image with \$(IMAGE) (see docs/contract.md in Metrify-App/metrify-workflows)." >&2
  exit 1
fi
```

Run: `chmod +x scripts/run-make.sh scripts/check-image.sh`

- [ ] **Step 5: Run tests and lint**

Run: `nix develop --command make test && nix develop --command make lint`
Expected: 66 `ok` lines in total and no `FAIL`, and both commands exit with 0. Check with `nix develop --command make test 2>&1 | grep -c '^ok'`, which should print `66`.

- [ ] **Step 6: Commit**

```bash
git add scripts/run-make.sh scripts/check-image.sh tests/unit/test-run-make.sh tests/unit/test-check-image.sh
git commit -m "feat(scripts): run a make rule and check the built image"
```

### Task 6: Internal composites `setup-env` and `run-make`

**Files:**
- Create: `.github/actions/setup-env/action.yml`, `.github/actions/run-make/action.yml`

**Interfaces:**
- Consumes: `scripts/export-make-env.sh` and `scripts/run-make.sh`, reached from a composite as `$GITHUB_ACTION_PATH/../../../scripts/`. This works because a composite loaded through `$/` comes with the whole repository at that commit (checked in Task 2).
- Produces: the two composites described in "Composite interfaces".

- [ ] **Step 1: Write `.github/actions/setup-env/action.yml`**

```yaml
name: setup-env
description: >-
  Internal to metrify-workflows, not a public interface. Installs Nix when the working
  directory has a flake.nix, otherwise the requested fallback toolchains, then restores caches.

inputs:
  working-directory:
    description: Directory that contains the Makefile.
    default: .
  cache-scope:
    description: Segment of the dependency cache key, usually the Makefile rule.
    required: true
  node-version:
    description: Fallback only. Node.js version for actions/setup-node.
    default: ""
  python-version:
    description: Fallback only. Python version for actions/setup-python.
    default: ""
  go-version:
    description: Fallback only. Go version for actions/setup-go.
    default: ""
  cache-paths:
    description: Extra paths to cache, one per line.
    default: ""
  cache-key-files:
    description: Glob, relative to the repository root, hashed into the dependency cache key.
    default: ""

outputs:
  use-nix:
    description: "'true' when the working directory has a flake.nix, 'false' otherwise."
    value: ${{ steps.detect.outputs.use-nix }}

runs:
  using: composite
  steps:
    - name: Detect flake.nix
      id: detect
      shell: bash
      env:
        WORKDIR: ${{ inputs.working-directory }}
        VERSIONS: ${{ inputs.node-version }}${{ inputs.python-version }}${{ inputs.go-version }}
        CACHE_PATHS: ${{ inputs.cache-paths }}
        CACHE_KEY_FILES: ${{ inputs.cache-key-files }}
      run: |
        if [[ -n $CACHE_PATHS && -z $CACHE_KEY_FILES ]]; then
          echo "::error::cache-paths is set but cache-key-files is empty: the cache would never be refreshed."
          exit 1
        fi
        if [[ -f "$WORKDIR/flake.nix" ]]; then
          echo "use-nix=true" >>"$GITHUB_OUTPUT"
          if [[ -n $VERSIONS ]]; then
            echo "::warning::$WORKDIR/flake.nix found: node-version, python-version and go-version are ignored, the Nix dev shell provides the tools."
          fi
        else
          echo "use-nix=false" >>"$GITHUB_OUTPUT"
        fi

    - name: Install Nix
      if: steps.detect.outputs.use-nix == 'true'
      uses: DeterminateSystems/nix-installer-action@3138316df39ed29be04236d7ffc686fa525866aa # v23
      with:
        determinate: false

    - name: Cache the Nix store
      if: steps.detect.outputs.use-nix == 'true'
      uses: nix-community/cache-nix-action@7df957e333c1e5da7721f60227dbba6d06080569 # v7
      with:
        primary-key: nix-${{ runner.os }}-${{ runner.arch }}-${{ hashFiles(format('{0}/flake.nix', inputs.working-directory), format('{0}/flake.lock', inputs.working-directory)) }}
        restore-prefixes-first-match: nix-${{ runner.os }}-${{ runner.arch }}-
        gc-max-store-size-linux: 1G

    - name: Set up Node.js
      if: steps.detect.outputs.use-nix == 'false' && inputs.node-version != ''
      uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
      with:
        node-version: ${{ inputs.node-version }}
        package-manager-cache: false

    - name: Set up Python
      if: steps.detect.outputs.use-nix == 'false' && inputs.python-version != ''
      uses: actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97 # v7.0.0
      with:
        python-version: ${{ inputs.python-version }}

    - name: Set up Go
      if: steps.detect.outputs.use-nix == 'false' && inputs.go-version != ''
      uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
      with:
        go-version: ${{ inputs.go-version }}
        cache: false

    - name: Cache dependencies
      if: inputs.cache-paths != ''
      uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0
      with:
        path: ${{ inputs.cache-paths }}
        key: deps-${{ runner.os }}-${{ runner.arch }}-${{ inputs.cache-scope }}-${{ hashFiles(inputs.cache-key-files) }}
        restore-keys: deps-${{ runner.os }}-${{ runner.arch }}-${{ inputs.cache-scope }}-
```

- [ ] **Step 2: Write `.github/actions/run-make/action.yml`**

```yaml
name: run-make
description: >-
  Internal to metrify-workflows, not a public interface. Exports make-env, checks that the
  Makefile has the rule, then runs it (inside `nix develop` when use-nix is 'true').

inputs:
  rule:
    description: Makefile rule to run.
    required: true
  working-directory:
    description: Directory that contains the Makefile.
    default: .
  use-nix:
    description: "'true' to run make inside `nix develop`."
    default: "false"
  make-args:
    description: Space-separated VAR=VALUE words passed to make. Values cannot contain spaces.
    default: ""
  make-env:
    description: KEY=VALUE lines exported (masked) before make runs.
    default: ""

runs:
  using: composite
  steps:
    - name: Export make-env
      if: inputs.make-env != ''
      shell: bash
      env:
        MAKE_ENV: ${{ inputs.make-env }}
      run: printf '%s\n' "$MAKE_ENV" | "$GITHUB_ACTION_PATH/../../../scripts/export-make-env.sh"

    - name: make ${{ inputs.rule }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        RULE: ${{ inputs.rule }}
        USE_NIX: ${{ inputs.use-nix }}
        MAKE_ARGS: ${{ inputs.make-args }}
      run: |
        read -ra args <<<"$MAKE_ARGS"
        "$GITHUB_ACTION_PATH/../../../scripts/run-make.sh" "$RULE" "${args[@]}"
```

- [ ] **Step 3: Lint**

Run: `nix develop --command make lint && nix develop --command make test`
Expected: zizmor lists both `action.yml` files as audited and ends with `No findings to report.`, and both commands exit with 0. The composites are exercised on GitHub in Task 7.

- [ ] **Step 4: Commit**

```bash
git add .github/actions
git commit -m "feat(setup-env,run-make): add internal composite actions"
```

### Task 7: `lint`, `test` and `build` workflows with self-tests

**Files:**
- Create: `.github/workflows/lint.yml`, `.github/workflows/test.yml`, `.github/workflows/build.yml`
- Create: `tests/fixtures/plain/Makefile`, `tests/fixtures/plain/Dockerfile`
- Replace: `.github/workflows/ci.yml`, `.github/actionlint.yaml`, `Makefile`, `flake.nix` (adds `act`), `.gitignore`
- Create: `tests/act/run.sh`
- Delete: `.github/workflows/smoke.yml`, `.github/actions/smoke/action.yml`

**Interfaces:**
- Consumes: the composites from Task 6.
- Produces: the public workflows `lint.yml`, `test.yml` and `build.yml` with the inputs from spec §5.1.

- [ ] **Step 1: Write `.github/workflows/lint.yml`**

```yaml
name: lint

# Public workflow: runs `make lint` (style and code quality) in the calling repository.
# Reference: docs/workflows.md. Makefile contract: docs/contract.md.

on:
  workflow_call:
    inputs:
      working-directory:
        description: Directory that contains the Makefile.
        type: string
        default: .
      runs-on:
        description: Runner label.
        type: string
        default: ubuntu-latest
      timeout-minutes:
        description: Job timeout in minutes.
        type: number
        default: 30
      node-version:
        description: Fallback only (no flake.nix). Node.js version to install.
        type: string
        default: ""
      python-version:
        description: Fallback only (no flake.nix). Python version to install.
        type: string
        default: ""
      go-version:
        description: Fallback only (no flake.nix). Go version to install.
        type: string
        default: ""
      cache-paths:
        description: Extra paths to cache, one per line. Requires cache-key-files.
        type: string
        default: ""
      cache-key-files:
        description: Glob, relative to the repository root, hashed into the cache key.
        type: string
        default: ""
    secrets:
      make-env:
        description: KEY=VALUE lines exported (masked) before make runs.
        required: false

permissions: {}

defaults:
  run:
    shell: bash

jobs:
  lint:
    name: make lint
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    permissions:
      contents: read
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      # `$/` loads the composites from this library at the commit of this workflow, whatever
      # ref the caller used (@v1, @main, a SHA). No checkout of the library is needed.
      - name: Set up environment
        id: env
        uses: $/.github/actions/setup-env
        with:
          working-directory: ${{ inputs.working-directory }}
          cache-scope: lint
          node-version: ${{ inputs.node-version }}
          python-version: ${{ inputs.python-version }}
          go-version: ${{ inputs.go-version }}
          cache-paths: ${{ inputs.cache-paths }}
          cache-key-files: ${{ inputs.cache-key-files }}

      - name: Run make lint
        uses: $/.github/actions/run-make
        with:
          rule: lint
          working-directory: ${{ inputs.working-directory }}
          use-nix: ${{ steps.env.outputs.use-nix }}
          make-env: ${{ secrets.make-env }}
```

- [ ] **Step 2: Write `.github/workflows/test.yml`**

```yaml
name: test

# Public workflow: runs `make test` (the tests) in the calling repository.
# Reference: docs/workflows.md. Makefile contract: docs/contract.md.

on:
  workflow_call:
    inputs:
      working-directory:
        description: Directory that contains the Makefile.
        type: string
        default: .
      runs-on:
        description: Runner label.
        type: string
        default: ubuntu-latest
      timeout-minutes:
        description: Job timeout in minutes.
        type: number
        default: 30
      node-version:
        description: Fallback only (no flake.nix). Node.js version to install.
        type: string
        default: ""
      python-version:
        description: Fallback only (no flake.nix). Python version to install.
        type: string
        default: ""
      go-version:
        description: Fallback only (no flake.nix). Go version to install.
        type: string
        default: ""
      cache-paths:
        description: Extra paths to cache, one per line. Requires cache-key-files.
        type: string
        default: ""
      cache-key-files:
        description: Glob, relative to the repository root, hashed into the cache key.
        type: string
        default: ""
    secrets:
      make-env:
        description: KEY=VALUE lines exported (masked) before make runs.
        required: false

permissions: {}

defaults:
  run:
    shell: bash

jobs:
  test:
    name: make test
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    permissions:
      contents: read
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      # `$/` loads the composites from this library at the commit of this workflow, whatever
      # ref the caller used (@v1, @main, a SHA). No checkout of the library is needed.
      - name: Set up environment
        id: env
        uses: $/.github/actions/setup-env
        with:
          working-directory: ${{ inputs.working-directory }}
          cache-scope: test
          node-version: ${{ inputs.node-version }}
          python-version: ${{ inputs.python-version }}
          go-version: ${{ inputs.go-version }}
          cache-paths: ${{ inputs.cache-paths }}
          cache-key-files: ${{ inputs.cache-key-files }}

      - name: Run make test
        uses: $/.github/actions/run-make
        with:
          rule: test
          working-directory: ${{ inputs.working-directory }}
          use-nix: ${{ steps.env.outputs.use-nix }}
          make-env: ${{ secrets.make-env }}
```

- [ ] **Step 3: Write `.github/workflows/build.yml`**

```yaml
name: build

# Public workflow: runs `make build` (compilation) in the calling repository.
# Reference: docs/workflows.md. Makefile contract: docs/contract.md.

on:
  workflow_call:
    inputs:
      working-directory:
        description: Directory that contains the Makefile.
        type: string
        default: .
      runs-on:
        description: Runner label.
        type: string
        default: ubuntu-latest
      timeout-minutes:
        description: Job timeout in minutes.
        type: number
        default: 30
      node-version:
        description: Fallback only (no flake.nix). Node.js version to install.
        type: string
        default: ""
      python-version:
        description: Fallback only (no flake.nix). Python version to install.
        type: string
        default: ""
      go-version:
        description: Fallback only (no flake.nix). Go version to install.
        type: string
        default: ""
      cache-paths:
        description: Extra paths to cache, one per line. Requires cache-key-files.
        type: string
        default: ""
      cache-key-files:
        description: Glob, relative to the repository root, hashed into the cache key.
        type: string
        default: ""
    secrets:
      make-env:
        description: KEY=VALUE lines exported (masked) before make runs.
        required: false

permissions: {}

defaults:
  run:
    shell: bash

jobs:
  build:
    name: make build
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    permissions:
      contents: read
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      # `$/` loads the composites from this library at the commit of this workflow, whatever
      # ref the caller used (@v1, @main, a SHA). No checkout of the library is needed.
      - name: Set up environment
        id: env
        uses: $/.github/actions/setup-env
        with:
          working-directory: ${{ inputs.working-directory }}
          cache-scope: build
          node-version: ${{ inputs.node-version }}
          python-version: ${{ inputs.python-version }}
          go-version: ${{ inputs.go-version }}
          cache-paths: ${{ inputs.cache-paths }}
          cache-key-files: ${{ inputs.cache-key-files }}

      - name: Run make build
        uses: $/.github/actions/run-make
        with:
          rule: build
          working-directory: ${{ inputs.working-directory }}
          use-nix: ${{ steps.env.outputs.use-nix }}
          make-env: ${{ secrets.make-env }}
```

- [ ] **Step 4: Write the fixture consumer `tests/fixtures/plain/`**

`tests/fixtures/plain/Makefile`:
```make
# Fixture consumer for the library self-tests (.github/workflows/ci.yml). Not a template:
# the rules check what the self-tests configure (tool versions, make-env, cache paths).
IMAGE ?= metrify-workflows-fixture:dev

.PHONY: lint test build docker-build

lint:
	node --version | grep '^v24\.'

test:
	@test -n "$$FIXTURE_TOKEN" || { echo "FIXTURE_TOKEN is not set: make-env was not exported"; exit 1; }
	@echo "FIXTURE_TOKEN=$$FIXTURE_TOKEN (must show *** in the CI log)"
	mkdir -p .cache
	date >.cache/last-run

build:
	python3 --version | grep '^Python 3\.14'
	go version | grep ' go1\.26'

docker-build:
	docker build -t $(IMAGE) .
```

`tests/fixtures/plain/Dockerfile`:
```dockerfile
FROM busybox:1.37
CMD ["true"]
```

- [ ] **Step 5: Replace `.github/workflows/ci.yml`** (`smoke.yml` is deleted in Step 7, in the second commit)

```yaml
name: ci

# CI of the library itself: dogfooding (lint and test of this repository through its own
# workflows), self-tests on fixtures, and contract error cases.

on:
  pull_request:
  push:
    branches: [main]

permissions: {}

defaults:
  run:
    shell: bash

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    name: library / lint
    uses: $/.github/workflows/lint.yml
    permissions:
      contents: read

  test:
    name: library / test
    uses: $/.github/workflows/test.yml
    permissions:
      contents: read

  fixture-lint:
    name: fixture / lint
    uses: $/.github/workflows/lint.yml
    permissions:
      contents: read
    with:
      working-directory: tests/fixtures/plain
      node-version: "24"

  fixture-test:
    name: fixture / test
    uses: $/.github/workflows/test.yml
    permissions:
      contents: read
    with:
      working-directory: tests/fixtures/plain
      cache-paths: tests/fixtures/plain/.cache
      cache-key-files: tests/fixtures/plain/Makefile
    secrets:
      make-env: ${{ format('FIXTURE_TOKEN=run-{0}', github.run_id) }}

  fixture-build:
    name: fixture / build
    uses: $/.github/workflows/build.yml
    permissions:
      contents: read
    with:
      working-directory: tests/fixtures/plain
      python-version: "3.14"
      go-version: "1.26"

  contract-errors:
    name: contract errors
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Missing rule
        id: missing-rule
        continue-on-error: true
        uses: $/.github/actions/run-make
        with:
          rule: missing
          working-directory: tests/fixtures/plain

      - name: Malformed make-env
        id: bad-env
        continue-on-error: true
        uses: $/.github/actions/run-make
        with:
          rule: lint
          working-directory: tests/fixtures/plain
          make-env: not a pair

      - name: Cache paths without key files
        id: bad-cache
        continue-on-error: true
        uses: $/.github/actions/setup-env
        with:
          cache-scope: test
          cache-paths: tests/fixtures/plain/.cache

      - name: Every case must have failed
        env:
          MISSING_RULE: ${{ steps.missing-rule.outcome }}
          BAD_ENV: ${{ steps.bad-env.outcome }}
          BAD_CACHE: ${{ steps.bad-cache.outcome }}
        run: |
          status=0
          for case in MISSING_RULE BAD_ENV BAD_CACHE; do
            if [[ ${!case} == failure ]]; then
              echo "ok   $case failed as expected"
            else
              echo "::error::$case: expected failure, got ${!case}"
              status=1
            fi
          done
          exit "$status"
```

- [ ] **Step 5b: Local tooling: actionlint config, act runner, Makefile, flake and .gitignore**

`.github/actionlint.yaml` (the `job.workflow_*` ignores from Task 2 are no longer needed):
```yaml
# actionlint 1.7.12 predates GitHub's self-repository syntax (`uses: $/...`, July 2026).
paths:
  .github/workflows/**/*.{yml,yaml}:
    ignore:
      - 'specifying action "\$/[^"]+" in invalid format because ref is missing'
      - 'reusable workflow call "\$/[^"]+" at "uses" is not following the format'
```

`tests/act/run.sh` (make it executable):
```bash
#!/usr/bin/env bash
# Runs the library's CI locally with act, on a copy of the working tree.
# Usage: tests/act/run.sh [act arguments...]   e.g. tests/act/run.sh -j fixture-test
#   act 0.2.x does not support the self-repository syntax (`uses: $/...`, nektos/act#6189).
#   In this repository `$/` and `./` resolve to the same code, so the copy rewrites one into
#   the other. Jobs that install Nix (library / lint, library / test) need a systemd host and
#   are better checked with `make lint test` directly.
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
```

`Makefile`:
```make
# Checks of the library itself. Run inside the dev shell: `nix develop --command make <rule>`
# (direnv users: `use flake`). CI runs the same rules through the library's own workflows.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-6s\033[0m %s\n", $$1, $$2}'

.PHONY: lint
lint: ## Static analysis of workflows, actions and scripts
	actionlint
	zizmor --offline --config .github/zizmor.yml $(wildcard .github examples tests)
	shellcheck -x $(wildcard scripts/*.sh tests/unit/*.sh tests/act/*.sh)

.PHONY: test
test: ## Unit tests of the scripts
	tests/unit/run.sh

.PHONY: act
act: ## Run ci.yml locally with act; pass act options in ARGS, e.g. ARGS="-j fixture-test"
	tests/act/run.sh $(ARGS)
```

`flake.nix`:
```nix
{
  description = "Metrify reusable GitHub Actions workflows: development shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            gnumake
            actionlint
            zizmor
            shellcheck
            act
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
```

`.gitignore`:
```
.direnv/
tests/fixtures/plain/.cache/
```

- [ ] **Step 6: Lint locally**

Run: `nix develop --command make lint && nix develop --command make test`
Expected: both commands exit with 0, and zizmor reports `No findings to report.`

- [ ] **Step 7: Commit in two micro commits**

```bash
git add .github/workflows/lint.yml .github/workflows/test.yml .github/workflows/build.yml
git commit -m "feat(lint,test,build): add public make-rule workflows"
git rm -r .github/workflows/smoke.yml .github/actions/smoke
git add tests/fixtures/plain .github/workflows/ci.yml .github/actionlint.yaml
git commit -m "test(ci): self-test workflows on the library and a plain fixture"
git add tests/act Makefile flake.nix .gitignore
git commit -m "build(ci): run ci.yml locally with act"
```

Make the first commit right after Step 3, while the Task 2 `ci.yml` is still in place, and the other two after Step 6. Run `nix develop --command make lint` before each one.

- [ ] **Step 7b: Run a fixture job locally with act**

Run: `nix develop --command make act ARGS="-j fixture-lint"`
Expected: the job ends with `🏁  Job succeeded`, and the log shows `v24.` from `node --version`. The first run pulls `catthehacker/ubuntu:act-latest`.

- [ ] **Step 8: Push and watch CI**

Run: `git push && gh run watch --exit-status "$(gh run list --branch reusable-workflows --workflow ci --limit 1 --json databaseId --jq '.[0].databaseId')"`
Expected: all jobs green, namely `library / lint`, `library / test` (Nix path, with the "Cache the Nix store" step present), `fixture / lint`, `fixture / test`, `fixture / build` and `contract errors`. The last one passes because its three cases fail as expected (`ok   MISSING_RULE failed as expected`, and the same for `BAD_ENV` and `BAD_CACHE`).

- [ ] **Step 9: Check the masking (Review Focus 2) and the error annotations**

Run: `gh run view --log "$(gh run list --branch reusable-workflows --workflow ci --limit 1 --json databaseId --jq '.[0].databaseId')" | grep -E 'FIXTURE_TOKEN=|has no .missing. rule|make-env line'`
Expected:
- `FIXTURE_TOKEN=*** (must show *** in the CI log)`, with no `run-<digits>` value visible;
- `The Makefile has no 'missing' rule`;
- `make-env line 1 is not KEY=VALUE`.

If the token value appears in clear, STOP and report it: this is a secret-handling bug.

### Task 8: `docker` workflow

**Files:**
- Create: `.github/actions/image-meta/action.yml`, `.github/actions/image-push/action.yml`
- Create: `.github/workflows/docker.yml`, `tests/fixtures/bad-image/Makefile`, `tests/fixtures/bad-image/Dockerfile`
- Modify: `.github/workflows/ci.yml` (add two jobs and two steps)

**Interfaces:**
- Consumes: `image-name.sh` and `docker-tags.sh` (from `image-meta`), `check-image.sh` (from `image-push`), all reached as `$GITHUB_ACTION_PATH/../../../scripts/`, plus `setup-env` and `run-make`.
- Produces: the `image-meta` and `image-push` composites described in "Composite interfaces".
- Produces: the public `docker.yml` with inputs `image-name` and `push`, and outputs `image`, `tags` and `digest` (spec §5.2).

- [ ] **Step 0: Write the Docker composites.** Workflow `run:` steps cannot reach `scripts/` without a checkout, so all Docker logic lives in composites loaded through `$/`.

`.github/actions/image-meta/action.yml`:
```yaml
name: image-meta
description: >-
  Internal to metrify-workflows, not a public interface. Computes the GHCR image name, the
  reference to build and the tags to push, from the calling repository and event.

inputs:
  image-name:
    description: Image name under ghcr.io/<owner>/. Empty means the repository name.
    default: ""
  push:
    description: auto, always or never.
    default: auto

outputs:
  image:
    description: Full image name, without tag.
    value: ${{ steps.meta.outputs.image }}
  build-ref:
    description: Reference `make docker-build` must produce (<image>:sha-<short sha>).
    value: ${{ steps.meta.outputs.build-ref }}
  tag-list:
    description: Space-separated tags to push, empty when nothing must be pushed.
    value: ${{ steps.meta.outputs.tag-list }}

runs:
  using: composite
  steps:
    - name: Compute image name and tags
      id: meta
      shell: bash
      env:
        REPOSITORY: ${{ github.repository }}
        IMAGE_NAME: ${{ inputs.image-name }}
        EVENT: ${{ github.event_name }}
        REF: ${{ github.ref }}
        SHA: ${{ github.event.pull_request.head.sha || github.sha }}
        PUSH_MODE: ${{ inputs.push }}
      run: |
        scripts="$GITHUB_ACTION_PATH/../../../scripts"
        image=$("$scripts/image-name.sh" "$REPOSITORY" "$IMAGE_NAME")
        tags=$("$scripts/docker-tags.sh" "$EVENT" "$REF" "$SHA" "$PUSH_MODE")
        {
          echo "image=$image"
          echo "build-ref=$image:sha-${SHA:0:7}"
          echo "tag-list=${tags//$'\n'/ }"
        } >>"$GITHUB_OUTPUT"
```

`.github/actions/image-push/action.yml`:
```yaml
name: image-push
description: >-
  Internal to metrify-workflows, not a public interface. Checks that `make docker-build`
  produced the expected image, then tags it and pushes it to GHCR when tags are given.

inputs:
  image:
    description: Full image name, without tag.
    required: true
  build-ref:
    description: Reference `make docker-build` was asked to produce.
    required: true
  tag-list:
    description: Space-separated tags to push. Empty means check only.
    default: ""

outputs:
  tags:
    description: Newline-separated image references that were pushed, empty if none.
    value: ${{ steps.push.outputs.tags }}
  digest:
    description: Digest of the pushed image, empty if nothing was pushed.
    value: ${{ steps.push.outputs.digest }}

runs:
  using: composite
  steps:
    - name: Check the image honours $(IMAGE)
      shell: bash
      env:
        BUILD_REF: ${{ inputs.build-ref }}
      run: '"$GITHUB_ACTION_PATH/../../../scripts/check-image.sh" "$BUILD_REF"'

    - name: Log in to GHCR
      if: inputs.tag-list != ''
      uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ github.token }}

    - name: Tag and push
      id: push
      if: inputs.tag-list != ''
      shell: bash
      env:
        IMAGE: ${{ inputs.image }}
        BUILD_REF: ${{ inputs.build-ref }}
        TAG_LIST: ${{ inputs.tag-list }}
      run: |
        read -ra tags <<<"$TAG_LIST"
        refs=()
        for tag in "${tags[@]}"; do
          docker tag "$BUILD_REF" "$IMAGE:$tag"
          docker push "$IMAGE:$tag"
          refs+=("$IMAGE:$tag")
        done
        digest=$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$BUILD_REF" |
          grep -m1 "^$IMAGE@" | cut -d@ -f2)
        {
          echo "digest=$digest"
          echo "tags<<METRIFY_TAGS"
          printf '%s\n' "${refs[@]}"
          echo "METRIFY_TAGS"
        } >>"$GITHUB_OUTPUT"
```

- [ ] **Step 1: Write `.github/workflows/docker.yml`**

```yaml
name: docker

# Public workflow: runs `make docker-build IMAGE=<name>`, then tags and pushes the image to
# GHCR according to the event and the push mode.
# Reference: docs/workflows.md. Makefile contract: docs/contract.md.
# The calling job must grant `contents: read` and `packages: write`.

on:
  workflow_call:
    inputs:
      working-directory:
        description: Directory that contains the Makefile.
        type: string
        default: .
      runs-on:
        description: Runner label.
        type: string
        default: ubuntu-latest
      timeout-minutes:
        description: Job timeout in minutes.
        type: number
        default: 30
      node-version:
        description: Fallback only (no flake.nix). Node.js version to install.
        type: string
        default: ""
      python-version:
        description: Fallback only (no flake.nix). Python version to install.
        type: string
        default: ""
      go-version:
        description: Fallback only (no flake.nix). Go version to install.
        type: string
        default: ""
      cache-paths:
        description: Extra paths to cache, one per line. Requires cache-key-files.
        type: string
        default: ""
      cache-key-files:
        description: Glob, relative to the repository root, hashed into the cache key.
        type: string
        default: ""
      image-name:
        description: Image name under ghcr.io/<owner>/. Defaults to the repository name.
        type: string
        default: ""
      push:
        description: "auto (push depends on the event), always or never."
        type: string
        default: auto
    secrets:
      make-env:
        description: KEY=VALUE lines exported (masked) before make runs.
        required: false
    outputs:
      image:
        description: Full image name, without tag.
        value: ${{ jobs.docker.outputs.image }}
      tags:
        description: Newline-separated image references that were pushed, empty if none.
        value: ${{ jobs.docker.outputs.tags }}
      digest:
        description: Digest of the pushed image, empty if nothing was pushed.
        value: ${{ jobs.docker.outputs.digest }}

permissions: {}

defaults:
  run:
    shell: bash

jobs:
  docker:
    name: make docker-build
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    permissions:
      contents: read
      packages: write
    outputs:
      image: ${{ steps.meta.outputs.image }}
      tags: ${{ steps.push.outputs.tags }}
      digest: ${{ steps.push.outputs.digest }}
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      # `$/` loads the composites from this library at the commit of this workflow, whatever
      # ref the caller used (@v1, @main, a SHA). No checkout of the library is needed.
      # Before the build, so a bad tag or push mode fails fast.
      - name: Compute image name and tags
        id: meta
        uses: $/.github/actions/image-meta
        with:
          image-name: ${{ inputs.image-name }}
          push: ${{ inputs.push }}

      - name: Set up environment
        id: env
        uses: $/.github/actions/setup-env
        with:
          working-directory: ${{ inputs.working-directory }}
          cache-scope: docker-build
          node-version: ${{ inputs.node-version }}
          python-version: ${{ inputs.python-version }}
          go-version: ${{ inputs.go-version }}
          cache-paths: ${{ inputs.cache-paths }}
          cache-key-files: ${{ inputs.cache-key-files }}

      - name: Run make docker-build
        uses: $/.github/actions/run-make
        with:
          rule: docker-build
          working-directory: ${{ inputs.working-directory }}
          use-nix: ${{ steps.env.outputs.use-nix }}
          make-args: IMAGE=${{ steps.meta.outputs.build-ref }}
          make-env: ${{ secrets.make-env }}

      - name: Check, tag and push the image
        id: push
        uses: $/.github/actions/image-push
        with:
          image: ${{ steps.meta.outputs.image }}
          build-ref: ${{ steps.meta.outputs.build-ref }}
          tag-list: ${{ steps.meta.outputs.tag-list }}
```

- [ ] **Step 2: Write the `bad-image` fixture**

`tests/fixtures/bad-image/Makefile`:
```make
# Fixture consumer whose docker-build ignores $(IMAGE): ci.yml checks the contract error.
.PHONY: docker-build

docker-build:
	docker build -t metrify-workflows-bad-image:dev .
```

`tests/fixtures/bad-image/Dockerfile`:
```dockerfile
FROM busybox:1.37
CMD ["true"]
```

- [ ] **Step 3: Add the docker self-tests to `ci.yml`.** Insert these two jobs just before `  contract-errors:`:

```yaml
  fixture-docker:
    name: fixture / docker
    uses: $/.github/workflows/docker.yml
    permissions:
      contents: read
      packages: write
    with:
      working-directory: tests/fixtures/plain
      image-name: metrify-workflows-fixture
      push: never

  fixture-docker-outputs:
    name: fixture / docker outputs
    needs: fixture-docker
    runs-on: ubuntu-latest
    permissions: {}
    steps:
      - name: Check the outputs of a build-only run
        env:
          IMAGE: ${{ needs.fixture-docker.outputs.image }}
          TAGS: ${{ needs.fixture-docker.outputs.tags }}
          DIGEST: ${{ needs.fixture-docker.outputs.digest }}
        run: |
          test "$IMAGE" = "ghcr.io/metrify-app/metrify-workflows-fixture"
          test -z "$TAGS"
          test -z "$DIGEST"

```

In `contract-errors`, insert these steps just before `      - name: Every case must have failed`:

```yaml
      - name: Build an image that ignores $(IMAGE)
        uses: $/.github/actions/run-make
        with:
          rule: docker-build
          working-directory: tests/fixtures/bad-image
          make-args: IMAGE=ghcr.io/metrify-app/bad-image:sha-0000000

      - name: Check the image
        id: bad-image
        continue-on-error: true
        uses: $/.github/actions/image-push
        with:
          image: ghcr.io/metrify-app/bad-image
          build-ref: ghcr.io/metrify-app/bad-image:sha-0000000

```

In the `Every case must have failed` step, add `BAD_IMAGE: ${{ steps.bad-image.outcome }}` under `env:` (after `BAD_CACHE`), and change the loop line to `for case in MISSING_RULE BAD_ENV BAD_CACHE BAD_IMAGE; do`.

The resulting `ci.yml` must be exactly:

```yaml
name: ci

# CI of the library itself: dogfooding (lint and test of this repository through its own
# workflows), self-tests on fixtures, and contract error cases.

on:
  pull_request:
  push:
    branches: [main]

permissions: {}

defaults:
  run:
    shell: bash

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    name: library / lint
    uses: $/.github/workflows/lint.yml
    permissions:
      contents: read

  test:
    name: library / test
    uses: $/.github/workflows/test.yml
    permissions:
      contents: read

  fixture-lint:
    name: fixture / lint
    uses: $/.github/workflows/lint.yml
    permissions:
      contents: read
    with:
      working-directory: tests/fixtures/plain
      node-version: "24"

  fixture-test:
    name: fixture / test
    uses: $/.github/workflows/test.yml
    permissions:
      contents: read
    with:
      working-directory: tests/fixtures/plain
      cache-paths: tests/fixtures/plain/.cache
      cache-key-files: tests/fixtures/plain/Makefile
    secrets:
      make-env: ${{ format('FIXTURE_TOKEN=run-{0}', github.run_id) }}

  fixture-build:
    name: fixture / build
    uses: $/.github/workflows/build.yml
    permissions:
      contents: read
    with:
      working-directory: tests/fixtures/plain
      python-version: "3.14"
      go-version: "1.26"

  fixture-docker:
    name: fixture / docker
    uses: $/.github/workflows/docker.yml
    permissions:
      contents: read
      packages: write
    with:
      working-directory: tests/fixtures/plain
      image-name: metrify-workflows-fixture
      push: never

  fixture-docker-outputs:
    name: fixture / docker outputs
    needs: fixture-docker
    runs-on: ubuntu-latest
    permissions: {}
    steps:
      - name: Check the outputs of a build-only run
        env:
          IMAGE: ${{ needs.fixture-docker.outputs.image }}
          TAGS: ${{ needs.fixture-docker.outputs.tags }}
          DIGEST: ${{ needs.fixture-docker.outputs.digest }}
        run: |
          test "$IMAGE" = "ghcr.io/metrify-app/metrify-workflows-fixture"
          test -z "$TAGS"
          test -z "$DIGEST"

  contract-errors:
    name: contract errors
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Missing rule
        id: missing-rule
        continue-on-error: true
        uses: $/.github/actions/run-make
        with:
          rule: missing
          working-directory: tests/fixtures/plain

      - name: Malformed make-env
        id: bad-env
        continue-on-error: true
        uses: $/.github/actions/run-make
        with:
          rule: lint
          working-directory: tests/fixtures/plain
          make-env: not a pair

      - name: Cache paths without key files
        id: bad-cache
        continue-on-error: true
        uses: $/.github/actions/setup-env
        with:
          cache-scope: test
          cache-paths: tests/fixtures/plain/.cache

      - name: Build an image that ignores $(IMAGE)
        uses: $/.github/actions/run-make
        with:
          rule: docker-build
          working-directory: tests/fixtures/bad-image
          make-args: IMAGE=ghcr.io/metrify-app/bad-image:sha-0000000

      - name: Check the image
        id: bad-image
        continue-on-error: true
        uses: $/.github/actions/image-push
        with:
          image: ghcr.io/metrify-app/bad-image
          build-ref: ghcr.io/metrify-app/bad-image:sha-0000000

      - name: Every case must have failed
        env:
          MISSING_RULE: ${{ steps.missing-rule.outcome }}
          BAD_ENV: ${{ steps.bad-env.outcome }}
          BAD_CACHE: ${{ steps.bad-cache.outcome }}
          BAD_IMAGE: ${{ steps.bad-image.outcome }}
        run: |
          status=0
          for case in MISSING_RULE BAD_ENV BAD_CACHE BAD_IMAGE; do
            if [[ ${!case} == failure ]]; then
              echo "ok   $case failed as expected"
            else
              echo "::error::$case: expected failure, got ${!case}"
              status=1
            fi
          done
          exit "$status"
```

- [ ] **Step 4: Lint**

Run: `nix develop --command make lint && nix develop --command make test`
Expected: both commands exit with 0.

- [ ] **Step 5: Commit**

```bash
git add .github/actions/image-meta .github/actions/image-push .github/workflows/docker.yml
git commit -m "feat(docker): build with make docker-build and push to GHCR"
git add tests/fixtures/bad-image .github/workflows/ci.yml
git commit -m "test(ci): self-test the docker workflow and the IMAGE contract"
```

- [ ] **Step 6: Push and watch CI**

Run: `git push && gh run watch --exit-status "$(gh run list --branch reusable-workflows --workflow ci --limit 1 --json databaseId --jq '.[0].databaseId')"`
Expected:
- all jobs are green;
- in `fixture / docker`, the steps "Log in to GHCR" and "Tag and push" are **skipped** (`push: never`);
- `fixture / docker outputs` passes;
- `contract errors` prints `ok   BAD_IMAGE failed as expected`.

### Task 9: Release automation and Dependabot

**Files:**
- Create: `release-please-config.json`, `.release-please-manifest.json`, `version.txt`, `CHANGELOG.md`, `.github/workflows/release.yml`, `.github/dependabot.yml`

- [ ] **Step 1: Write the release-please files**

`release-please-config.json`:
```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "simple",
  "include-component-in-tag": false,
  "packages": {
    ".": {
      "release-as": "1.0.0"
    }
  }
}
```

`.release-please-manifest.json`:
```json
{ ".": "0.0.0" }
```

`version.txt`:
```
0.0.0
```

`CHANGELOG.md`:
```markdown
# Changelog
```

- [ ] **Step 2: Check release-please's expectations for the `simple` type**

Run: `gh api "repos/googleapis/release-please/contents/src/strategies/simple.ts" --jq .content | base64 -d | grep -n "version.txt\|versionFile"`
Expected: the strategy updates `version.txt` (its default `versionFile`). If the output shows another default file, rename `version.txt` accordingly and update spec §4.1 in the same commit.

- [ ] **Step 3: Write `.github/workflows/release.yml`**

```yaml
name: release

# Keeps a release pull request open from Conventional Commits (release-please). Merging it
# tags vX.Y.Z and creates the GitHub Release; then the floating major tag vX is moved.
# Process: docs/releasing.md.

on:
  push:
    branches: [main]

permissions: {}

concurrency:
  group: release
  cancel-in-progress: false

jobs:
  release-please:
    name: release-please
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: write
      pull-requests: write
    outputs:
      release-created: ${{ steps.release.outputs.release_created }}
      major: ${{ steps.release.outputs.major }}
      sha: ${{ steps.release.outputs.sha }}
    steps:
      - name: Run release-please
        id: release
        uses: googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7 # v5.0.0
        with:
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json

  major-tag:
    name: move major tag
    needs: release-please
    if: needs.release-please.outputs.release-created == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: write
    steps:
      - name: Point vX at the release commit
        shell: bash
        env:
          GH_TOKEN: ${{ github.token }}
          REPOSITORY: ${{ github.repository }}
          MAJOR: ${{ needs.release-please.outputs.major }}
          SHA: ${{ needs.release-please.outputs.sha }}
        run: |
          tag="v$MAJOR"
          if gh api "repos/$REPOSITORY/git/ref/tags/$tag" >/dev/null 2>&1; then
            gh api --method PATCH "repos/$REPOSITORY/git/refs/tags/$tag" -f sha="$SHA" -F force=true
          else
            gh api --method POST "repos/$REPOSITORY/git/refs" -f ref="refs/tags/$tag" -f sha="$SHA"
          fi
          echo "$tag -> $SHA"
```

- [ ] **Step 4: Write `.github/dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directories:
      - /
      - /.github/actions/*
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
    commit-message:
      prefix: build
      include: scope
```

- [ ] **Step 5: Lint**

Run: `nix develop --command make lint && nix develop --command make test && jq . release-please-config.json .release-please-manifest.json >/dev/null`
Expected: every command exits with 0, and zizmor reports no finding for `release.yml` or `dependabot.yml`.

- [ ] **Step 6: Commit**

```bash
git add release-please-config.json .release-please-manifest.json version.txt CHANGELOG.md .github/workflows/release.yml
git commit -m "ci(release): release with release-please and move the major tag"
git add .github/dependabot.yml
git commit -m "build(ci): keep pinned actions up to date with Dependabot"
```

### Task 10: Documentation, example consumer and contributor rules

**Files:**
- Create: `README.md`, `docs/contract.md`, `docs/workflows.md`, `docs/releasing.md`, `CLAUDE.md`
- Create: `examples/consumer/Makefile`, `examples/consumer/Dockerfile`, `examples/consumer/.dockerignore`, `examples/consumer/.github/workflows/ci.yml`

Before writing, check every documented message against the scripts and workflows written in Tasks 3 to 8 (`grep -rn "::error::" scripts .github`). The documentation must quote them exactly.

- [ ] **Step 1: Write `docs/contract.md`**

```markdown
# Makefile contract

The library never knows a repository's stack. Its workflows only run standard Makefile rules;
each repository decides what those rules do.

## Rules

| Rule | Workflow | What it must do |
|------|----------|-----------------|
| `lint` | `lint.yml` | Check style and code quality. Exit non-zero on problems. |
| `test` | `test.yml` | Run the tests. |
| `build` | `build.yml` | Compile the project. |
| `docker-build` | `docker.yml` | Build the image and tag it with `$(IMAGE)`. Never push. |
| `install` | none | Install dependencies. Other rules depend on it when they need it. |

A repository that has no use for a rule does not implement it and does not call the matching
workflow. Calling a workflow whose rule is missing fails with:

```
The Makefile has no 'build' rule. Add it, or stop calling the build workflow.
```

## Dependencies between rules

Each workflow runs on a fresh runner and calls exactly one rule. Express what a rule needs as
Make prerequisites, so CI and local runs behave the same:

```make
install:
	npm ci

lint: install
	npm run lint

test: install
	npm test
```

## Docker images

`docker.yml` runs `make docker-build IMAGE=ghcr.io/<owner>/<image>:sha-<short sha>`. The rule
must tag the image with exactly `$(IMAGE)`; keep a default for local builds:

```make
IMAGE ?= my-service:dev

docker-build:
	docker build -t $(IMAGE) .
```

If the image is missing after the rule, the job fails with:

```
make docker-build did not produce 'ghcr.io/...'. The docker-build rule must tag its image with $(IMAGE).
```

Makefiles never log in to a registry, push, or handle tokens: the workflow does. Images are
built for `linux/amd64` only.

## Tools: Nix or the runner

- **With a `flake.nix`** in the working directory, rules run as
  `nix develop --command make <rule>`. The default devShell must provide every tool the rules
  use, **including `gnumake`**. The Nix store is cached between runs, keyed on `flake.nix` and
  `flake.lock`.
- **Without a flake**, rules run with the tools of the GitHub runner image (`ubuntu-latest`:
  make, Docker, Node.js, Python, Go and more). Pin a version with the `node-version`,
  `python-version` or `go-version` inputs. Anything else is installed by `make install`.

## Secrets and environment variables

Pass `KEY=VALUE` lines in the `make-env` secret; they are exported before `make` runs and every
value is masked in the logs. Blank lines and lines starting with `#` are ignored.

## Runners

The workflows load their internal actions with GitHub's self-repository syntax (`uses: $/...`),
which needs runner 2.336.0 or newer. GitHub-hosted runners qualify; keep self-hosted runners
(`runs-on` input) up to date.
```

- [ ] **Step 2: Write `docs/workflows.md`**

```markdown
# Workflows reference

Every workflow runs one Makefile rule (see [contract.md](contract.md)) in a single job:

| Workflow | Rule | Job permissions |
|----------|------|-----------------|
| `lint.yml` | `make lint` | `contents: read` |
| `test.yml` | `make test` | `contents: read` |
| `build.yml` | `make build` | `contents: read` |
| `docker.yml` | `make docker-build`, then tag and push to GHCR | `contents: read`, `packages: write` |

A reusable workflow cannot get more permissions than its caller: grant at least the permissions
above on the calling job.

```yaml
jobs:
  test:
    uses: Metrify-App/metrify-workflows/.github/workflows/test.yml@v1
    permissions:
      contents: read
```

## Common inputs

All four workflows accept:

| Input | Default | Description |
|-------|---------|-------------|
| `working-directory` | `.` | Directory that contains the Makefile (monorepos). |
| `runs-on` | `ubuntu-latest` | Runner label. |
| `timeout-minutes` | `30` | Job timeout. |
| `node-version` | `""` | Without a flake: Node.js version to install. Ignored (with a warning) when a `flake.nix` is present. |
| `python-version` | `""` | Same, for Python. |
| `go-version` | `""` | Same, for Go. |
| `cache-paths` | `""` | Extra paths to cache, one per line (for example `~/.npm`). Requires `cache-key-files`. |
| `cache-key-files` | `""` | One glob, relative to the repository root, hashed into the cache key (for example `**/package-lock.json`). |

| Secret | Required | Description |
|--------|----------|-------------|
| `make-env` | no | `KEY=VALUE` lines exported, masked, before `make` runs. |

## docker.yml

Extra inputs:

| Input | Default | Description |
|-------|---------|-------------|
| `image-name` | repository name | Image is `ghcr.io/<owner>/<image-name>`, lowercased. Call the workflow once per image to build several. |
| `push` | `auto` | `auto`, `always` or `never` (see below). |

Outputs:

| Output | Description |
|--------|-------------|
| `image` | Full image name without tag, for example `ghcr.io/metrify-app/metrify-api`. |
| `tags` | Newline-separated references that were pushed; empty if nothing was pushed. |
| `digest` | Digest of the pushed image; empty if nothing was pushed. |

The image is always built as `<image>:sha-<7-character commit>`, where the commit is the pull
request head on pull requests and `github.sha` otherwise. What is pushed:

| Event | `auto` | `always` | `never` |
|-------|--------|----------|---------|
| pull request | nothing | `sha-<short>` | nothing |
| push to `main` | `sha-<short>`, `latest` | same as `auto` | nothing |
| push to `develop` | `sha-<short>`, `develop` | same as `auto` | nothing |
| push of tag `vX.Y.Z` | `sha-<short>`, `vX.Y.Z` | same as `auto` | nothing |
| push to another branch | nothing | `sha-<short>` | nothing |
| any other event | nothing | `sha-<short>` | nothing |

Login uses the job's `GITHUB_TOKEN`; no secret is needed. Pull requests from forks never get
`packages: write`, so leave `push: auto` for them.

## Common errors

| Message | Cause | Fix |
|---------|-------|-----|
| `The Makefile has no '<rule>' rule` | The workflow is called but the rule does not exist. | Add the rule, or remove the job. |
| `make docker-build did not produce '<image>'` | `docker-build` does not tag with `$(IMAGE)`. | Use `docker build -t $(IMAGE) .`. |
| `Git tag '<tag>' is not a release tag (expected vX.Y.Z)` | A pushed tag triggered the workflow. | Restrict the trigger to `tags: ["v*.*.*"]` or use `push: never`. |
| `unknown push mode` | `push` is not `auto`, `always` or `never`. | Fix the input. |
| `make-env line N is not KEY=VALUE` | A malformed line in the `make-env` secret. | Fix line N (the value is never printed). |
| `cache-paths is set but cache-key-files is empty` | A cache without a key would never be refreshed. | Set `cache-key-files`. |
| `make: command not found` (Nix) | The devShell does not provide make. | Add `gnumake` to the devShell packages. |
| `The workflow is requesting 'packages: write', but is only allowed 'packages: none'` | The calling job does not grant the permission. | Add `permissions: { contents: read, packages: write }` to the job. |
```

- [ ] **Step 3: Write `docs/releasing.md`**

```markdown
# Releasing

## Which ref should consumers use?

- **`@v1`** (recommended): the floating major tag. It receives every fix and backward-compatible
  feature as soon as it is released, and never a breaking change.
- `@v1.2.3` or a commit SHA: frozen; upgrade by hand.
- `@main`: every merged change immediately, including breaking ones. Avoid it outside tests.

## How a release happens

1. Changes land on `main` through pull requests, with Conventional Commit messages
   (`feat:`, `fix:`, `docs:`, `build:`...).
2. `release.yml` runs release-please, which keeps a pull request named `chore(main): release X.Y.Z`
   up to date with `CHANGELOG.md`, `version.txt` and `.release-please-manifest.json`.
   That pull request is opened with `GITHUB_TOKEN`, so CI does not run on it; it only touches
   those three files.
3. Merging it tags `vX.Y.Z`, creates the GitHub Release, and moves the `vX` tag to the same
   commit.

The version bump follows the commits since the last release: `fix:` gives a patch, `feat:` a
minor, and `feat!:` or a `BREAKING CHANGE:` footer a major.

## What is a breaking change?

Anything that can break a consumer that did not change:

- removing or renaming a workflow, input, output or secret;
- changing an input default in a way that changes behaviour;
- changing the Makefile contract (rule names, `$(IMAGE)`);
- changing the image naming or the tag policy.

A breaking change produces `v2`. The previous major is frozen: there is no backport branch.
Announce the migration to the team before merging the release pull request.

## First release

`release-please-config.json` forces the first version to `1.0.0` with `release-as`. After
`v1.0.0` is published, remove `release-as` in a `chore:` commit, otherwise every release
would be `1.0.0` again.
```

- [ ] **Step 4: Write the example consumer**

`examples/consumer/Makefile`:
```make
# Example consumer Makefile for Metrify-App/metrify-workflows (Node.js service).
# Copy it, then replace the commands with your stack's. Contract: docs/contract.md.
IMAGE ?= example-service:dev

.PHONY: install lint test build docker-build

install:
	npm ci

lint: install
	npm run lint

test: install
	npm test

build: install
	npm run build

docker-build:
	docker build -t $(IMAGE) .
```

`examples/consumer/Dockerfile`:
```dockerfile
FROM node:24-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
CMD ["node", "index.js"]
```

`examples/consumer/.dockerignore`:
```
node_modules/
.git/
```

`examples/consumer/.github/workflows/ci.yml`:
```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main, develop]
    tags: ["v*.*.*"]

permissions: {}

jobs:
  lint:
    uses: Metrify-App/metrify-workflows/.github/workflows/lint.yml@v1
    permissions:
      contents: read

  test:
    uses: Metrify-App/metrify-workflows/.github/workflows/test.yml@v1
    permissions:
      contents: read
    secrets:
      make-env: ${{ secrets.TEST_ENV }}

  docker:
    needs: [lint, test]
    uses: Metrify-App/metrify-workflows/.github/workflows/docker.yml@v1
    permissions:
      contents: read
      packages: write
```

- [ ] **Step 5: Write `README.md`**

````markdown
# Metrify workflows

Reusable GitHub Actions workflows for every Metrify repository. A repository imports only the
workflows it needs; a fix made here reaches every repository that uses `@v1`.

The workflows know nothing about your stack: each one runs a standard Makefile rule
(`make lint`, `make test`...). Your Makefile decides what the rule does.

## Quick start

1. Give your repository a `Makefile` with the rules you need
   (see [docs/contract.md](docs/contract.md) and [examples/consumer/](examples/consumer/)):

   ```make
   IMAGE ?= my-service:dev

   install:
   	npm ci
   lint: install
   	npm run lint
   test: install
   	npm test
   docker-build:
   	docker build -t $(IMAGE) .
   ```

2. Add `.github/workflows/ci.yml`:

   ```yaml
   name: CI
   on:
     pull_request:
     push:
       branches: [main, develop]
       tags: ["v*.*.*"]
   permissions: {}
   jobs:
     lint:
       uses: Metrify-App/metrify-workflows/.github/workflows/lint.yml@v1
       permissions:
         contents: read
     test:
       uses: Metrify-App/metrify-workflows/.github/workflows/test.yml@v1
       permissions:
         contents: read
     docker:
       needs: [lint, test]
       uses: Metrify-App/metrify-workflows/.github/workflows/docker.yml@v1
       permissions:
         contents: read
         packages: write
   ```

## Workflows

| Workflow | Runs | Pushes to GHCR |
|----------|------|----------------|
| `lint.yml` | `make lint` | no |
| `test.yml` | `make test` | no |
| `build.yml` | `make build` | no |
| `docker.yml` | `make docker-build IMAGE=...` | `sha-<commit>`, plus `latest` on `main`, `develop` on `develop`, `vX.Y.Z` on release tags |

Inputs, outputs, permissions and errors: [docs/workflows.md](docs/workflows.md).
Repositories with a `flake.nix` run their rules inside `nix develop`; the others use the tools
of the GitHub runner, with optional `node-version`, `python-version` and `go-version` inputs.

## Versions

Use `@v1`: it follows every compatible release. `@main` also receives breaking changes
immediately. See [docs/releasing.md](docs/releasing.md) and [CHANGELOG.md](CHANGELOG.md).

## Contributing

Work in the dev shell (`nix develop`, or direnv), then:

```sh
make lint   # actionlint, zizmor, shellcheck
make test   # unit tests of scripts/
make act ARGS="-j fixture-test"   # one ci.yml job locally, in Docker (act)
```

Pull requests also run the self-tests in `.github/workflows/ci.yml`. Design:
[docs/superpowers/specs/](docs/superpowers/specs/). Rules for contributors: [CLAUDE.md](CLAUDE.md).
````

- [ ] **Step 6: Write `CLAUDE.md`**

```markdown
# CLAUDE.md

Reusable GitHub Actions workflows for Metrify repositories. Each public workflow runs one
Makefile rule of the calling repository; the library never knows consumer stacks.

The design reference is `docs/superpowers/specs/2026-10-09-reusable-workflows-library-design.md`.
Read it before structural changes; update it when a design decision changes.

## Layout

- `.github/workflows/{lint,test,build,docker}.yml`: public interface (`workflow_call`).
- `.github/workflows/{ci,release}.yml`: the library's own CI and releases.
- `.github/actions/`: internal composites, loaded by public workflows with `uses: $/...`, which
  resolves to this repository at the commit of the running workflow. Not a public interface.
- `scripts/`: all non-trivial logic, each script unit-tested in `tests/unit/`.
- `tests/fixtures/`: mini consumer repositories used by `ci.yml`.

## Documentation

| Document | Update when |
|----------|-------------|
| `README.md` | the list of workflows or the quick start changes |
| `docs/contract.md` | the Makefile contract changes |
| `docs/workflows.md` | an input, output, secret, permission, tag rule or error message changes |
| `docs/releasing.md` | the release process or the breaking-change policy changes |
| `examples/consumer/` | the recommended consumer setup changes |

Update docs in the same change as the behaviour they describe.

## Working rules

- **Language: English only** in the repository, whatever the conversation language.
- **Public interface = semver.** Removing or renaming a workflow, input, output or secret,
  changing a default's behaviour, the Makefile contract or the tag policy is breaking: use
  `feat!:` and see `docs/releasing.md`.
- **Logic goes in `scripts/`**, with a unit test, not inline in YAML.
- **Pin third-party actions by full commit SHA** with a `# vX.Y.Z` comment. Metrify's own
  workflows are the only exception (`.github/zizmor.yml`).
- **Least privilege:** `permissions: {}` at workflow level, minimal permissions per job,
  `persist-credentials: false` on checkouts, untrusted values passed through `env:`, never
  interpolated in `run:`.
- **Micro commits:** one self-contained step per commit; `make lint` and `make test` pass at
  every commit.

## Git workflow

- Never commit directly on `main`: one branch per change, merged by pull request once CI passes.
- Commit messages: Conventional Commits, `type(scope): imperative summary`, with type among
  `feat`, `fix`, `docs`, `test`, `build`, `refactor`, `chore`, `ci`, and scope among `lint`, `test`,
  `build`, `docker`, `setup-env`, `run-make`, `scripts`, `ci`, `release`, `docs`, `spec`, `plan`.
  release-please builds the changelog from them.
- Never push, force-push, rewrite published history or move tags by hand without being asked.

## Testing changes

- Locally: `nix develop --command make lint test`, then `make act ARGS="-j <job>"` to run a
  `ci.yml` job in Docker with act (see `tests/act/run.sh` for its limits).
- In CI: open a pull request; `ci.yml` calls the workflows from the branch (`$/.github/...`).
- Before merging a change to a public workflow, also try it from a consumer repository by
  referencing the branch: `uses: Metrify-App/metrify-workflows/.github/workflows/test.yml@<branch>`.
```

- [ ] **Step 7: Lint, including the example (zizmor accepts its `@v1` refs thanks to `.github/zizmor.yml`)**

Run: `nix develop --command make lint && nix develop --command make test`
Expected: zizmor audits `examples/consumer/.github/workflows/ci.yml` and reports `No findings to report.`, and both commands exit with 0.

- [ ] **Step 8: Commit in micro commits**

```bash
git add docs/contract.md docs/workflows.md docs/releasing.md
git commit -m "docs(docs): document the Makefile contract, workflows and releases"
git add examples
git commit -m "docs(docs): add an example consumer repository"
git add README.md CLAUDE.md
git commit -m "docs(docs): add README and contributor rules"
```

### Task 11: End-to-end validation and first release

- [ ] **Step 1: Push and watch the full CI**

Run: `git push && gh run watch --exit-status "$(gh run list --branch reusable-workflows --workflow ci --limit 1 --json databaseId --jq '.[0].databaseId')"`
Expected: every job is green.

- [ ] **Step 2: Request a whole-branch code review** (superpowers:requesting-code-review) and address its findings before going further.

- [ ] **Step 3: Cross-repository check (Review Focus 3). Ask the user first.** Propose a throwaway branch `try-metrify-workflows` in `Metrify-App/test-app` (the existing test application). On that branch, add the example `.github/workflows/ci.yml` with `@reusable-workflows` instead of `@v1`, keep only the jobs whose rules that repository's Makefile implements (add a minimal Makefile if it has none), and push. Then run `gh run watch --repo Metrify-App/test-app --exit-status <run id>`.
Expected: the jobs succeed; the "Check out metrify-workflows" step shows a checkout of `Metrify-App/metrify-workflows` at the branch commit; on a non-PR push, `docker` pushes nothing (`auto` on another branch). Delete the throwaway branch afterwards, with the user's agreement.

- [ ] **Step 4: Mark the PR ready and ask the user to review and merge it.** Run `gh pr ready`, then wait for the user to merge the PR. Never merge it yourself without an explicit "yes".

- [ ] **Step 5: First release. Ask the user before merging the release PR.** After the merge, `release.yml` opens `chore(main): release 1.0.0`. Check it with `gh pr list --search "release 1.0.0"`, then show it to the user. Once the user merges it, run `gh run watch --exit-status` on the `release` run.
Expected: tag `v1.0.0` and a GitHub Release exist (`gh release view v1.0.0`), and job `move major tag` succeeded.

- [ ] **Step 6: Check the floating tag (Review Focus 5)**

Run: `gh api repos/Metrify-App/metrify-workflows/git/ref/tags/v1 --jq .object.sha` and `gh api repos/Metrify-App/metrify-workflows/git/ref/tags/v1.0.0 --jq .object.sha`
Expected: both print the same SHA. If `v1.0.0` is an annotated tag (`.object.type == "tag"`), compare against `gh api repos/Metrify-App/metrify-workflows/commits/v1.0.0 --jq .sha` instead.

- [ ] **Step 7: Remove the one-off `release-as`.** On a new branch `chore-release-as`, delete the `"release-as": "1.0.0"` entry (leaving `"packages": { ".": {} }`). Run `make lint`, then commit `chore(release): stop forcing the release version` and open a PR (after asking the user).
