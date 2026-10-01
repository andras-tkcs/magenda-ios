# ADR 0005: `CHANGELOG.md` is the only source of release notes

## Status

Accepted — 2026-10-01. Inherited from the iOS app template.

## Context

GitHub can generate release notes from merged pull requests, but the result is a list of PR
titles written for reviewers, not for the people who use the app. Notes written on tag day are
rushed and unreviewed.

## Decision

1. A user-visible change adds its line under `## [Unreleased]` in the same PR.
2. The PR that prepares a release turns `[Unreleased]` into the version's section.
3. `build.yml` renders the stable release's GitHub Release body with
   `scripts/changelog_section.py`, which fails when the section is missing, duplicated, or when
   `[Unreleased]` still has entries.
4. The App Store's "What's New" text is written from that section when the version is submitted.

## Alternatives considered

- **GitHub's generated notes.** Rejected: written for the wrong audience.
- **Silently falling back to generated notes when the section is missing.** Rejected: a release
  with the wrong notes should fail, not ship.

## Consequences

- Release notes are reviewed in a pull request like any other change.
- Feature branches never open a version heading.

## Verification

`scripts/changelog_section.py` and its tests in `scripts/tests/test_scripts.py`;
`.github/workflows/build.yml`'s `github-release` job; `.github/workflows/release.yml`'s
"Render release notes" step.
