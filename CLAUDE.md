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
