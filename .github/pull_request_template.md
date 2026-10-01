## What this changes

<!-- Why the change is needed, not just what it does. -->

## Definition of done

The checklist from [`docs/coding-and-testing-guidelines.md`, "Definition of done"](../docs/coding-and-testing-guidelines.md#definition-of-done),
which is the authoritative copy. Tick what you ran; strike through anything genuinely not
applicable with a one-line reason rather than leaving it blank. `/dod` runs the commands.

### Every PR

- [ ] `swift test --package-path AppCore --enable-code-coverage` passes at 100%, and
      `scripts/check_coverage_floor.py` passes on its report.
- [ ] `swift format lint --strict` and `python3 -m unittest discover -s scripts/tests` pass.
- [ ] The app tests and UI tests pass on every simulator `tests.yml` runs.
- [ ] A user-visible change has a line under `CHANGELOG.md`'s `## [Unreleased]` (never under a
      version heading).
- [ ] A decision that is hard to reverse, moves a trust boundary, changes the build/release path,
      or rejects a non-obvious alternative has an ADR in `docs/adr/`. A PR that deletes a plan
      document extracts its decisions into ADRs first, or says below that it made none.
- [ ] New logic is in AppCore with tests; views hold layout and state only.
- [ ] New elements a UI test touches have accessibility identifiers; new interactive elements have
      accessibility labels.
- [ ] No log line or error message carries a credential, a token or the user's content.
- [ ] Comments only where the *why* is non-obvious; no project history in code or docs.
- [ ] Standing docs describe the new behavior.

### Only if this PR touches those files

- [ ] **`project.yml`** — `xcodegen generate` run and the app builds; new targets are in the
      scheme; changed build settings are commented.
- [ ] **Permissions, entitlements or privacy** — purpose strings written for the user; the App
      Store Connect privacy answers that change are listed under "Manual verification" below.
- [ ] **A dependency in `AppCore/Package.swift`** — bounded version range; an ADR for a new
      third-party package; a dispatched `build.yml` run linked.
- [ ] **`.github/workflows/`** — dispatchable workflows are on `main`, or this PR says they become
      dispatchable after merge.

## Manual verification

<!-- Real-device or App Store Connect steps a person has to do, as unchecked items; delete this
section if there are none. -->

## Notes for review

<!-- Anything a reviewer should look at first, or a decision worth a second opinion. -->
