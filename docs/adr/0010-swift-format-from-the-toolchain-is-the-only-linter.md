# ADR 0010: `swift format` from the toolchain is the only formatter and linter

## Status

Accepted — 2026-10-01. Inherited from the iOS app template.

## Context

Formatting arguments in review are noise, and a style rule only holds if a check enforces it. The
check has to run in every place code is written, including a Linux cloud session and the Linux CI
jobs (ADR 0007), and its version has to be the one everyone has.

## Decision

1. `swift format lint --strict` over the app, test and AppCore sources blocks CI (`tests.yml`'s
   `lint`), with `.swift-format` as its configuration: four-space indentation, 100-column lines,
   documentation on every public declaration, no force unwraps or `try!`.
2. The compiler's own warnings are errors in the app target (`SWIFT_TREAT_WARNINGS_AS_ERRORS`), and
   Swift 6 language mode makes data races compile errors.
3. No other linter is added without a new ADR.

## Alternatives considered

- **SwiftLint.** More rules, but a separate tool with its own release cycle to install everywhere,
  including on Linux, and much of its value overlaps with `swift format` and the Swift 6 compiler.
- **SwiftFormat (Nick Lockwood's).** Same objection: one more tool to install and pin, when the
  toolchain already ships a formatter.

## Consequences

- The formatter's version is the toolchain's: a new Xcode or Swift release can change the output,
  and the fix is to run `swift format format --in-place` in the PR that moves CI to it.
- Rules `swift format` does not have are review conventions, written in
  `docs/coding-and-testing-guidelines.md`.

## Verification

`.swift-format`; `.github/workflows/tests.yml` (`lint`); `project.yml`
(`SWIFT_TREAT_WARNINGS_AS_ERRORS`, `SWIFT_VERSION`).
