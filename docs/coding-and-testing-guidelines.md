# Coding and testing guidelines

The repository's standing expectations for implementation and test changes. Keep this document
descriptive: when a pattern becomes established in `AppCore/`, `App/` and the test targets, write it
down here; when a rule here stops matching the code, fix one or the other in the same PR.

See [`CONTRIBUTING.md`](../CONTRIBUTING.md) for process (branches, PRs, ADRs) and
[`testing-policy.md`](testing-policy.md) for which test runs where. This document covers how to
write, test and extend the code.

## Coding guidelines

### Where code goes

| Code | Lives in | Tested by |
|---|---|---|
| Logic: parsing, validation, formatting, state machines, networking clients, persistence models | `AppCore/Sources/` (a Swift package, Foundation at most) | `swift test` in `AppCore/Tests/`, on Linux and macOS |
| Views, navigation, app lifecycle, anything that imports SwiftUI or UIKit | `App/` | UI tests in `AppUITests/` |
| What only the built app can show: its bundle, entitlements, launch | — | Hosted tests in `AppTests/` |

AppCore must build and test with `swift test` on Linux (ADR 0007). It never imports SwiftUI, UIKit,
Combine or any other Apple-only framework; if a type needs one, it belongs in `App/`, or AppCore
defines a protocol and the app supplies the Apple-specific implementation. A view computes nothing
it could ask AppCore for.

### Language baseline

- Swift 6 language mode, with complete concurrency checking. Warnings are errors in the app target
  (`SWIFT_TREAT_WARNINGS_AS_ERRORS` in `project.yml`), so a new warning fails the build.
- Apple's frameworks and the Swift standard library first. A third-party package is a deliberate
  exception and gets an ADR saying why.
- No force unwraps (`!`), no `try!`, no implicitly unwrapped optionals outside `@IBOutlet`-style
  framework requirements. `swift format lint` enforces these (`.swift-format`).
- Value types by default. A reference type that holds mutable state shared across tasks is an
  `actor` or `@MainActor`-isolated; never silence the compiler with `@unchecked Sendable` or
  `nonisolated(unsafe)` without a comment saying why it is safe.

### Documentation and comments

- Every `public` declaration in AppCore has a `///` documentation comment (`.swift-format`'s
  `AllPublicDeclarationsHaveDocumentation`). A type with a non-obvious invariant explains it there.
- Default to no other comments. Add one only for a non-obvious *why*: a hidden constraint, a
  workaround for a platform bug, a race that was fixed. Never restate *what* the next line does.
- Comments, documentation and user-visible strings carry no project history: no phase names, plan
  or review item IDs, bare issue or PR numbers, or "as of version N" phrasing. Say the reason in
  your own words; when the reason is a decision, name its ADR (`ADR 0007`). Open work is cited by
  the issue's full URL, with the limitation described next to it. History belongs in
  `CHANGELOG.md` and the ADRs. `scripts/tests/test_no_project_history.py` enforces this
  (ADR 0008).

### Views

- One screen per file in `App/`, named after what it shows (`ContentView` is the placeholder).
- State the view owns is `@State private`; state it is handed is a `let` or a `@Binding`. Shared
  model state is an `@Observable` type injected through the environment, not a singleton.
- Every element a UI test reads or taps has an `accessibilityIdentifier`, declared once in the
  view's `ID` enum. UI tests find elements by identifier, never by visible text.
- Every interactive element has an accessibility label a VoiceOver user understands; an icon-only
  button gets an explicit `accessibilityLabel`. Layout works at the largest Dynamic Type size.
- Every view has a `#Preview` with representative data.

### Untrusted input

- Everything that arrives from outside the app — a server response, a deep link, a pasted string,
  a file the user opens — is untrusted. Decode it in AppCore into a typed value at the boundary
  (`Decodable`, a failable initializer), and fail closed on anything malformed.
- Never build a URL, a query or a file path by string concatenation from such input; use
  `URLComponents` and `URL.appending(path:)`.

### Networking and persistence

- An API client lives in AppCore behind a protocol, defines its own error enum, and throws only
  that across its public methods. Views catch it at the boundary and show a message saying what
  the user can do.
- Every request has a timeout. Nothing blocks the main actor.
- Secrets (tokens, passwords) go in the Keychain, never in `UserDefaults`, a file or a log.

### Logging and privacy

- Log through `os.Logger` with a subsystem of the bundle identifier. Interpolated values are
  `.private` unless they are known to be harmless (counts, identifiers you generated).
- Never log a credential, a token, or the user's content.
- Using an API Apple lists as needing a "required reason" (`UserDefaults`, file timestamps, disk
  space, and others) means adding or updating `App/PrivacyInfo.xcprivacy` in the same PR.

### Formatting

```bash
swift format lint --strict --parallel --recursive \
  App AppTests AppUITests AppCore/Package.swift AppCore/Sources AppCore/Tests
```

`.swift-format` is authoritative (ADR 0010). `swift format format --in-place` with the same paths
fixes what it can.

## Testing guidelines

### Frameworks and layout

- **Swift Testing** (`import Testing`, `@Test`, `#expect`) for AppCore and the hosted app tests.
  **XCTest** only for UI tests, which Swift Testing does not drive.
- `AppCore/Tests/` mirrors `AppCore/Sources/`: `Sources/Greeting.swift` is tested by
  `Tests/GreetingTests.swift`.
- Run the smallest relevant test set while developing (`swift test --package-path AppCore --filter
  GreetingTests`), then `/dod` before opening or updating a PR. A 100% pass rate is required to
  merge.
- Tests are offline and deterministic. No real credentials and no unmocked network calls.

### Organization

- Every test file opens with a comment naming what it tests and, where relevant, the one invariant
  that matters most.
- Group tests into a `@Suite` per behavior. Give each `@Test` a display name that reads as a
  sentence about the behavior.
- A regression test's documentation comment explains the bug it guards against, so a later reader
  can tell why it exists before deciding it is safe to delete or weaken.
- Parameterize (`@Test(arguments:)`) where several inputs share one invariant.

### Faking the outside world

- Code that talks to a server, the clock, the file system or the Keychain takes it as a protocol in
  its initializer. Tests pass a fake that records what it was asked and returns canned values.
- A UI test that needs a known state launches the app with a launch argument
  (`app.launchArguments`) that the app reads in `App/` to swap in fakes. It never depends on what a
  previous test left behind.

### Test design

Prefer tests that assert observable contracts over implementation trivia: what a function returned
or threw, what it asked its dependencies to do, and what the user sees. Never wait with a fixed
sleep; use `waitForExistence(timeout:)` in UI tests and `await` an explicit signal elsewhere. Every
test fails in bounded time.

### Security-sensitive changes

Changes to authentication, credential storage, input decoding, or what data leaves the device need
targeted negative tests as well as the happy path. Fail closed on malformed input, and prove it
with a test that expects the rejection.

### Definition of done

This section is the authoritative copy. `/dod` (`.claude/commands/dod.md`) runs its commands and
checks the conditional rows against the branch's diff, `scripts/pre_release_check.py` runs the
blocking commands, and `.github/pull_request_template.md` repeats the checklist.

**Every PR:**

- [ ] `swift test --package-path AppCore --enable-code-coverage` passes at 100%, and
      `python3 scripts/check_coverage_floor.py "$(swift test --package-path AppCore --show-codecov-path)"`
      passes (the coverage ratchet).
- [ ] `swift format lint --strict` passes over the paths above, and
      `python3 -m unittest discover -s scripts/tests` passes.
- [ ] The app tests and UI tests pass on every simulator `tests.yml` runs: locally on macOS with
      `python3 scripts/pre_release_check.py`, or from the branch's `tests.yml` run.
- [ ] A user-visible change has a line under `CHANGELOG.md`'s `## [Unreleased]` heading, never
      under a concrete version heading. Internal-only changes don't need one.
- [ ] A decision that is hard to reverse, moves a trust boundary, changes the build/release/
      distribution path, or rejects a non-obvious alternative has an ADR in `docs/adr/`. A PR that
      deletes a plan document extracts that plan's decisions into ADRs first, or says in its
      description that it made none.
- [ ] New logic is in AppCore with tests; views hold layout and state only.
- [ ] Every new element a UI test touches has an accessibility identifier; every new interactive
      element has an accessibility label.
- [ ] No log line or error message carries a credential, a token or the user's content.
- [ ] Comments only where the *why* is non-obvious; no restated-*what* comments; no project
      history.
- [ ] Standing docs describe the new behavior.

**Only if the PR touches these files:**

- [ ] **`project.yml`**: `xcodegen generate` has been run and the app builds; a new target is in
      the scheme's build and test lists; a changed build setting has a comment saying why.
- [ ] **Permissions, entitlements or privacy** (a new `INFOPLIST_KEY_NS*UsageDescription`, a
      capability, `PrivacyInfo.xcprivacy`): the purpose string is written for the user, and the
      PR lists the App Store Connect privacy answers that change as a `manual_after` item.
- [ ] **A dependency in `AppCore/Package.swift`**: the change is deliberate, the version
      requirement is a bounded range, a new third-party package has an ADR, and `build.yml` has
      been dispatched against the branch.
- [ ] **`.github/workflows/`**: a workflow that must be dispatchable is already on `main`, or the
      PR says it becomes dispatchable only after merge.

## Adding a screen

1. Put any logic it needs in AppCore first, with tests (`AppCore/Tests/`).
2. Add the view in `App/`, with an `ID` enum for the identifiers UI tests use, accessibility labels,
   and a `#Preview`.
3. Add a UI test in `AppUITests/` for the path a user takes through it.
4. Add a `CHANGELOG.md` line.

## Documentation

Update standing documentation in the same PR as the behavior. Standing docs describe current
behavior, not implementation history: no phase narratives, issue numbers, version qualifiers or
"previously / after X" explanations. History belongs in `CHANGELOG.md` and the *why* in an ADR;
see [`adr/README.md`](adr/README.md) for when a plan, an ADR or a reference doc is the right home.

A new testing gap belongs in [`testing-policy.md`](testing-policy.md) if it changes current
policy, or in [`release-testing.md`](release-testing.md)'s "What stays manual" if it is a standing
open item — not in a plan document written to hold it.
