# Releasing

How a Magenda release is versioned, cut, built, gated and uploaded. The checks a human
runs before a release are in [`release-testing.md`](release-testing.md).

## Versioning

There is no version in the source tree that a release edits, and no version-bump commit
(ADR 0004). `project.yml` carries `MARKETING_VERSION: 0.0.0` and `CURRENT_PROJECT_VERSION: 0`
only as what a local build shows; `build.yml` overrides both on the `xcodebuild` command line:

- **Version** (`CFBundleShortVersionString`): the tag without its `v` and without any pre-release
  suffix. App Store Connect accepts only `X.Y.Z`, so `v1.2.0-rc.1` ships as version `1.2.0`.
- **Build number** (`CFBundleVersion`): `git rev-list --count HEAD`, the number of commits behind
  the tagged commit. It grows with every merge to `main`, so every upload has a build number App
  Store Connect has not seen.

Tags are `vX.Y.Z` (stable) or `vX.Y.Z-alpha.N`, `vX.Y.Z-beta.N`, `vX.Y.Z-rc.N` (pre-release).
Every tag uploads to App Store Connect; what differs is who gets it (see "TestFlight and the App
Store" below) and whether the GitHub Release carries notes.

The build number needs the full history: `build.yml` checks out with `fetch-depth: 0`, and the
Claude Code session-start hook unshallows the web checkout for the same reason.

## Cutting a release

**A release is a tag, not a commit.** Once `main` is at the commit to release:

```
python3 scripts/tag_release.py 1.2.0          # checks, then creates v1.2.0 locally
git push origin v1.2.0
```

`scripts/tag_release.py` runs the checks the tag step otherwise has no gate for: clean tree, at
`origin/main`'s tip, no second tag on the commit, the tag format above, sequential with no gaps.
See its docstring.

**Or cut it from the Actions tab.** `.github/workflows/release.yml` (`workflow_dispatch`, inputs
`version` and `dry_run`) resolves the channel, renders the stable release notes, and runs
`tag_release.py` against `main`'s tip on a runner. `dry_run` **defaults to true**: it runs every
check and creates the tag on the runner without pushing it. This is the only way to cut a release
from a sandboxed session (such as Claude Code on the web), which can push branches but not tags;
see `/cut-release`.

It needs one secret, `RELEASE_TAG_TOKEN`, and **it may not be the `GITHUB_TOKEN`**: GitHub starts
no workflow for an event the `GITHUB_TOKEN` raised, so a tag pushed with it would create the tag,
start no `build.yml`, and report success. Use a fine-grained personal access token with
**Contents: write** on this repository only. The workflow refuses to start without the secret, and
after pushing it waits for a `build.yml` run on the tagged commit and fails loudly if none appears
(ADR 0006).

**Pre-flight `build.yml` before tagging.** `release.yml` builds nothing. Dispatch `build.yml` (no
inputs) against the exact commit to tag and confirm the `archive` job succeeds. It is safe on an
untagged commit: signing and upload are gated on a tag ref.

**One release tag per commit.** A second tag on a released commit would upload a build number App
Store Connect has already accepted, and fail. Move the release forward onto a new commit instead;
`tag_release.py` refuses.

## Release notes come from CHANGELOG.md

A stable release's GitHub Release body is `CHANGELOG.md`'s section for that version, rendered by
`scripts/changelog_section.py` (ADR 0005). That makes the notes a pull-request deliverable: **the
PR that prepares a release leaves `CHANGELOG.md` with exactly one `## [X.Y.Z] — YYYY-MM-DD`
heading for the version, a fresh empty `## [Unreleased]` above it, and the link definitions at the
bottom updated — before tagging.**

Usually that means renaming `## [Unreleased]`. Check first whether a section for that version
already exists: renaming on top of one produces a second heading. If one exists, merge
`[Unreleased]`'s entries into it and correct its date.

The render fails, deliberately, when the version has no section, when it has two, and when
`[Unreleased]` still has entries. `--allow-unreleased` exists for reading a section by hand
mid-cycle; no workflow passes it.

The App Store's "What's New in This Version" text is written for App Store users and entered in
App Store Connect when the version is submitted for review (a manual step in
[`release-testing.md`](release-testing.md)). Start it from the same changelog section.

## Build and upload

A `v*` tag push starts `.github/workflows/build.yml`:

1. **`version`** — resolves the channel, the version and the build number.
2. **`archive`** — generates the Xcode project, archives the Release configuration unsigned, and
   checks the archive's `Info.plist` carries the version and build number it was given.
3. **`testflight`** — archives again with automatic signing and uploads to App Store Connect, in
   the `app-store` environment (ADR 0009).
4. **`github-release`** — creates the GitHub Release; for a stable tag the body is the changelog
   section, for a pre-release the entry is marked pre-release.

## Signing and App Store Connect

Signing uses Xcode's automatic signing, driven by an App Store Connect API key; there are no
certificates, provisioning profiles or passwords in the repository or in GitHub (ADR 0009).

Before the first upload:

1. **The app record.** In App Store Connect, **Apps → + → New App**, with bundle ID
   `name.felhasznalo.magenda`. Register the bundle ID first under **Certificates, Identifiers & Profiles →
   Identifiers** if it is not offered.
2. **The team.** Put the ten-character Team ID (**Membership details** in the developer account) in
   `project.yml`'s `DEVELOPMENT_TEAM`, in a PR.
3. **The API key.** In App Store Connect, **Users and Access → Integrations → App Store Connect
   API → Team Keys**, generate a key with the **App Manager** role (it must be allowed to create
   distribution certificates and profiles for cloud signing; use **Admin** if your account's
   settings require it). Download the `.p8` once.
4. **The environment.** In the repository's **Settings → Environments**, create `app-store` and
   add three secrets: `ASC_KEY_P8` (the whole `.p8` file's contents), `ASC_KEY_ID` (the key's ID)
   and `ASC_ISSUER_ID` (the issuer ID shown above the keys list). Optionally add a required
   reviewer, so every upload is a go/no-go.
5. **An app icon.** Put a 1024×1024 PNG into `App/Assets.xcassets/AppIcon.appiconset/` and name it
   in that folder's `Contents.json`. App Store Connect rejects an upload without one.

## TestFlight and the App Store

Every uploaded build appears in App Store Connect's **TestFlight** tab after Apple finishes
processing it (usually minutes). Internal testers get it automatically if a group is set to; a
pre-release meant for external testers is added to an external group, which needs a one-time Beta
App Review.

Submitting a stable version to the App Store is manual: in App Store Connect, add the version,
pick its build, write "What's New", and submit for review. The checks before that are in
[`release-testing.md`](release-testing.md).
