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
