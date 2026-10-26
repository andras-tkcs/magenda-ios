# ADR 0035: Start Over is refused while a meeting of the day is sent, and Reset Hand-off unlocks the pages

## Status

Accepted — 2026-10-26. Implemented.
Amends [ADR 0026](0026-start-over-is-separate-from-render.md): Start over is refused while a meeting is sent.
Amends [ADR 0032](0032-a-sent-days-hand-off-can-be-reset-after-asking.md): a reset also forgets the date's sent meetings and unlocks their pages.

## Context

Start over deletes every page's handwriting and the added pages. A sent meeting's PDF and Doc are
already in Drive and its pages are locked ([ADR 0033](0033-a-meeting-can-be-sent-before-the-day-ends.md)),
so starting over would leave a Review row whose pages no longer exist on the device.

## Decision

1. `AgendaController.canStartOver` is false while the open binder has locked pages, and the Start
   Over button is disabled. `startOver()` refuses with a message that says to reset the hand-off
   first.
2. `HandoffController.resetHandoff(for:unlocking:)` deletes the date's day record and every part,
   and unlocks all pages of the given binder. Nothing in Drive is changed.
3. When the date has no record but the binder has locked pages, a reset only unlocks them.
   Reset Hand-off shows while the date has a record or the binder has a locked page.

## Alternatives considered

- **Starting over also forgets the sent meetings** — it would delete two kinds of data with one
  confirmation, which ADR 0032 rejected for the day too.
- **Letting Start over delete locked pages' ink** — the Review row would describe handwriting that
  is gone.

## Consequences

- To start a day over after sending a meeting, reset the hand-off first. Drive keeps the earlier
  PDF and Doc, and the routine run already started is not cancelled.

## Verification

`AppCore/Sources/Controller/AgendaController.swift`, `AppCore/Sources/Handoff/HandoffController.swift`,
`AppCore/Sources/Binder/BinderSession.swift`, `App/Screens/AgendaView.swift`,
`App/Screens/BinderView.swift`, `AppCore/Tests/Controller/AgendaControllerBinderTests.swift`,
`AppCore/Tests/Handoff/HandoffControllerTests.swift`, `AppUITests/HandoffUITests.swift`.

## Related

ADR 0026, ADR 0032, ADR 0033.
