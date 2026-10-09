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
