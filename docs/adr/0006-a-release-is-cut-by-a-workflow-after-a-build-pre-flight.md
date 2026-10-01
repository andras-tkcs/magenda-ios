# ADR 0006: A release tag is pushed by a workflow with a non-`GITHUB_TOKEN` credential, after a `build.yml` pre-flight

## Status

Accepted — 2026-10-01. Inherited from the iOS app template.

## Context

A release is a tag push, which starts `build.yml`, which uploads to App Store Connect. Three things
go wrong with that step when it is done by hand:

- a sandboxed session (Claude Code on the web) can push branches but not tags;
- a tag pushed with the workflow's own `GITHUB_TOKEN` starts no workflow at all (GitHub's
  recursion guard), so the release silently does not happen while everything reports success;
- a regression only the Release configuration shows (an optimizer-only compile error, a lost
  version number) is first found on a real, public tag.

## Decision

1. `release.yml` (`workflow_dispatch`, `dry_run` defaulting to true) runs
   `scripts/tag_release.py` on a runner and pushes the tag with `RELEASE_TAG_TOKEN`, a token that
   is not the `GITHUB_TOKEN`. It refuses to start without it, and after pushing it waits for a
   `build.yml` run on the tagged commit and fails if none appears.
2. Before `release.yml` is dispatched, `build.yml` is dispatched against the exact commit to tag.
   Signing and upload are gated on a tag ref, so that run archives the Release configuration and
   uploads nothing.
3. `tag_release.py` refuses a second release tag on a commit, which would also reuse a build number
   (ADR 0004).

## Alternatives considered

- **Tag from a laptop.** Still allowed, with `tag_release.py`, but a release should not depend on
  which machine someone is at.
- **Use the `GITHUB_TOKEN` and trigger `build.yml` with `workflow_call`.** Rejected: two paths into
  the release build, and the tag-push path would still be silent when misused.

## Consequences

- One secret, `RELEASE_TAG_TOKEN`, to create and rotate.
- The pre-flight archives unsigned, so a signing problem still surfaces only on a tag. A release
  candidate tag (`-rc.N`) before each stable one finds it without affecting App Store users.
- `/cut-release` encodes the order: pre-flight, dry run, then the real cut on the maintainer's word.

## Verification

`.github/workflows/release.yml`; `scripts/tag_release.py` and its tests;
`.claude/commands/cut-release.md`.
