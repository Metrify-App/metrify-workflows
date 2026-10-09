# Standard Make Verbs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (the user chose native execution for this repository) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align metrify-workflows on the Metrify make verbs of `metrify-template`. Each workflow runs `make install` and then its verb. A new `check.yml` checks that every standard verb exists, then runs `make check`. The template documents the optional `build` and `docker-build` verbs and moves its CI to these workflows.

**Architecture:** One new unit-tested script reads make's rule database (`scripts/check-verbs.sh`), exposed through a thin composite (`check-verbs`). The `run-make` composite gains a `make install` step, so every workflow inherits it. Three new single-verb workflows (`check`, `format-check`, `typecheck`) are generated from `lint.yml`. Fixtures, the library's own Makefile, the example and the docs follow the standard. `metrify-template` receives a separate branch, released as standard version 2.

**Tech Stack:** GitHub Actions (reusable workflows, composites, `uses: $/...`), bash 5, GNU make, Nix, act.

**Spec:** `docs/superpowers/specs/2026-10-09-reusable-workflows-library-design.md` (§2, §3, §4, §7, §9, §10).

## Global Constraints

- Branch `reusable-workflows` (PR #1, not merged yet: v1.0.0 has not been released, so nothing here is a breaking change). The template work goes on a new branch `standard-make-verbs` in `../metrify-template`.
- Commits follow Conventional Commits and carry **no attribution trailer**. In metrify-template, the husky `commit-msg` hook also requires a lowercase kebab-case scope and a subject of at most 72 characters.
- `nix develop --command make check` must pass at every metrify-workflows commit (it replaces `make lint test`).
- Standard verbs, in this order everywhere: `help install dev format format-check lint typecheck test fix check`. Optional verbs: `build`, `docker-build`.
- Third-party actions stay pinned by SHA; internal references use `$/`.
- Outward actions (pushes, PRs, a run in test-app) were approved by the user ("branche + PR" for the template; the PR #1 branch already accepts pushes).

## Interfaces

- `scripts/check-verbs.sh`: no arguments. It runs in the Makefile's directory and reads `USE_NIX` (`true` makes it run `nix develop --command make ...`, then unset the variable). It prints nothing and exits 0 when every standard verb exists. Otherwise it prints `::error::The Makefile lacks the standard verbs: <missing, space-separated>. Every Metrify repo has <all verbs> (see docs/contract.md in Metrify-App/metrify-workflows).` on stderr and exits 1.
- `.github/actions/check-verbs`: inputs `working-directory` (`.`) and `use-nix` (`"false"`).
- `.github/actions/run-make`: unchanged inputs. A new step runs `run-make.sh install` before the rule.

## Review Focus

1. **A consumer Makefile whose `install` is slow or networked:** it now runs in every job, including `docker.yml`. This is expected and documented in `docs/contract.md`, "make install first".
2. **Verbs defined through variables or pattern rules** (`$(VERBS):`) must count. `make -pRrq` expands them, and `test-check-verbs.sh` covers the `$(VERBS)` case.
3. **A Makefile that includes other files or needs Nix to parse:** `check-verbs.sh` honours `USE_NIX` like `run-make.sh`. Dogfooding (`library / check`) covers the Nix path.
4. **Template CI before v1.0.0:** `check.yml@v1` does not exist yet, so the template PR stays a draft until the release (Task 6).
5. **Every other repo's standard check** fails after the template's version 2 is merged, until it runs `/metrify-sync`. This is the template's normal process; mention it in the PR.

---

### Task 1: `scripts/check-verbs.sh`

**Files:** Create `tests/unit/test-check-verbs.sh` and `scripts/check-verbs.sh`.

- [ ] **Step 1: Write the failing test**

`tests/unit/test-check-verbs.sh`:
~~~~bash
#!/usr/bin/env bash
# Unit tests for scripts/check-verbs.sh.
# shellcheck source=tests/unit/lib.sh
source "$(dirname "$0")/lib.sh"
script="$(cd "$(dirname "$0")/../../scripts" && pwd)/check-verbs.sh"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cd "$workdir" || exit 1
# Isolate from a calling make and from CI's USE_NIX (see test-run-make.sh).
unset MAKEFLAGS MFLAGS MAKELEVEL USE_NIX

cat >Makefile <<'MAKEFILE'
VERBS := lint test
.PHONY: help install
help:
	@echo help
install dev format:
	@echo never-run >ran
format-check: ; @echo never-run >ran
$(VERBS) typecheck:
	@echo never-run >ran
fix: format
check: format-check lint typecheck test
MAKEFILE

run "$script"
assert_status 0 "accepts a Makefile with every standard verb"
assert_output "" "prints nothing when every verb is there"
if [[ -e ran ]]; then fail "runs no recipe"; else pass "runs no recipe"; fi

cat >Makefile <<'MAKEFILE'
VERBS := lint test
typecheck := not-a-target
help install dev format format-check $(VERBS):
	@echo never-run >ran
check: format-check lint test
MAKEFILE
run "$script"
assert_status 1 "fails when verbs are missing"
assert_contains "::error::The Makefile lacks the standard verbs: typecheck fix" "names every missing verb, variables do not count"
assert_contains "docs/contract.md" "points to the contract"

rm Makefile
run "$script"
assert_status 1 "fails without a Makefile"
assert_contains "lacks the standard verbs: help install" "reports every verb without a Makefile"

finish
~~~~

- [ ] **Step 2: Run it.** Run `nix develop --command make test`. Expected: FAIL lines under `# test-check-verbs.sh` (status 127, script missing).

- [ ] **Step 3: Write the script** (then `chmod +x`)

`scripts/check-verbs.sh`:
~~~~bash
#!/usr/bin/env bash
# Fails with a contract error annotation when the Makefile lacks a standard Metrify verb.
# Usage: USE_NIX=true|false check-verbs.sh   (run in the directory of the Makefile)
#   Reads make's rule database (`make -pRrq`), so no recipe runs.
set -euo pipefail

verbs=(help install dev format format-check lint typecheck test fix check)

use_nix=${USE_NIX:-false}
unset USE_NIX
runner=()
[[ $use_nix != true ]] || runner=(nix develop --command)

# A target that cannot exist, so -q only prints the database and fails harmlessly.
targets=$("${runner[@]}" make -pRrq .metrify-no-such-target 2>/dev/null | awk '
  /^# Not a target:/ { skip = 1; next }
  /^[A-Za-z0-9_.-]+:/ { name = $0; sub(/:.*/, "", name); if (!skip) print name }
  { skip = 0 }' || true)

missing=()
for verb in "${verbs[@]}"; do
  grep -qxF "$verb" <<<"$targets" || missing+=("$verb")
done

if ((${#missing[@]} > 0)); then
  echo "::error::The Makefile lacks the standard verbs: ${missing[*]}. Every Metrify repo has ${verbs[*]} (see docs/contract.md in Metrify-App/metrify-workflows)." >&2
  exit 1
fi
~~~~

- [ ] **Step 4: Run the tests and lint.** Run `nix develop --command make test && nix develop --command make lint`. Expected: 8 `ok` lines under `# test-check-verbs.sh`, no `FAIL`, and both commands exit with 0.

- [ ] **Step 5: Commit** `feat(scripts): list the standard make verbs a Makefile lacks`.

### Task 2: Run `make install` before every verb

**Files:** Modify `.github/actions/run-make/action.yml`, `tests/fixtures/plain/Makefile`, `tests/fixtures/bad-image/Makefile`, `Makefile` and `.gitignore`.

The plain fixture's verbs depend on a `.installed` marker that only `make install` creates, so CI fails if a workflow skips `install`. The library's own Makefile gains every standard verb, because it is called through `check.yml` in Task 3.

- [ ] **Step 1: Make the fixture's verbs require `make install`** (the RED for CI). Use the diff below for `tests/fixtures/plain/Makefile`, `tests/fixtures/bad-image/Makefile` and `.gitignore`. Check locally: `cd tests/fixtures/plain && make typecheck` fails with `make install did not run first`, and `make install typecheck` passes. Then `rm .installed`.

~~~~diff
diff --git a/.gitignore b/.gitignore
index bfe116a..4bd6ee4 100644
--- a/.gitignore
+++ b/.gitignore
@@ -1,2 +1,3 @@
 .direnv/
 tests/fixtures/plain/.cache/
+tests/fixtures/plain/.installed
diff --git a/tests/fixtures/bad-image/Makefile b/tests/fixtures/bad-image/Makefile
index 2047eb7..9097cab 100644
--- a/tests/fixtures/bad-image/Makefile
+++ b/tests/fixtures/bad-image/Makefile
@@ -1,5 +1,8 @@
 # Fixture consumer whose docker-build ignores $(IMAGE): ci.yml checks the contract error.
-.PHONY: docker-build
+.PHONY: install docker-build
+
+install:
+	@echo "install: nothing to do"
 
 docker-build:
 	docker build -t metrify-workflows-bad-image:dev .
diff --git a/tests/fixtures/plain/Makefile b/tests/fixtures/plain/Makefile
index 87569f2..9ab2b5f 100644
--- a/tests/fixtures/plain/Makefile
+++ b/tests/fixtures/plain/Makefile
@@ -1,21 +1,41 @@
 # Fixture consumer for the library self-tests (.github/workflows/ci.yml). Not a template:
-# the rules check what the self-tests configure (tool versions, make-env, cache paths).
+# the verbs check what the self-tests configure (tool versions, make-env, cache paths, install).
 IMAGE ?= metrify-workflows-fixture:dev
 
-.PHONY: lint test build docker-build
+.PHONY: help install dev format format-check lint typecheck test fix check build docker-build
 
-lint:
+help:
+	@echo "Fixture for metrify-workflows self-tests"
+
+# The other verbs fail without this marker, which proves every workflow runs install first.
+install:
+	touch .installed
+
+dev format:
+	@echo "$@: nothing to do"
+
+format-check typecheck: .installed
+	@echo "$@: nothing to do"
+
+lint: .installed
 	node --version | grep '^v24\.'
 
-test:
+test: .installed
 	@test -n "$$FIXTURE_TOKEN" || { echo "FIXTURE_TOKEN is not set: make-env was not exported"; exit 1; }
 	@echo "FIXTURE_TOKEN=$$FIXTURE_TOKEN (must show *** in the CI log)"
 	mkdir -p .cache
 	date >.cache/last-run
 
-build:
+fix: format
+
+check: format-check lint typecheck test
+
+build: .installed
 	python3 --version | grep '^Python 3\.14'
 	go version | grep ' go1\.26'
 
-docker-build:
+docker-build: .installed
 	docker build -t $(IMAGE) .
+
+.installed:
+	@echo "make install did not run first"; exit 1
~~~~

- [ ] **Step 2: Add the `make install` step to `run-make`**

~~~~diff
diff --git a/.github/actions/run-make/action.yml b/.github/actions/run-make/action.yml
index 2df131c..f736ba3 100644
--- a/.github/actions/run-make/action.yml
+++ b/.github/actions/run-make/action.yml
@@ -1,7 +1,7 @@
 name: run-make
 description: >-
-  Internal to metrify-workflows, not a public interface. Exports make-env, checks that the
-  Makefile has the rule, then runs it (inside `nix develop` when use-nix is 'true').
+  Internal to metrify-workflows, not a public interface. Exports make-env, runs `make install`,
+  then the rule (inside `nix develop` when use-nix is 'true').
 
 inputs:
   rule:
@@ -30,6 +30,14 @@ runs:
         MAKE_ENV: ${{ inputs.make-env }}
       run: printf '%s\n' "$MAKE_ENV" | "$GITHUB_ACTION_PATH/../../../scripts/export-make-env.sh"
 
+    # Every Metrify repo has `install` (see docs/contract.md); the verb runs on a fresh runner.
+    - name: make install
+      shell: bash
+      working-directory: ${{ inputs.working-directory }}
+      env:
+        USE_NIX: ${{ inputs.use-nix }}
+      run: '"$GITHUB_ACTION_PATH/../../../scripts/run-make.sh" install'
+
     - name: make ${{ inputs.rule }}
       shell: bash
       working-directory: ${{ inputs.working-directory }}
~~~~

- [ ] **Step 3: Give the library's Makefile every standard verb**

`Makefile`:
~~~~make
# The library follows the Metrify make verbs it enforces (docs/contract.md). Run inside the dev
# shell: `nix develop --command make <verb>` (direnv users: `use flake`). CI runs `make check`
# through the library's own check.yml.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

.PHONY: help install dev format format-check lint typecheck test fix check act

help: ## Show this help
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies (the Nix dev shell provides every tool)
	@echo "install: nothing to do"

dev: ## Run the project locally (a library: see `make act`)
	@echo "dev: nothing to do"

format: ## Format the code
	@echo "format: nothing to do"

format-check: ## Check formatting
	@echo "format-check: nothing to do"

lint: ## Static analysis of workflows, actions and scripts
	actionlint
	zizmor --offline --config .github/zizmor.yml $(wildcard .github examples tests)
	shellcheck -x $(wildcard scripts/*.sh tests/unit/*.sh tests/act/*.sh)

typecheck: ## Type check
	@echo "typecheck: nothing to do"

test: ## Unit tests of the scripts
	tests/unit/run.sh

fix: format ## Format and apply autofixable lint
	@echo "fix: no autofix lint configured"

check: format-check lint typecheck test ## Everything the CI runs

act: ## Run ci.yml locally with act; pass act options in ARGS, e.g. ARGS="-j fixture-test"
	tests/act/run.sh $(ARGS)
~~~~

- [ ] **Step 4: Verify.** Run `nix develop --command make check && nix develop --command scripts/check-verbs.sh`. Expected: both exit with 0.

- [ ] **Step 5: Commit** in two micro commits:
  - `feat(run-make): run make install before every verb` (run-make, fixtures, .gitignore);
  - `build(ci): give the library every standard make verb` (Makefile).

### Task 3: `check.yml`, `format-check.yml` and `typecheck.yml`, with self-tests

**Files:** Create `.github/actions/check-verbs/action.yml`, the three workflows and `tests/fixtures/missing-verbs/Makefile`. Modify the headers of the existing workflows, `ci.yml` and `tests/act/run.sh`.

- [ ] **Step 1: Composite**

`.github/actions/check-verbs/action.yml`:
~~~~yaml
name: check-verbs
description: >-
  Internal to metrify-workflows, not a public interface. Fails when the Makefile lacks a
  standard Metrify verb, without running any recipe.

inputs:
  working-directory:
    description: Directory that contains the Makefile.
    default: .
  use-nix:
    description: "'true' to read the Makefile inside `nix develop`."
    default: "false"

runs:
  using: composite
  steps:
    - name: Check the standard make verbs
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        USE_NIX: ${{ inputs.use-nix }}
      run: '"$GITHUB_ACTION_PATH/../../../scripts/check-verbs.sh"'
~~~~

- [ ] **Step 2: Workflows.** `format-check.yml` and `typecheck.yml` are `lint.yml` with the verb replaced. `check.yml` also adds the `check-verbs` step before `Run make check`. Full files:

`.github/workflows/check.yml`:
~~~~yaml
name: check

# Public workflow: checks that the Makefile has every standard Metrify verb, then runs
# `make install` and `make check` (format-check, lint, typecheck, test) in the calling
# repository. The default CI workflow of a Metrify repo.
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
  check:
    name: make check
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
          cache-scope: check
          node-version: ${{ inputs.node-version }}
          python-version: ${{ inputs.python-version }}
          go-version: ${{ inputs.go-version }}
          cache-paths: ${{ inputs.cache-paths }}
          cache-key-files: ${{ inputs.cache-key-files }}

      - name: Check the standard make verbs
        uses: $/.github/actions/check-verbs
        with:
          working-directory: ${{ inputs.working-directory }}
          use-nix: ${{ steps.env.outputs.use-nix }}

      - name: Run make check
        uses: $/.github/actions/run-make
        with:
          rule: check
          working-directory: ${{ inputs.working-directory }}
          use-nix: ${{ steps.env.outputs.use-nix }}
          make-env: ${{ secrets.make-env }}
~~~~

`.github/workflows/format-check.yml`:
~~~~yaml
name: format-check

# Public workflow: runs `make install`, then `make format-check` (formatting check),
# in the calling repository.
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
  format-check:
    name: make format-check
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
          cache-scope: format-check
          node-version: ${{ inputs.node-version }}
          python-version: ${{ inputs.python-version }}
          go-version: ${{ inputs.go-version }}
          cache-paths: ${{ inputs.cache-paths }}
          cache-key-files: ${{ inputs.cache-key-files }}

      - name: Run make format-check
        uses: $/.github/actions/run-make
        with:
          rule: format-check
          working-directory: ${{ inputs.working-directory }}
          use-nix: ${{ steps.env.outputs.use-nix }}
          make-env: ${{ secrets.make-env }}
~~~~

`.github/workflows/typecheck.yml`:
~~~~yaml
name: typecheck

# Public workflow: runs `make install`, then `make typecheck` (type checking),
# in the calling repository.
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
  typecheck:
    name: make typecheck
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
          cache-scope: typecheck
          node-version: ${{ inputs.node-version }}
          python-version: ${{ inputs.python-version }}
          go-version: ${{ inputs.go-version }}
          cache-paths: ${{ inputs.cache-paths }}
          cache-key-files: ${{ inputs.cache-key-files }}

      - name: Run make typecheck
        uses: $/.github/actions/run-make
        with:
          rule: typecheck
          working-directory: ${{ inputs.working-directory }}
          use-nix: ${{ steps.env.outputs.use-nix }}
          make-env: ${{ secrets.make-env }}
~~~~

Header comments of the existing public workflows now say that `make install` runs first:

~~~~diff
diff --git a/.github/workflows/build.yml b/.github/workflows/build.yml
index 2498703..d9b7da6 100644
--- a/.github/workflows/build.yml
+++ b/.github/workflows/build.yml
@@ -1,6 +1,7 @@
 name: build
 
-# Public workflow: runs `make build` (compilation) in the calling repository.
+# Public workflow: runs `make install`, then `make build` (compilation),
+# in the calling repository.
 # Reference: docs/workflows.md. Makefile contract: docs/contract.md.
 
 on:
diff --git a/.github/workflows/docker.yml b/.github/workflows/docker.yml
index ffa80e8..090de42 100644
--- a/.github/workflows/docker.yml
+++ b/.github/workflows/docker.yml
@@ -1,7 +1,7 @@
 name: docker
 
-# Public workflow: runs `make docker-build IMAGE=<name>`, then tags and pushes the image to
-# GHCR according to the event and the push mode.
+# Public workflow: runs `make install` and `make docker-build IMAGE=<name>`, then tags and
+# pushes the image to GHCR according to the event and the push mode.
 # Reference: docs/workflows.md. Makefile contract: docs/contract.md.
 # The calling job must grant `contents: read` and `packages: write`.
 
diff --git a/.github/workflows/lint.yml b/.github/workflows/lint.yml
index 045621b..44645ab 100644
--- a/.github/workflows/lint.yml
+++ b/.github/workflows/lint.yml
@@ -1,6 +1,7 @@
 name: lint
 
-# Public workflow: runs `make lint` (style and code quality) in the calling repository.
+# Public workflow: runs `make install`, then `make lint` (style and code quality),
+# in the calling repository.
 # Reference: docs/workflows.md. Makefile contract: docs/contract.md.
 
 on:
diff --git a/.github/workflows/test.yml b/.github/workflows/test.yml
index 748622d..1483ba3 100644
--- a/.github/workflows/test.yml
+++ b/.github/workflows/test.yml
@@ -1,6 +1,7 @@
 name: test
 
-# Public workflow: runs `make test` (the tests) in the calling repository.
+# Public workflow: runs `make install`, then `make test` (the tests),
+# in the calling repository.
 # Reference: docs/workflows.md. Makefile contract: docs/contract.md.
 
 on:
~~~~

- [ ] **Step 3: Negative fixture and self-tests**

`tests/fixtures/missing-verbs/Makefile`:
~~~~make
# Fixture consumer that lacks most standard verbs: ci.yml checks the contract error.
.PHONY: install lint test

install lint test:
	@echo "$@: nothing to do"
~~~~

~~~~diff
diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
index 86e7371..0a0303d 100644
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -1,7 +1,7 @@
 name: ci
 
-# CI of the library itself: dogfooding (lint and test of this repository through its own
-# workflows), self-tests on fixtures, and contract error cases.
+# CI of the library itself: dogfooding (`make check` of this repository through its own
+# check.yml), self-tests on fixtures, and contract error cases.
 
 on:
   pull_request:
@@ -19,17 +19,38 @@ concurrency:
   cancel-in-progress: true
 
 jobs:
-  lint:
-    name: library / lint
-    uses: $/.github/workflows/lint.yml
+  check:
+    name: library / check
+    uses: $/.github/workflows/check.yml
     permissions:
       contents: read
 
-  test:
-    name: library / test
-    uses: $/.github/workflows/test.yml
+  fixture-check:
+    name: fixture / check
+    uses: $/.github/workflows/check.yml
+    permissions:
+      contents: read
+    with:
+      working-directory: tests/fixtures/plain
+      node-version: "24"
+    secrets:
+      make-env: ${{ format('FIXTURE_TOKEN=run-{0}', github.run_id) }}
+
+  fixture-format-check:
+    name: fixture / format-check
+    uses: $/.github/workflows/format-check.yml
     permissions:
       contents: read
+    with:
+      working-directory: tests/fixtures/plain
+
+  fixture-typecheck:
+    name: fixture / typecheck
+    uses: $/.github/workflows/typecheck.yml
+    permissions:
+      contents: read
+    with:
+      working-directory: tests/fixtures/plain
 
   fixture-lint:
     name: fixture / lint
@@ -109,6 +130,13 @@ jobs:
           rule: missing
           working-directory: tests/fixtures/plain
 
+      - name: Missing standard verbs
+        id: missing-verbs
+        continue-on-error: true
+        uses: $/.github/actions/check-verbs
+        with:
+          working-directory: tests/fixtures/missing-verbs
+
       - name: Malformed make-env
         id: bad-env
         continue-on-error: true
@@ -144,12 +172,13 @@ jobs:
       - name: Every case must have failed
         env:
           MISSING_RULE: ${{ steps.missing-rule.outcome }}
+          MISSING_VERBS: ${{ steps.missing-verbs.outcome }}
           BAD_ENV: ${{ steps.bad-env.outcome }}
           BAD_CACHE: ${{ steps.bad-cache.outcome }}
           BAD_IMAGE: ${{ steps.bad-image.outcome }}
         run: |
           status=0
-          for case in MISSING_RULE BAD_ENV BAD_CACHE BAD_IMAGE; do
+          for case in MISSING_RULE MISSING_VERBS BAD_ENV BAD_CACHE BAD_IMAGE; do
             if [[ ${!case} == failure ]]; then
               echo "ok   $case failed as expected"
             else
diff --git a/tests/act/run.sh b/tests/act/run.sh
index 0705055..f86b7ba 100755
--- a/tests/act/run.sh
+++ b/tests/act/run.sh
@@ -4,7 +4,7 @@
 #   act 0.2.x does not support the self-repository syntax (`uses: $/...`, nektos/act#6189).
 #   In this repository `$/` and `./` resolve to the same code, so the copy rewrites one into
 #   the other. Jobs that install Nix (library / lint, library / test) need a systemd host and
-#   are better checked with `make lint test` directly.
+#   are better checked with `make check` directly.
 set -euo pipefail
 
 root=$(git rev-parse --show-toplevel)
~~~~

- [ ] **Step 4: Verify locally.** Run `nix develop --command make check`, then `nix develop --command make act ARGS="-j fixture-check"`. Expected: `make check` exits with 0, and act ends on `🏁  Job succeeded` with `touch .installed`, `format-check: nothing to do` and `FIXTURE_TOKEN=***` in the log.

- [ ] **Step 5: Commit** in micro commits:
  - `feat(check): add check, format-check and typecheck workflows` (composite + 3 workflows + headers);
  - `test(ci): self-test the standard verbs workflows` (fixture, ci.yml, act comment).

- [ ] **Step 6: Push and watch CI.** Run `git push`, then `gh run watch --exit-status <run>`. Expected: every job is green, including `library / check`, `fixture / check`, `fixture / format-check` and `fixture / typecheck`. `contract errors` prints `ok   MISSING_VERBS failed as expected`.

### Task 4: Docs, example consumer and contributor rules

**Files:** Modify `docs/contract.md`, `docs/workflows.md`, `README.md`, `CLAUDE.md`, `examples/consumer/Makefile` and `examples/consumer/.github/workflows/ci.yml`. The spec was updated with the design (commit before this plan).

- [ ] **Step 1: Apply**

~~~~diff
diff --git a/CLAUDE.md b/CLAUDE.md
index a92247a..1158e21 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -1,14 +1,16 @@
 # CLAUDE.md
 
-Reusable GitHub Actions workflows for Metrify repositories. Each public workflow runs one
-Makefile rule of the calling repository; the library never knows consumer stacks.
+Reusable GitHub Actions workflows for Metrify repositories. Each public workflow runs `make install`
+then one make verb of the calling repository; the library never knows consumer stacks. The verbs
+are those of the Metrify standard (`metrify-template`, `STANDARD.md`): change them there first.
 
 The design reference is `docs/superpowers/specs/2026-10-09-reusable-workflows-library-design.md`.
 Read it before structural changes; update it when a design decision changes.
 
 ## Layout
 
-- `.github/workflows/{lint,test,build,docker}.yml`: public interface (`workflow_call`).
+- `.github/workflows/{check,format-check,lint,typecheck,test,build,docker}.yml`: public interface
+  (`workflow_call`).
 - `.github/workflows/{ci,release}.yml`: the library's own CI and releases.
 - `.github/actions/`: internal composites, loaded by public workflows with `uses: $/...`, which
   resolves to this repository at the commit of the running workflow. Not a public interface.
@@ -20,7 +22,7 @@ Read it before structural changes; update it when a design decision changes.
 | Document | Update when |
 |----------|-------------|
 | `README.md` | the list of workflows or the quick start changes |
-| `docs/contract.md` | the Makefile contract changes |
+| `docs/contract.md` | the make verbs or the Makefile contract change (keep in sync with `metrify-template`) |
 | `docs/workflows.md` | an input, output, secret, permission, tag rule or error message changes |
 | `docs/releasing.md` | the release process or the breaking-change policy changes |
 | `examples/consumer/` | the recommended consumer setup changes |
@@ -39,8 +41,8 @@ Update docs in the same change as the behaviour they describe.
 - **Least privilege:** `permissions: {}` at workflow level, minimal permissions per job,
   `persist-credentials: false` on checkouts, untrusted values passed through `env:`, never
   interpolated in `run:`.
-- **Micro commits:** one self-contained step per commit; `make lint` and `make test` pass at
-  every commit.
+- **Micro commits:** one self-contained step per commit; `make check` passes at every
+  commit.
 
 ## Git workflow
 
@@ -53,7 +55,7 @@ Update docs in the same change as the behaviour they describe.
 
 ## Testing changes
 
-- Locally: `nix develop --command make lint test`, then `make act ARGS="-j <job>"` to run a
+- Locally: `nix develop --command make check`, then `make act ARGS="-j <job>"` to run a
   `ci.yml` job in Docker with act (see `tests/act/run.sh` for its limits).
 - In CI: open a pull request; `ci.yml` calls the workflows from the branch (`$/.github/...`).
 - Before merging a change to a public workflow, also try it from a consumer repository by
diff --git a/README.md b/README.md
index 57833d0..a6bf2d2 100644
--- a/README.md
+++ b/README.md
@@ -8,21 +8,11 @@ The workflows know nothing about your stack: each one runs a standard Makefile r
 
 ## Quick start
 
-1. Give your repository a `Makefile` with the rules you need
-   (see [docs/contract.md](docs/contract.md) and [examples/consumer/](examples/consumer/)):
-
-   ```make
-   IMAGE ?= my-service:dev
-
-   install:
-   	npm ci
-   lint: install
-   	npm run lint
-   test: install
-   	npm test
-   docker-build:
-   	docker build -t $(IMAGE) .
-   ```
+1. Give your repository the Metrify make verbs (`help`, `install`, `dev`, `format`,
+   `format-check`, `lint`, `typecheck`, `test`, `fix`, `check`), plus `docker-build` if it ships
+   an image. Repositories created from
+   [metrify-template](https://github.com/Metrify-App/metrify-template) already have them; see
+   [docs/contract.md](docs/contract.md) and [examples/consumer/Makefile](examples/consumer/Makefile).
 
 2. Add `.github/workflows/ci.yml`:
 
@@ -35,16 +25,12 @@ The workflows know nothing about your stack: each one runs a standard Makefile r
        tags: ["v*.*.*"]
    permissions: {}
    jobs:
-     lint:
-       uses: Metrify-App/metrify-workflows/.github/workflows/lint.yml@v1
-       permissions:
-         contents: read
-     test:
-       uses: Metrify-App/metrify-workflows/.github/workflows/test.yml@v1
+     check:
+       uses: Metrify-App/metrify-workflows/.github/workflows/check.yml@v1
        permissions:
          contents: read
      docker:
-       needs: [lint, test]
+       needs: check
        uses: Metrify-App/metrify-workflows/.github/workflows/docker.yml@v1
        permissions:
          contents: read
@@ -53,15 +39,20 @@ The workflows know nothing about your stack: each one runs a standard Makefile r
 
 ## Workflows
 
+Each one runs `make install`, then its verb.
+
 | Workflow | Runs | Pushes to GHCR |
 |----------|------|----------------|
+| `check.yml` | standard verbs check, then `make check` (the default) | no |
+| `format-check.yml` | `make format-check` | no |
 | `lint.yml` | `make lint` | no |
+| `typecheck.yml` | `make typecheck` | no |
 | `test.yml` | `make test` | no |
-| `build.yml` | `make build` | no |
-| `docker.yml` | `make docker-build IMAGE=...` | `sha-<commit>`, plus `latest` on `main`, `develop` on `develop`, `vX.Y.Z` on release tags |
+| `build.yml` | `make build` (optional verb) | no |
+| `docker.yml` | `make docker-build IMAGE=...` (optional verb) | `sha-<commit>`, plus `latest` on `main`, `develop` on `develop`, `vX.Y.Z` on release tags |
 
 Inputs, outputs, permissions and errors: [docs/workflows.md](docs/workflows.md).
-Repositories with a `flake.nix` run their rules inside `nix develop`; the others use the tools
+Repositories with a `flake.nix` run their verbs inside `nix develop`; the others use the tools
 of the GitHub runner, with optional `node-version`, `python-version` and `go-version` inputs.
 
 ## Versions
@@ -74,8 +65,7 @@ immediately. See [docs/releasing.md](docs/releasing.md) and [CHANGELOG.md](CHANG
 Work in the dev shell (`nix develop`, or direnv), then:
 
 ```sh
-make lint   # actionlint, zizmor, shellcheck
-make test   # unit tests of scripts/
+make check  # format-check, lint (actionlint, zizmor, shellcheck), typecheck, test
 make act ARGS="-j fixture-test"   # one ci.yml job locally, in Docker (act)
 ```
 
diff --git a/docs/contract.md b/docs/contract.md
index abceecc..35c6dbd 100644
--- a/docs/contract.md
+++ b/docs/contract.md
@@ -1,40 +1,53 @@
 # Makefile contract
 
-The library never knows a repository's stack. Its workflows only run standard Makefile rules;
-each repository decides what those rules do.
-
-## Rules
-
-| Rule | Workflow | What it must do |
-|------|----------|-----------------|
-| `lint` | `lint.yml` | Check style and code quality. Exit non-zero on problems. |
-| `test` | `test.yml` | Run the tests. |
-| `build` | `build.yml` | Compile the project. |
-| `docker-build` | `docker.yml` | Build the image and tag it with `$(IMAGE)`. Never push. |
-| `install` | none | Install dependencies. Other rules depend on it when they need it. |
-
-A repository that has no use for a rule does not implement it and does not call the matching
-workflow. Calling a workflow whose rule is missing fails with:
+The library never knows a repository's stack. Its workflows only run the make verbs of the
+Metrify repo standard; each repository decides what those verbs do. The standard is defined in
+[metrify-template](https://github.com/Metrify-App/metrify-template/blob/main/.claude/skills/metrify-sync/STANDARD.md)
+("Make verbs"); this page restates what the workflows rely on.
+
+## Standard verbs
+
+Every Metrify repository has these targets. A verb with nothing to do for the stack prints
+`<verb>: nothing to do` and exits 0.
+
+| Verb | Does | Workflow |
+|------|------|----------|
+| `help` | Lists targets (default goal). | none |
+| `install` | Installs dependencies. | run first by every workflow |
+| `dev` | Runs the project locally. | none |
+| `format` / `format-check` | Formats / checks formatting. | `format-check.yml` |
+| `lint` | Lints. | `lint.yml` |
+| `typecheck` | Type checks. | `typecheck.yml` |
+| `test` | Runs the tests. | `test.yml` |
+| `fix` | `format` + autofixable lint. | none |
+| `check` | `format-check lint typecheck test`: everything the CI runs. | `check.yml` |
+
+`check.yml` first reads the Makefile's rule database (no recipe runs) and fails when a verb is
+missing:
 
 ```
-The Makefile has no 'build' rule. Add it, or stop calling the build workflow.
+The Makefile lacks the standard verbs: typecheck fix. Every Metrify repo has help install dev format format-check lint typecheck test fix check.
 ```
 
-## Dependencies between rules
+## Optional verbs
 
-Each workflow runs on a fresh runner and calls exactly one rule. Express what a rule needs as
-Make prerequisites, so CI and local runs behave the same:
+Only for repositories that ship a binary or an image:
 
-```make
-install:
-	npm ci
+| Verb | Does | Workflow |
+|------|------|----------|
+| `build` | Compiles the project. | `build.yml` |
+| `docker-build` | Builds the image tagged `$(IMAGE)`. Never pushes. | `docker.yml` |
 
-lint: install
-	npm run lint
+Calling a workflow whose verb is missing fails with:
 
-test: install
-	npm test
 ```
+The Makefile has no 'build' rule. Add it, or stop calling the build workflow.
+```
+
+## `make install` first
+
+Each workflow runs on a fresh runner: it runs `make install`, then its verb, in the same job.
+No Make prerequisite on `install` is needed (it would run twice).
 
 ## Docker images
 
diff --git a/docs/workflows.md b/docs/workflows.md
index 438a7fa..f2e1cbb 100644
--- a/docs/workflows.md
+++ b/docs/workflows.md
@@ -1,28 +1,33 @@
 # Workflows reference
 
-Every workflow runs one Makefile rule (see [contract.md](contract.md)) in a single job:
+Every workflow runs `make install`, then one make verb (see [contract.md](contract.md)), in a
+single job. Use `check.yml` by default; the single-verb workflows are for repositories that want
+separate, parallel jobs.
 
-| Workflow | Rule | Job permissions |
+| Workflow | Runs | Job permissions |
 |----------|------|-----------------|
+| `check.yml` | standard verbs check, then `make check` | `contents: read` |
+| `format-check.yml` | `make format-check` | `contents: read` |
 | `lint.yml` | `make lint` | `contents: read` |
+| `typecheck.yml` | `make typecheck` | `contents: read` |
 | `test.yml` | `make test` | `contents: read` |
-| `build.yml` | `make build` | `contents: read` |
-| `docker.yml` | `make docker-build`, then tag and push to GHCR | `contents: read`, `packages: write` |
+| `build.yml` | `make build` (optional verb) | `contents: read` |
+| `docker.yml` | `make docker-build` (optional verb), then tag and push to GHCR | `contents: read`, `packages: write` |
 
 A reusable workflow cannot get more permissions than its caller: grant at least the permissions
 above on the calling job.
 
 ```yaml
 jobs:
-  test:
-    uses: Metrify-App/metrify-workflows/.github/workflows/test.yml@v1
+  check:
+    uses: Metrify-App/metrify-workflows/.github/workflows/check.yml@v1
     permissions:
       contents: read
 ```
 
 ## Common inputs
 
-All four workflows accept:
+All workflows accept:
 
 | Input | Default | Description |
 |-------|---------|-------------|
@@ -76,6 +81,7 @@ image (`concurrency`), so an older run never overwrites `latest` or `develop` wi
 
 | Message | Cause | Fix |
 |---------|-------|-----|
+| `The Makefile lacks the standard verbs: <verbs>` | `check.yml` found standard verbs missing. | Add them; a verb with nothing to do prints `<verb>: nothing to do`. |
 | `The Makefile has no '<rule>' rule` | The workflow is called but the rule does not exist. | Add the rule, or remove the job. |
 | `make docker-build did not produce '<image>'` | `docker-build` does not tag with `$(IMAGE)`. | Use `docker build -t $(IMAGE) .`. |
 | `Git tag '<tag>' is not a release tag (expected vX.Y.Z)` | A pushed tag triggered the workflow. | Restrict the trigger to `tags: ["v*.*.*"]` or use `push: never`. |
~~~~

`examples/consumer/Makefile`:
~~~~make
# Example consumer Makefile for Metrify-App/metrify-workflows (Node.js service), following the
# Metrify make verbs (metrify-template STANDARD.md). Replace the commands with your stack's.
IMAGE ?= example-service:dev

.DEFAULT_GOAL := help
.PHONY: help install dev format format-check lint typecheck test fix check docker-build

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ {printf "    %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Install dependencies
	npm ci --no-fund --no-audit

dev: ## Run the project locally
	npm run dev

format: ## Format the code
	npx prettier --write .

format-check: ## Check formatting
	npx prettier --check .

lint: ## Lint
	npx eslint .

typecheck: ## Type check
	npx tsc --noEmit

test: ## Run the tests
	npm test

fix: format ## Format and apply autofixable lint
	npx eslint --fix .

check: format-check lint typecheck test ## Everything the CI runs

# Optional verb: only for a repo that ships an image. Must tag $(IMAGE) and never push.
docker-build: ## Build the Docker image
	docker build -t $(IMAGE) .
~~~~

`examples/consumer/.github/workflows/ci.yml`:
~~~~yaml
name: CI

on:
  pull_request:
  push:
    branches: [main, develop]
    tags: ["v*.*.*"]

permissions: {}

jobs:
  check:
    uses: Metrify-App/metrify-workflows/.github/workflows/check.yml@v1
    permissions:
      contents: read
    with:
      node-version: "24"
      cache-paths: ~/.npm
      cache-key-files: package-lock.json
    secrets:
      make-env: ${{ secrets.TEST_ENV }}

  docker:
    needs: check
    uses: Metrify-App/metrify-workflows/.github/workflows/docker.yml@v1
    permissions:
      contents: read
      packages: write
~~~~

- [ ] **Step 2: Verify.** Run `nix develop --command make check`. Expected: exit 0, with zizmor auditing `examples/consumer/.github/workflows/ci.yml` without findings. Then run `grep -rn "test: install\|lint.yml@v1" README.md docs examples CLAUDE.md`. Expected: no output.

- [ ] **Step 3: Commit** in micro commits:
  - `docs(docs): document the standard make verbs and check.yml`;
  - `docs(docs): align the example consumer on the standard verbs`;
  - `docs(docs): update README and contributor rules for check.yml`.

### Task 5: Final verification of metrify-workflows

- [ ] **Step 1:** Push and watch CI on the final commit. Expected: all jobs are green.
- [ ] **Step 2: Whole-branch review** of the commits of this plan, by a fresh reviewer on the most capable model, with this plan's Review Focus. Then one fix pass for the Critical and Important findings, each fixed RED→GREEN.

### Task 6: metrify-template, standard version 2

**Files** (in `../metrify-template`, branch `standard-make-verbs`): `Makefile`, `.claude/skills/metrify-sync/STANDARD.md`, `.claude/rules/metrify-rules.md`, `.claude/skills/metrify-setup/SKILL.md`, `.github/workflows/ci.yml` and `README.md`. `bump.sh` updates `VERSION` and `OWNED.sha256`.

- [ ] **Step 1: Branch.** Run `git -C ../metrify-template checkout -b standard-make-verbs`.
- [ ] **Step 2: Apply**

~~~~diff
diff --git a/.claude/rules/metrify-rules.md b/.claude/rules/metrify-rules.md
index d9e9406..ea04a42 100644
--- a/.claude/rules/metrify-rules.md
+++ b/.claude/rules/metrify-rules.md
@@ -15,7 +15,8 @@ edit it there, never in a repo (`/metrify-sync` overwrites it).
 
 Always through `make`; `make help` lists every target. Every repo has `install`, `dev`,
 `format`, `format-check`, `lint`, `typecheck`, `test`, `fix`, and `check`, which is
-everything the CI runs.
+everything the CI runs. A repo that ships a binary or an image also has `build` or
+`docker-build`.
 
 ## Conventions
 
diff --git a/.claude/skills/metrify-setup/SKILL.md b/.claude/skills/metrify-setup/SKILL.md
index 0707241..275920c 100644
--- a/.claude/skills/metrify-setup/SKILL.md
+++ b/.claude/skills/metrify-setup/SKILL.md
@@ -53,9 +53,10 @@ One question-tool round, at most 4 questions, each with your best guess as the f
 In this order, replacing every fill marker:
 
 1. `Makefile`: each standard verb runs the confirmed command; `install` keeps
-   `npm install` for the hooks; project targets go under `##@ Project`. Existing targets
-   stay.
-2. `.github/workflows/ci.yml`: the toolchain step(s) for the stack; uncomment the
+   `npm install` for the hooks; `build` and `docker-build` are uncommented when the repo ships a
+   binary or an image; project targets go under `##@ Project`. Existing targets stay.
+2. `.github/workflows/ci.yml`: the stack's toolchain as inputs of the `check` job
+   (`node-version`, `python-version`, `go-version`; none with a `flake.nix`); uncomment the
    `docker` job when the repo has a `Dockerfile`. `.claude/settings.json`: the project targets agents run often.
 3. Hooks: an existing repo's own checks in `pre-commit`/`pre-push` stay, next to
    `make format-check lint` and `make test`.
diff --git a/.claude/skills/metrify-sync/STANDARD.md b/.claude/skills/metrify-sync/STANDARD.md
index c4f534a..bfcd79f 100644
--- a/.claude/skills/metrify-sync/STANDARD.md
+++ b/.claude/skills/metrify-sync/STANDARD.md
@@ -31,7 +31,7 @@ two ways.
 | `docs/GLOSSARY.md` | The repo's own domain words. |
 | `Makefile` | The make verbs below, plus project targets. |
 | `.husky/pre-commit`, `.husky/pre-push` | The hooks below, plus project checks. |
-| `.github/workflows/ci.yml` | `make install check` and the standard check, on push to `main` and on pull requests. The check compares `VERSION` with the public template's `main`. |
+| `.github/workflows/ci.yml` | `make install check` through `metrify-workflows` (`check.yml`) and the standard check, on push to `main` and on pull requests. The check compares `VERSION` with the public template's `main`. |
 | `.claude/settings.json` | Shared permissions: make verbs and read-only git. |
 | `package.json` | husky. |
 | `.gitignore` | Git basics. |
@@ -87,6 +87,17 @@ Every repo has these targets, so the CI, the hooks and agents need one command s
 
 A verb with nothing to do for the stack prints `<verb>: nothing to do` and exits 0.
 
+The CI runs them through `Metrify-App/metrify-workflows`: `check.yml` runs `make install`, checks
+that every verb above exists, then runs `make check`.
+
+**Optional verbs**, only in a repo that ships a binary or an image (the Makefile shows them
+commented out):
+
+| Verb | Does |
+|---|---|
+| `build` | Compiles the project; `build.yml` runs it. |
+| `docker-build` | Builds the image tagged `$(IMAGE)` (local default `IMAGE ?= <repo>:dev`); never pushes. `docker.yml` runs it, then tags and pushes to GHCR. |
+
 ## Hooks
 
 - `commit-msg`: Conventional Commits, lowercase kebab-case scope, subject at most 72 chars.
diff --git a/Makefile b/Makefile
index 69e8764..be5f1c1 100644
--- a/Makefile
+++ b/Makefile
@@ -36,4 +36,14 @@ fix: format ## Format and apply autofixable lint
 
 check: format-check lint typecheck test ## Everything the CI runs
 
+# Optional verbs (STANDARD.md): only in a repo that ships a binary or an image; uncomment them.
+# The CI's build and docker jobs call them. docker-build tags $(IMAGE) and never pushes.
+# IMAGE ?= <repo>:dev
+#
+# build: ## Compile the project
+# 	<build command>
+#
+# docker-build: ## Build the Docker image
+# 	docker build -t $(IMAGE) .
+
 ##@ Project
diff --git a/README.md b/README.md
index 9db475a..a02579b 100644
--- a/README.md
+++ b/README.md
@@ -51,5 +51,6 @@ Hooks are installed by `make install` (husky):
 - `pre-commit`: blocks files over 10 MB, then `make format-check lint`.
 - `pre-push`: on `main`/`develop`, refuses when behind origin; then `make test`.
 
-CI (`.github/workflows/ci.yml`) runs `make install check` and the Metrify standard check on
-every push to `main` and on pull requests.
+CI (`.github/workflows/ci.yml`) runs `make install check` through
+[metrify-workflows](https://github.com/Metrify-App/metrify-workflows) and the Metrify standard
+check on every push to `main` and on pull requests.
~~~~

`.github/workflows/ci.yml`:
~~~~yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions: {}

jobs:
  # make install, then make check, through the shared workflows of Metrify-App/metrify-workflows.
  # /metrify-setup sets the stack's toolchain here (node-version, python-version, go-version), or
  # nothing when the repo has a flake.nix. Node is there for husky (make install).
  check:
    uses: Metrify-App/metrify-workflows/.github/workflows/check.yml@v1
    permissions:
      contents: read
    with:
      node-version: lts/*

  standard:
    name: Metrify standard
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Metrify standard
        run: bash .claude/skills/metrify-quality/scripts/check-standard.sh

  # Docker image to ghcr.io/<org>/<repo>, through the same shared workflows. Uncomment for a repo
  # that ships one; it needs the optional docker-build verb (Makefile). sha-<commit> on every push,
  # latest on main; add tags: ["v*.*.*"] under push for vX.Y.Z release images.
  # docker:
  #   needs: [check, standard]
  #   uses: Metrify-App/metrify-workflows/.github/workflows/docker.yml@v1
  #   permissions:
  #     contents: read
  #     packages: write
~~~~

- [ ] **Step 3: Release the standard.** Run `sh .claude/skills/metrify-sync/scripts/bump.sh`. Expected: `✓ standard 1 -> 2`.
- [ ] **Step 4: Verify.** Run `make help`, which lists the same verbs as before (the optional ones are comments). Then run `bash .claude/skills/metrify-quality/scripts/check-standard.sh`, which ends with `Standard: pass`. Then, from `../metrify-template`, run `USE_NIX=false ../metrify-workflows/scripts/check-verbs.sh`, which exits with 0.
- [ ] **Step 5: Commit** in micro commits, with no attribution and the husky hooks active:
  - `feat(standard): add optional build and docker-build verbs` (STANDARD.md, rules, Makefile, SKILL.md, VERSION, OWNED.sha256);
  - `ci(ci): run make check through metrify-workflows` (ci.yml, README.md).
- [ ] **Step 6: Push and open a draft PR.** The body states that it merges after metrify-workflows v1.0.0, since `check.yml@v1` does not exist before then, and that other repos then run `/metrify-sync`.
