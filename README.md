# Metrify workflows

Reusable GitHub Actions workflows for every Metrify repository. A repository imports only the
workflows it needs; a fix made here reaches every repository that uses `@v1`.

The workflows know nothing about your stack: each one runs a standard Makefile rule
(`make lint`, `make test`...). Your Makefile decides what the rule does.

## Quick start

1. Give your repository the Metrify make verbs (`help`, `install`, `dev`, `format`,
   `format-check`, `lint`, `typecheck`, `test`, `fix`, `check`), plus `docker-build` if it ships
   an image. Repositories created from
   [metrify-template](https://github.com/Metrify-App/metrify-template) already have them; see
   [docs/contract.md](docs/contract.md) and [examples/consumer/Makefile](examples/consumer/Makefile).

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
     check:
       uses: Metrify-App/metrify-workflows/.github/workflows/check.yml@v1
       permissions:
         contents: read
     docker:
       needs: check
       uses: Metrify-App/metrify-workflows/.github/workflows/docker.yml@v1
       permissions:
         contents: read
         packages: write
   ```

## Workflows

Each one runs `make install`, then its verb.

| Workflow | Runs | Pushes to GHCR |
|----------|------|----------------|
| `check.yml` | standard verbs check, then `make check` (the default) | no |
| `format-check.yml` | `make format-check` | no |
| `lint.yml` | `make lint` | no |
| `typecheck.yml` | `make typecheck` | no |
| `test.yml` | `make test` | no |
| `build.yml` | `make build` (optional verb) | no |
| `docker.yml` | `make docker-build IMAGE=...` (optional verb) | `sha-<commit>`, plus `latest` on `main`, `develop` on `develop`, `vX.Y.Z` on release tags |

Inputs, outputs, permissions and errors: [docs/workflows.md](docs/workflows.md).
Repositories with a `flake.nix` run their verbs inside `nix develop`; the others use the tools
of the GitHub runner, with optional `node-version`, `python-version` and `go-version` inputs.

## Versions

Use `@v1`: it follows every compatible release. `@main` also receives breaking changes
immediately. See [docs/releasing.md](docs/releasing.md) and [CHANGELOG.md](CHANGELOG.md).

## Contributing

Work in the dev shell (`nix develop`, or direnv), then:

```sh
make check  # format-check, lint (actionlint, zizmor, shellcheck), typecheck, test
make act ARGS="-j fixture-test"   # one ci.yml job locally, in Docker (act)
```

Pull requests also run the self-tests in `.github/workflows/ci.yml`. Design:
[docs/superpowers/specs/](docs/superpowers/specs/). Rules for contributors: [CLAUDE.md](CLAUDE.md).
