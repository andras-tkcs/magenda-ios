# ADR 0004: The version comes from the git tag and the build number from the commit count

## Status

Accepted — 2026-10-01. Inherited from the iOS app template.

## Context

A version kept in files and bumped by a commit fails in a predictable way: two branches in flight
both bump to the same next version, one merges after another release already took that number,
and a release ships with the wrong version or has to be reverted. App Store Connect adds a second
number with its own rule: every upload of a version needs a build number it has not seen before,
and a forgotten bump is only discovered when the upload is rejected.

## Decision

1. `project.yml` carries `MARKETING_VERSION: 0.0.0` and `CURRENT_PROJECT_VERSION: 0` only as what a
   local build shows. Nobody edits them to cut a release.
2. `build.yml` sets `MARKETING_VERSION` to the tag's `X.Y.Z` (a pre-release suffix is dropped,
   because App Store Connect accepts only `X.Y.Z`) and `CURRENT_PROJECT_VERSION` to
   `git rev-list --count HEAD`, on the `xcodebuild` command line.
3. The archive's `Info.plist` is checked for both before anything is uploaded.
4. `CHANGELOG.md` is never parsed to decide a version.

## Alternatives considered

- **Bump the numbers in a release PR** (by hand, or with `agvtool`). Rejected for the failure
  above, and because the bump commit, not the tagged commit, would decide what ships.
- **The workflow run number as the build number.** It restarts if the workflow is renamed or
  recreated, and a re-run of the same commit gets a different number.
- **A timestamp as the build number.** Unique, but says nothing about which commit was built.

## Consequences

- Every workflow that computes the build number checks out with `fetch-depth: 0`, and the Claude
  Code web session hook unshallows its checkout; a shallow clone would count one commit.
- The commit count only grows on `main` as long as `main`'s history is never rewritten, which
  branch protection already forbids.
- A commit can carry only one release tag (ADR 0006): a second would reuse a build number.

## Verification

`project.yml`; `.github/workflows/build.yml` (the `version` job and the archive check);
`scripts/release_channel.py --marketing`; `.claude/hooks/session-start.sh`.
