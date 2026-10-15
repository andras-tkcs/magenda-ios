# ADR 0015: AppCore may import the toolchain's Observation module

## Status

Accepted — 2026-10-15. Implemented.
Amends ADR 0007.

## Context

ADR 0007 says AppCore depends on Foundation at most, so that it builds and tests on Linux. The
screen state (`AgendaController`) is observable state that SwiftUI views read. Keeping it in `App/`
leaves the controller — which sequences loading, drafting, editing and rendering — untested on
Linux. `Observation` ships with the Swift toolchain on Linux, so importing it costs nothing ADR
0007 protects.

## Decision

AppCore may import `Foundation` and `Observation`, and nothing else from the platform. The
`@Observable` `AgendaController` lives in `AppCore/Sources/Controller/` and is tested with `swift
test`. The rest of ADR 0007 stands: no SwiftUI, UIKit, Combine or other Apple-only framework in
AppCore.

## Alternatives considered

- **Keep the controller in `App/`.** Its logic would only be testable through UI tests on a
  simulator.
- **A hand-written observer.** More code to test, and the views would not use the framework
  mechanism.

## Consequences

- The controller's behavior is covered by the 100% AppCore ratchet.
- The Observation import must keep building on Linux; if a toolchain stops shipping it, this ADR is
  revisited.

## Verification

`AppCore/Package.swift` (comment); `AppCore/Sources/Controller/AgendaController.swift`;
`AppCore/Tests/Controller/`; `docs/coding-and-testing-guidelines.md`, "Where code goes".

## Related

ADR 0007.
