# Metrify reusable workflows library — design

- **Date:** 2026-10-09
- **Status:** approved design, pending implementation plan
- **Repository:** `github.com/Metrify-App/metrify-workflows`

## 1. Goal

Centralise CI/CD for every repository of the Metrify project. Each consumer repository imports
only the workflows it needs from this repository. A fix or an improvement is made here once and
reaches every consumer without editing them (for consumers that track `@v1` or `@main`).

Success criteria:

- A consumer CI is a few lines of YAML that call library workflows.
- The library knows nothing about consumer stacks: it only calls the make verbs of the Metrify
  repo standard (`metrify-template`).
- Docker images are pushed to GHCR with one shared naming convention, and only the library
  handles registries, tokens and tags.
- The library is versioned (`vX.Y.Z` plus a floating major `vX`) and tests itself.

Prerequisites:

- **The repository is public**, so every consumer can call it without access settings or
  tokens. The library contains no secret and no business code.
- The older private repository `Metrify-App/github-workflows` (`docker-build-push.yml`,
  repository mirroring) is replaced by this library over time. Migrating its consumers, its
  mirroring workflows and archiving it are out of scope here.

## 2. Decisions summary

| Topic | Decision |
|---|---|
| Make verbs | The Metrify standard (`metrify-template`, `STANDARD.md`): `help install dev format format-check lint typecheck test fix check` in every repo; `build` and `docker-build` optional |
| Building blocks | One reusable workflow (`workflow_call`) per CI verb (`check`, `format-check`, `lint`, `typecheck`, `test`, `build`, `docker`), built on shared internal composite actions; `check.yml` is the default |
| Conformity | `check.yml` first fails if the Makefile lacks a standard verb (read from make's rule database, nothing runs) |
| Optional rules | A consumer imports `build.yml` or `docker.yml` only if it implements the optional verb |
| `make install` | Not a workflow. Every workflow runs `make install` before its verb, as the template's CI did |
| Tooling | Nix if the consumer has `flake.nix`, otherwise the GitHub runner image plus optional `*-version` inputs |
| Nix cache | GitHub Actions cache (`nix-community/cache-nix-action`), keyed on `flake.lock` |
| Docker handoff | `make docker-build IMAGE=<full name>`; the Makefile must tag its image with `$(IMAGE)` |
| Architectures | `linux/amd64` only |
| Push policy | Event-driven (`push: auto`), overridable with `always` / `never` |
| Release image tags | `vX.Y.Z` only (no floating image tags) |
| Make secrets | One optional multi-line secret `make-env` (`KEY=VALUE` lines) |
| Library releases | release-please, `CHANGELOG.md`, floating major tag `vX` |
| Recommended consumer ref | `@v1` |
| Internal actions | Loaded with GitHub's self-repository syntax (`uses: $/...`), which resolves to this repository at the commit of the running workflow |
| Library tests | actionlint + zizmor + shellcheck, unit tests for every script, self-tests (dogfooding + fixtures) |
| Dependency caches | Only through `cache-paths` / `cache-key-files`; built-in `setup-*` caches are disabled |
| Docs | All in this repository, in English |

## 3. Makefile contract

The make verbs are those of the Metrify repo standard, defined in `Metrify-App/metrify-template`
(`.claude/skills/metrify-sync/STANDARD.md`, "Make verbs"). That file is the source of truth; this
section restates what the library relies on. Each repository decides what its verbs do.

**Standard verbs** (every repository has them; a verb with nothing to do prints
`<verb>: nothing to do` and exits 0):

| Verb | Does | Workflow |
|---|---|---|
| `help` | Lists targets (default goal) | none |
| `install` | Installs dependencies | run first by every workflow |
| `dev` | Runs the project locally | none |
| `format` / `format-check` | Formats / checks formatting | `format-check.yml` |
| `lint` | Lints | `lint.yml` |
| `typecheck` | Type checks | `typecheck.yml` |
| `test` | Runs the tests | `test.yml` |
| `fix` | `format` + autofixable lint | none |
| `check` | `format-check lint typecheck test`: what the CI runs | `check.yml` |

**Optional verbs** (only in repositories that ship a binary or an image):

| Verb | Does | Workflow |
|---|---|---|
| `build` | Compiles the project | `build.yml` |
| `docker-build` | Builds the image tagged `$(IMAGE)`; never pushes | `docker.yml` |

Rules:

- Every workflow runs `make install`, then its verb, in the same job.
- `check.yml` first checks that the Makefile has every standard verb. It reads make's rule
  database (`make -pRrq`), so no recipe runs, and fails with one annotation that names every
  missing verb.
- `docker-build` must honour the `IMAGE` variable and keep a local default:

  ```make
  IMAGE ?= my-service:dev

  docker-build:
  	docker build -t $(IMAGE) .
  ```

- Makefiles never log in to a registry, push, or handle tokens.
- A repository with a `flake.nix` runs `nix develop --command make <verb>` in CI, so its
  devShell must provide `gnumake`.
- The workflows need runner 2.336.0 or newer (self-repository syntax, section 4.2).
  GitHub-hosted runners qualify.

## 4. Architecture

### 4.1 Repository layout

```
.github/
  workflows/
    check.yml           # public: checks the standard verbs, runs `make check` (the default)
    format-check.yml    # public: runs `make format-check`
    lint.yml            # public: runs `make lint`
    typecheck.yml       # public: runs `make typecheck`
    test.yml            # public: runs `make test`
    build.yml           # public: runs `make build` (optional verb)
    docker.yml          # public: runs `make docker-build`, tags and pushes to GHCR
    ci.yml              # internal: static analysis, unit tests, self-tests
    release.yml         # internal: release-please and floating major tag
  actions/
    setup-env/action.yml  # internal: Nix or fallback toolchain, caches
    run-make/action.yml   # internal: exports make-env, runs `make install`, then the verb
    check-verbs/action.yml # internal: fails when a standard verb is missing
    image-meta/action.yml # internal: image name, build reference and tags to push
    image-push/action.yml # internal: checks $(IMAGE) was built, logs in, tags and pushes
  actionlint.yaml         # ignores the `$/` syntax until actionlint knows it
  dependabot.yml          # keeps pinned action SHAs up to date
scripts/
  image-name.sh         # ghcr.io/<lowercase owner>/<image name>
  docker-tags.sh        # computes image tags from the event and the push mode
  export-make-env.sh    # validates, masks and exports make-env lines
  run-make.sh           # checks the rule exists, then runs make (optionally in nix develop)
  check-verbs.sh        # lists the standard verbs missing from the Makefile
  check-image.sh        # fails with a contract error when $(IMAGE) was not built
tests/
  unit/                 # one plain-bash test file per script, plus a tiny assert library
  act/run.sh            # runs ci.yml locally with act (`make act`)
  fixtures/
    plain/              # Makefile + Dockerfile, no flake (fallback path)
    bad-image/          # docker-build ignores $(IMAGE) (negative test)
    missing-verbs/      # lacks standard verbs (negative test)
flake.nix, flake.lock   # dev shell of the library itself (make, actionlint, zizmor, shellcheck, act)
Makefile                # the standard verbs, plus `make act`, for the library itself
examples/consumer/
  Makefile
  Dockerfile
  .github/workflows/ci.yml
docs/
  contract.md
  workflows.md
  releasing.md
README.md
CHANGELOG.md            # maintained by release-please
release-please-config.json
.release-please-manifest.json
version.txt             # maintained by release-please (simple release type)
CLAUDE.md
```

The library dogfoods its own contract: it has a `flake.nix` and a `Makefile` with every standard
verb, and `ci.yml` calls `check.yml` on the repository root. This is also the self-test of the Nix
path, so there is no separate Nix fixture.

### 4.2 Flow of a public workflow

Example for `test.yml`:

1. Check out the consumer repository.
2. `uses: $/.github/actions/setup-env`
3. `uses: $/.github/actions/run-make` with `rule: test`: `make install`, then `make test`.

`check.yml` adds `uses: $/.github/actions/check-verbs` between steps 2 and 3.

`$/` is GitHub's self-repository syntax (July 2026, github.com only, runner 2.336.0+). Inside a
reusable workflow it resolves to the workflow's own repository at the exact commit that is
running, so the composites always match the ref the consumer chose (`@v1`, `@main` or a SHA).
The runner downloads the whole repository at that commit, so composites reach the scripts as
`$GITHUB_ACTION_PATH/../../../scripts/`. Nothing is written to the consumer's workspace. A
cross-repository smoke test from `Metrify-App/test-app` confirmed this on 2026-10-09; it
replaced an earlier design that checked out the library at `job.workflow_sha`.

`format-check.yml`, `lint.yml`, `typecheck.yml` and `build.yml` are identical except for the verb. `docker.yml` adds the
`image-meta` and `image-push` composites around `run-make` (section 6): workflow `run:` steps
cannot reach the scripts without a checkout, so all Docker logic lives in composites.

### 4.3 `setup-env` composite

- If `<working-directory>/flake.nix` exists:
  - install Nix with `nixbuild/nix-quick-install-action`, the installer `cache-nix-action` is
    designed for (a store installed by `DeterminateSystems/nix-installer-action` was restored
    with broken hard links in CI, and Determinate Nix would also need an `id-token` permission);
  - restore and save the Nix store with `nix-community/cache-nix-action`, key based on
    `flake.nix` and `flake.lock` of the working directory;
  - if any `*-version` input is set, emit a `::warning::` saying it is ignored.
- Otherwise (fallback): rely on the tools of the runner image (`ubuntu-latest`: make, Docker,
  Node, Python, Go…). For each non-empty `node-version`, `python-version`, `go-version` input,
  call the matching `actions/setup-*` action with its built-in dependency cache **disabled**
  (those caches look for lock files at the repository root and fail or warn in monorepos, so
  caching stays explicit and uniform).
- In both cases, if `cache-paths` is set, use `actions/cache` with those paths and a key built
  from the OS, the rule and `hashFiles(cache-key-files)`. `cache-key-files` is one glob,
  relative to the repository root (not to `working-directory`).

### 4.4 `run-make` composite

1. If the `make-env` secret is set, `scripts/export-make-env.sh` parses it line by line. Each
   line must be `KEY=VALUE` with `KEY` matching `^[A-Za-z_][A-Za-z0-9_]*$` (blank lines and lines
   starting with `#` are skipped). Each non-empty value is masked with `::add-mask::` (with `%`,
   `\r` and `\n` escaped) and, once every line is valid, all pairs are appended to
   `$GITHUB_ENV`. A malformed line fails the step, naming its line number but never its value.
2. `scripts/run-make.sh install`, then the verb. For each one, `scripts/run-make.sh` checks the rule exists with `make -n <rule>`. When make reports
   `No rule to make target '<rule>'`, it emits an `::error::` annotation that names the rule and
   points to `docs/contract.md`. Any other dry-run failure is left to the real run to report.
3. Run `nix develop --command make <rule> <extra vars>` when a flake is present, otherwise
   `make <rule> <extra vars>`, in `working-directory`. `docker.yml` passes `IMAGE=...` as an
   extra variable.

## 5. Workflow interface

### 5.1 Common inputs (every public workflow)

| Input | Type | Default | Purpose |
|---|---|---|---|
| `working-directory` | string | `.` | Directory that contains the Makefile |
| `runs-on` | string | `ubuntu-latest` | Runner label |
| `timeout-minutes` | number | `30` | Job timeout |
| `node-version` | string | `''` | Fallback only: `actions/setup-node` |
| `python-version` | string | `''` | Fallback only: `actions/setup-python` |
| `go-version` | string | `''` | Fallback only: `actions/setup-go` |
| `cache-paths` | string | `''` | Extra paths to cache (multi-line) |
| `cache-key-files` | string | `''` | Glob(s) hashed into the cache key |

Secrets:

| Secret | Required | Purpose |
|---|---|---|
| `make-env` | no | `KEY=VALUE` lines exported (masked) before `make` runs |

Default job permissions: `contents: read`.

### 5.2 `docker.yml` specific inputs and outputs

| Input | Type | Default | Purpose |
|---|---|---|---|
| `image-name` | string | repository name | Image is `ghcr.io/<lowercase owner>/<image-name>` |
| `push` | string | `auto` | `auto`, `always` or `never` |

| Output | Description |
|---|---|
| `image` | Full image name without tag |
| `tags` | Newline-separated list of full image references that were pushed, empty if none |
| `digest` | Pushed image digest, empty if nothing was pushed |

A repository that builds several images calls `docker.yml` once per image, with a different
`image-name` and, if needed, `working-directory`.

The caller job must grant `permissions: { contents: read, packages: write }`: a reusable workflow
cannot get more permissions than its caller. Login uses `GITHUB_TOKEN`; no secret is needed.

## 6. Docker tagging and push

The build always uses `IMAGE=ghcr.io/<owner>/<image-name>:sha-<short sha>` (7 characters,
owner and image name lowercased because GHCR requires lowercase names). The commit is
`github.event.pull_request.head.sha` on pull requests (the commit the author pushed, not the
temporary merge commit) and `github.sha` otherwise. After `make docker-build`, the workflow
runs `docker image inspect "$IMAGE"`; if the image is missing, it fails with an annotation
explaining the `$(IMAGE)` contract.

`scripts/docker-tags.sh` computes the tags to push from the event, the ref and the push mode:

| Event | `auto` | `always` | `never` |
|---|---|---|---|
| `pull_request` | none (build only) | `sha-<short>` | none |
| push to `main` | `sha-<short>`, `latest` | same as `auto` | none |
| push to `develop` | `sha-<short>`, `develop` | same as `auto` | none |
| push of tag `vX.Y.Z` | `sha-<short>`, `vX.Y.Z` | same as `auto` | none |
| push to another branch | none | `sha-<short>` | none |
| other events (e.g. `workflow_dispatch`) | none | `sha-<short>` | none |

- A pushed Git tag that does not match `^v[0-9]+\.[0-9]+\.[0-9]+$` fails the job; nothing is
  pushed under an unexpected name.
- An unknown `push` value fails the job.
- When the tag list is non-empty, the workflow logs in to GHCR with `docker/login-action`,
  adds every tag with `docker tag`, pushes each one, and exposes the digest.
- Pull requests from forks cannot get `packages: write`; with `auto` they never push, so they
  still pass.

## 7. Library testing (`ci.yml`)

Runs on pull requests and on pushes to `main`.

- **Static analysis** (`make lint`): `actionlint` (syntax and expressions), `zizmor` on
  `.github examples tests`, `shellcheck` on `scripts/` and `tests/`. actionlint 1.7.12 does not
  know the `$/` syntax yet, so `.github/actionlint.yaml` ignores exactly those two errors.
- **Unit tests** (`make test`): plain bash, no dependency besides `make`. They cover every row of
  the table in section 6, the `always`/`never` modes, a malformed release tag, an unknown push
  mode, an uppercase owner, every `make-env` rule (including a value with `%`), the missing-rule
  annotation and the missing-image annotation.
- **Self-tests:** jobs call the public workflows from the same commit (`uses: $/.github/workflows/<name>.yml`):
  - `check` on the repository root (dogfooding, Nix path and Nix cache);
  - `check`, `format-check`, `lint`, `typecheck`, `test`, `build` on `tests/fixtures/plain`
    (fallback path; its `test` verb fails unless `install` ran first);
  - `docker` on `tests/fixtures/plain` with `push: never`.
- **Negative tests:** jobs that call a reusable workflow cannot use `continue-on-error`, so
  failure cases call the composites directly in a step with `continue-on-error: true`, then
  assert `steps.<id>.outcome == 'failure'`:
  - `run-make` with a rule that does not exist;
  - `check-verbs` on `tests/fixtures/missing-verbs`;
  - `run-make` with a malformed `make-env` line;
  - the image check after `docker-build` on `tests/fixtures/bad-image`.
- **Local runs:** `make act ARGS="-j <job>"` runs a `ci.yml` job in Docker with act. act 0.2.x
  rejects `$/` (nektos/act#6189), so `tests/act/run.sh` runs a copy of the tree where `$/` is
  rewritten to `./` (equivalent inside this repository). Jobs that install Nix need a systemd
  host and are better checked with `make lint test`.
- All third-party actions are pinned by commit SHA with a version comment; Dependabot updates
  them.

## 8. Release and versioning

- Commits follow Conventional Commits (`type(scope): summary`).
- `release.yml` runs `googleapis/release-please-action` (`release-type: simple`) on pushes to
  `main`. It keeps a release pull request open that updates `CHANGELOG.md`, `version.txt` and
  the manifest. That pull request is created with `GITHUB_TOKEN`, so it does not trigger
  `ci.yml`; this is acceptable because it only touches those three files.
- Merging the release pull request creates the `vX.Y.Z` tag and the GitHub Release. A following
  job in the same workflow then moves the floating major tag `vX` to the release commit through
  the GitHub API (`gh api`), so no credentials are persisted in a checkout.
- The first release is forced to `1.0.0` (`release-as` in the config, removed afterwards).
- A breaking change (`feat!:` or a `BREAKING CHANGE:` footer) produces the next major (`v2`).
  The previous major is frozen: no backport branch for now.
- What counts as breaking: removing or renaming an input, output, secret or workflow; changing an
  input default in a way that changes behaviour; changing the Makefile contract; changing the
  image naming or tag policy.
- Consumers are told to use `@v1`. `@main` works but receives breaking changes immediately.

## 9. Documentation

All documentation is in English.

| Document | Content |
|---|---|
| `README.md` | Purpose, 5-minute quick start, list of workflows, `@v1` vs `@main` |
| `docs/contract.md` | Standard and optional verbs, `make install` first, `$(IMAGE)`, Nix vs fallback |
| `docs/workflows.md` | Per workflow: inputs, secrets, outputs, permissions, tag table, common errors |
| `docs/releasing.md` | Release process, breaking-change policy |
| `examples/consumer/` | Copy-ready `Makefile`, `Dockerfile` and `.github/workflows/ci.yml` |
| `CLAUDE.md` | Contribution rules, aligned with `metrify-monitor` |

Example consumer workflow:

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main, develop]
    tags: ['v*.*.*']

permissions:
  contents: read

jobs:
  check:
    uses: Metrify-App/metrify-workflows/.github/workflows/check.yml@v1
    secrets:
      make-env: ${{ secrets.TEST_ENV }}
  docker:
    needs: check
    permissions:
      contents: read
      packages: write
    uses: Metrify-App/metrify-workflows/.github/workflows/docker.yml@v1
```

## 10. Alignment with metrify-template

`Metrify-App/metrify-template` owns the standard; this library implements its CI. The same change
updates the template (its own branch and pull request, released as standard version 2 with its
`bump.sh`):

- `STANDARD.md` and `.claude/rules/metrify-rules.md`: an "Optional verbs" table (`build`,
  `docker-build` with the `$(IMAGE)` contract) next to the standard verbs.
- `Makefile`: an `##@ Optional` section showing `build` and `docker-build`, commented out.
- `.github/workflows/ci.yml`: job `check` calls `check.yml@v1`; job `standard` keeps running
  `check-standard.sh`; a commented `docker` job calls `docker.yml@v1` (no Docker Hub secrets).
  It only works once `v1.0.0` of this library is released, so it merges after that release.
- `metrify-setup` skill: the toolchain goes in the `check` job inputs (`node-version`...) or the
  repo's `flake.nix`, not in CI steps.

## 11. Out of scope

- Multi-architecture images (`linux/arm64`).
- Cleanup of old GHCR images.
- Backports to a previous major version.
- Cachix or any external binary cache.
- Deployment workflows.
- Migrating consumers and mirroring workflows from `Metrify-App/github-workflows`.
- Toolchains other than Node, Python and Go in the fallback path (added when a consumer needs
  them, as a non-breaking new input).
