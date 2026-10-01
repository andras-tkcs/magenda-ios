# ADR 0007: Logic lives in AppCore, a Swift package that builds and tests on Linux; the app target is a thin SwiftUI shell

## Status

Accepted — 2026-10-01. Inherited from the iOS app template.

## Context

Everything that builds an iOS app needs macOS and Xcode: compiling the app target, running its
tests on a simulator, previewing a view. Much of the work on this repository happens where there is
no Mac — a Claude Code cloud session runs on Linux — and even on a Mac a simulator test run takes
minutes. Logic tested only through the app target is tested slowly, and from a cloud session not
at all.

## Decision

1. The app's logic lives in `AppCore/`, a local Swift package that depends on Foundation at most.
   It never imports SwiftUI, UIKit, Combine or another Apple-only framework.
2. `App/` holds views, navigation and the app lifecycle, and computes nothing it could ask AppCore
   for.
3. AppCore is tested with `swift test`, on Linux in CI (`tests.yml`'s `core` job) and wherever a
   session has a Swift toolchain. Its line coverage is the ratchet
   (`scripts/check_coverage_floor.py`); the app target's views are covered by UI tests instead.

## Alternatives considered

- **Everything in the app target, tested on a simulator.** Rejected: no test runs without a Mac,
  and each run costs a simulator boot.
- **A coverage ratchet over the app target as well.** Rejected for now: view code measured line
  by line rewards tests that assert nothing; UI tests prove the screens instead.
- **Several feature packages from the start.** Rejected until the app is big enough for build
  times or ownership to need them; splitting AppCore later is mechanical.

## Consequences

- An Apple-only API that logic needs (the Keychain, `os.Logger`, `UserDefaults`) sits behind a
  protocol AppCore defines, implemented in `App/`; AppCore's tests use a fake.
- A cloud session can run the unit layer and the coverage ratchet itself, once its environment can
  install a Swift toolchain (`.claude/hooks/session-start.sh`).
- `swift test` on Linux uses the open-source Foundation, which can differ from Apple's in rare
  corners; the `app` jobs run AppCore inside the real app as well.

## Verification

`AppCore/Package.swift`; `.github/workflows/tests.yml` (`core`); `scripts/check_coverage_floor.py`;
`docs/coding-and-testing-guidelines.md`, "Where code goes".
