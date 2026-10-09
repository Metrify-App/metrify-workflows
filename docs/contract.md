# Makefile contract

The library never knows a repository's stack. Its workflows only run the make verbs of the
Metrify repo standard; each repository decides what those verbs do. The standard is defined in
[metrify-template](https://github.com/Metrify-App/metrify-template/blob/main/.claude/skills/metrify-sync/STANDARD.md)
("Make verbs"); this page restates what the workflows rely on.

## Standard verbs

Every Metrify repository has these targets. A verb with nothing to do for the stack prints
`<verb>: nothing to do` and exits 0.

| Verb | Does | Workflow |
|------|------|----------|
| `help` | Lists targets (default goal). | none |
| `install` | Installs dependencies. | run first by every workflow |
| `dev` | Runs the project locally. | none |
| `format` / `format-check` | Formats / checks formatting. | `format-check.yml` |
| `lint` | Lints. | `lint.yml` |
| `typecheck` | Type checks. | `typecheck.yml` |
| `test` | Runs the tests. | `test.yml` |
| `fix` | `format` + autofixable lint. | none |
| `check` | `format-check lint typecheck test`: everything the CI runs. | `check.yml` |

After `make install`, `check.yml` reads the Makefile's rule database (`make -pRrq`: no verb recipe
runs, though make still parses the Makefile and may regenerate included makefiles) and fails
when a verb has no rule, even if `.PHONY` lists it. Only explicit targets count, not `%` pattern
rules:

```
The Makefile lacks the standard verbs: typecheck fix. Every Metrify repo has help install dev format format-check lint typecheck test fix check.
```

## Optional verbs

Only for repositories that ship a binary or an image:

| Verb | Does | Workflow |
|------|------|----------|
| `build` | Compiles the project. | `build.yml` |
| `docker-build` | Builds the image tagged `$(IMAGE)`. Never pushes. | `docker.yml` |

Calling a workflow whose verb is missing fails with:

```
The Makefile has no 'build' rule. Add it, or stop calling the build workflow.
```

## `make install` first

Each workflow runs on a fresh runner: it runs `make install`, then its verb, in the same job.
No Make prerequisite on `install` is needed (it would run twice).

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
