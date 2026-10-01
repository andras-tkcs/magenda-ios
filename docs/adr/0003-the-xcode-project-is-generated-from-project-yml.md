# ADR 0003: The Xcode project is generated from `project.yml` by XcodeGen and never committed

## Status

Accepted — 2026-10-01. Inherited from the iOS app template.

## Context

An `.xcodeproj` is a generated-looking file that people edit through Xcode's UI. Its
`project.pbxproj` is thousands of lines of object IDs, rewritten wholesale by small UI changes, so
two branches that each add a file or a build setting conflict in ways nobody can resolve by reading
the diff. Work here is often done by several sessions in parallel and merged phase by phase
(`/implement`), which makes those conflicts routine rather than rare. A reviewer also cannot tell
from a pbxproj diff which build setting changed and why.

## Decision

1. The project is described by `project.yml`, a short, reviewable YAML file. `xcodegen generate`
   writes `Magenda.xcodeproj` from it.
2. `*.xcodeproj/` is git-ignored. Nobody commits it, and a change made in Xcode's project editor is
   lost on the next generate unless it is also made in `project.yml`.
3. Build settings live in `project.yml`, with a comment where the reason is not obvious.
4. CI installs XcodeGen and generates the project before every build. `project.yml`'s
   `options.minimumXcodeGenVersion` refuses a version older than the spec needs.

## Alternatives considered

- **Commit the `.xcodeproj`, using Xcode's folder-synchronized groups.** Adding a file no longer
  touches the pbxproj, but targets, schemes and build settings still do, and those diffs stay
  unreviewable and conflict-prone.
- **Tuist.** A Swift manifest instead of YAML, with more features (caching, module graphs) than
  one app needs, and its own versioned toolchain to install and keep current.
- **Swift Package Manager alone.** A package cannot produce a signed iOS app bundle with its
  Info.plist, assets and entitlements; it is used for the app's logic instead (ADR 0007).

## Consequences

- A fresh checkout needs `xcodegen generate` before Xcode can open it, and so does a pull that
  changed `project.yml`. The README says so.
- XcodeGen is a build-time dependency of every macOS job, installed from Homebrew without an upper
  version bound; a new XcodeGen release that changes generated output shows up as a CI failure,
  not a silent difference.
- Adding a file needs nothing: XcodeGen picks up everything under a target's `sources` folders.

## Verification

`project.yml`; `.gitignore`; the `xcodegen generate` steps in `.github/workflows/tests.yml` and
`build.yml`; `scripts/pre_release_check.py`.
