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
- The library knows nothing about consumer stacks: it only calls standard Makefile rules.
- Docker images are pushed to GHCR with one shared naming convention, and only the library
  handles registries, tokens and tags.
- The library is versioned (`vX.Y.Z` plus a floating major `vX`) and tests itself.

Prerequisites:

- **The repository is public.** Public workflows check out the library itself (section 4.2).
  A consumer's `GITHUB_TOKEN` can only read its own repository, so that checkout fails when the
  library is private. The library contains no secret and no business code.
- The older private repository `Metrify-App/github-workflows` (`docker-build-push.yml`,
  repository mirroring) is replaced by this library over time. Migrating its consumers, its
  mirroring workflows and archiving it are out of scope here.

## 2. Decisions summary

| Topic | Decision |
|---|---|
| Building blocks | One reusable workflow (`workflow_call`) per Makefile rule, built on shared internal composite actions |
| Missing rules | No detection, no flags: a consumer imports only the workflows whose rule it implements |
| `make install` | Not a workflow. Consumers declare it as a Make prerequisite (`test: install`) when needed |
| Tooling | Nix if the consumer has `flake.nix`, otherwise the GitHub runner image plus optional `*-version` inputs |
| Nix cache | GitHub Actions cache (`nix-community/cache-nix-action`), keyed on `flake.lock` |
| Docker handoff | `make docker-build IMAGE=<full name>`; the Makefile must tag its image with `$(IMAGE)` |
| Architectures | `linux/amd64` only |
| Push policy | Event-driven (`push: auto`), overridable with `always` / `never` |
| Release image tags | `vX.Y.Z` only (no floating image tags) |
| Make secrets | One optional multi-line secret `make-env` (`KEY=VALUE` lines) |
| Library releases | release-please, `CHANGELOG.md`, floating major tag `vX` |
| Recommended consumer ref | `@v1` |
| Library tests | actionlint + zizmor + shellcheck, unit tests for every script, self-tests (dogfooding + fixtures) |
| Dependency caches | Only through `cache-paths` / `cache-key-files`; built-in `setup-*` caches are disabled |
| Docs | All in this repository, in English |

## 3. Makefile contract

Consumer repositories provide a `Makefile` with standard rule names. The library only ever runs
`make <rule>`; each repository decides what its rules do.

| Rule | Called by | Contract |
|---|---|---|
| `lint` | `lint.yml` | Checks style and code quality. Non-zero exit fails the job. |
| `test` | `test.yml` | Runs the tests. |
| `build` | `build.yml` | Compiles the project. |
| `docker-build` | `docker.yml` | Builds the image and tags it with `$(IMAGE)`. Must not push. |
| `install` | nobody directly | Conventional name for installing dependencies. Other rules depend on it when needed. |

Rules:

- A repository that does not implement a rule does not import the matching workflow.
- Dependencies between rules are expressed in Make, so CI and local runs behave the same:

  ```make
  test: install
  lint: install
  ```

- `docker-build` must honour the `IMAGE` variable and keep a local default:

  ```make
  IMAGE ?= my-service:dev

  docker-build:
  	docker build -t $(IMAGE) .
  ```

- Makefiles never log in to a registry, push, or handle tokens.
- A repository with a `flake.nix` runs `nix develop --command make <rule>` in CI, so its
  devShell must provide `gnumake`.
- The library is checked out into `.metrify-workflows/` inside the workspace during CI
  (section 4.2). Consumers exclude that directory from their linters and from the Docker build
  context (`.dockerignore`).

## 4. Architecture

### 4.1 Repository layout

```
.github/
  workflows/
    lint.yml            # public: runs `make lint`
    test.yml            # public: runs `make test`
    build.yml           # public: runs `make build`
    docker.yml          # public: runs `make docker-build`, tags and pushes to GHCR
    ci.yml              # internal: static analysis, unit tests, self-tests
    release.yml         # internal: release-please and floating major tag
  actions/
    setup-env/action.yml  # internal: Nix or fallback toolchain, caches
    run-make/action.yml   # internal: exports make-env, checks the rule, runs make
  actionlint.yaml         # ignores job.workflow_* until actionlint knows them
  dependabot.yml          # keeps pinned action SHAs up to date
scripts/
  image-name.sh         # ghcr.io/<lowercase owner>/<image name>
  docker-tags.sh        # computes image tags from the event and the push mode
  export-make-env.sh    # validates, masks and exports make-env lines
  run-make.sh           # checks the rule exists, then runs make (optionally in nix develop)
  check-image.sh        # fails with a contract error when $(IMAGE) was not built
tests/
  unit/                 # one plain-bash test file per script, plus a tiny assert library
  fixtures/
    plain/              # Makefile + Dockerfile, no flake (fallback path)
    bad-image/          # docker-build ignores $(IMAGE) (negative test)
flake.nix, flake.lock   # dev shell of the library itself (actionlint, zizmor, shellcheck, make)
Makefile                # `make lint` and `make test` for the library itself
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

The library dogfoods its own contract: it has a `flake.nix` and a `Makefile`, and `ci.yml`
calls `lint.yml` and `test.yml` on the repository root. This is also the self-test of the Nix
path, so there is no separate Nix fixture.

### 4.2 Flow of a public workflow

Example for `test.yml`:

1. Check out the consumer repository.
2. Check out the library itself, `${{ job.workflow_repository }}` at `${{ job.workflow_sha }}`,
   into `.metrify-workflows/`. This guarantees the composites run at exactly the same version as
   the workflow the consumer referenced (`@v1`, `@main` or a SHA), instead of a hard-coded ref.
   These `job.*` context properties exist on github.com since September 2026 (not on GHES).
   The checkout is sparse (`.github/actions` and `scripts` only) and `.metrify-workflows/` is
   added to `.git/info/exclude`. Because local `uses:` paths must live in the workspace, the
   directory is visible to the consumer's rules: `docs/contract.md` tells consumers to exclude
   `.metrify-workflows/` from linters and from the Docker build context (`.dockerignore`).
3. `uses: ./.metrify-workflows/.github/actions/setup-env`
4. `uses: ./.metrify-workflows/.github/actions/run-make` with `rule: test`.

`lint.yml` and `build.yml` are identical except for the rule. `docker.yml` adds the tagging,
login and push steps (section 6).

### 4.3 `setup-env` composite

- If `<working-directory>/flake.nix` exists:
  - install upstream Nix (`DeterminateSystems/nix-installer-action` with `determinate: false`:
    Determinate Nix logs in to FlakeHub, which needs an `id-token` permission callers would
    have to grant);
  - restore and save the Nix store with `nix-community/cache-nix-action`, key based on
    `hashFiles('<working-directory>/flake.lock')`;
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
2. `scripts/run-make.sh` checks the rule exists with `make -n <rule>`. When make reports
   `No rule to make target '<rule>'`, it emits an `::error::` annotation that names the rule and
   points to `docs/contract.md`. Any other dry-run failure is left to the real run to report.
3. Run `nix develop --command make <rule> <extra vars>` when a flake is present, otherwise
   `make <rule> <extra vars>`, in `working-directory`. `docker.yml` passes `IMAGE=...` as an
   extra variable.

## 5. Workflow interface

### 5.1 Common inputs (`lint`, `test`, `build`, `docker`)

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

- **Static analysis** (`make lint`): `actionlint` (syntax and expressions), `zizmor` on explicit
  paths (`.github examples tests`, never the `.metrify-workflows/` checkout), `shellcheck` on
  `scripts/` and `tests/`. actionlint does not know `job.workflow_repository` and
  `job.workflow_sha` yet, so `.github/actionlint.yaml` ignores exactly those two errors.
- **Unit tests** (`make test`): plain bash, no dependency besides `make`. They cover every row of
  the table in section 6, the `always`/`never` modes, a malformed release tag, an unknown push
  mode, an uppercase owner, every `make-env` rule (including a value with `%`), the missing-rule
  annotation and the missing-image annotation.
- **Self-tests:** jobs call the public workflows locally (`uses: ./.github/workflows/<name>.yml`):
  - `lint` and `test` on the repository root (dogfooding, Nix path and Nix cache);
  - `lint`, `test`, `build` on `tests/fixtures/plain` with `node-version` set (fallback path);
  - `docker` on `tests/fixtures/plain` with `push: never`.
- **Negative tests:** jobs that call a reusable workflow cannot use `continue-on-error`, so
  failure cases call the composites directly in a step with `continue-on-error: true`, then
  assert `steps.<id>.outcome == 'failure'`:
  - `run-make` with a rule that does not exist;
  - `run-make` with a malformed `make-env` line;
  - the image check after `docker-build` on `tests/fixtures/bad-image`.
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
| `docs/contract.md` | Makefile rules, `$(IMAGE)`, `test: install` pattern, Nix vs fallback |
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
  lint:
    uses: Metrify-App/metrify-workflows/.github/workflows/lint.yml@v1
  test:
    uses: Metrify-App/metrify-workflows/.github/workflows/test.yml@v1
    secrets:
      make-env: ${{ secrets.TEST_ENV }}
  docker:
    needs: [lint, test]
    permissions:
      contents: read
      packages: write
    uses: Metrify-App/metrify-workflows/.github/workflows/docker.yml@v1
```

## 10. Out of scope

- Multi-architecture images (`linux/arm64`).
- Cleanup of old GHCR images.
- Backports to a previous major version.
- Cachix or any external binary cache.
- Deployment workflows.
- Migrating consumers and mirroring workflows from `Metrify-App/github-workflows`.
- Toolchains other than Node, Python and Go in the fallback path (added when a consumer needs
  them, as a non-breaking new input).
