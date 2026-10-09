# Releasing

## Which ref should consumers use?

- **`@v1`** (recommended): the floating major tag. It receives every fix and backward-compatible
  feature as soon as it is released, and never a breaking change.
- `@v1.2.3` or a commit SHA: frozen; upgrade by hand.
- `@main`: every merged change immediately, including breaking ones. Avoid it outside tests.

## Prerequisite

release-please opens its pull request with `GITHUB_TOKEN`. The repository (or the organization)
must allow it: Settings → Actions → General → Workflow permissions → "Allow GitHub Actions to
create and approve pull requests". Without it, `release.yml` fails with "GitHub Actions is not
permitted to create or approve pull requests" and no version is published.

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
