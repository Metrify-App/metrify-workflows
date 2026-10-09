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

Login uses the job's `GITHUB_TOKEN`; no secret is needed. Runs are serialized per repository, ref and
image (`concurrency`), so an older run never overwrites `latest` or `develop` with an older image. Pull requests from forks never get
`packages: write`, so leave `push: auto` for them.

## Common errors

| Message | Cause | Fix |
|---------|-------|-----|
| `The Makefile has no '<rule>' rule` | The workflow is called but the rule does not exist. | Add the rule, or remove the job. |
| `make docker-build did not produce '<image>'` | `docker-build` does not tag with `$(IMAGE)`. | Use `docker build -t $(IMAGE) .`. |
| `Git tag '<tag>' is not a release tag (expected vX.Y.Z)` | A pushed tag triggered the workflow. | Restrict the trigger to `tags: ["v*.*.*"]` or use `push: never`. |
| `invalid image name '<name>'` | `image-name` has characters GHCR does not accept. | Use lowercase letters, digits, `.`, `_` and `-`. |
| `unknown push mode` | `push` is not `auto`, `always` or `never`. | Fix the input. |
| `make-env line N is not KEY=VALUE` | A malformed line in the `make-env` secret. | Fix line N (the value is never printed). |
| `cache-paths is set but cache-key-files is empty` | A cache without a key would never be refreshed. | Set `cache-key-files`. |
| `make: command not found` (Nix) | The devShell does not provide make. | Add `gnumake` to the devShell packages. |
| `The workflow is requesting 'packages: write', but is only allowed 'packages: none'` | The calling job does not grant the permission. | Add `permissions: { contents: read, packages: write }` to the job. |
