# ADR 0032: A day's hand-off can be reset after asking, so a day can be finished and sent again

## Status

Accepted — 2026-10-25. Implemented.
Amends [ADR 0028](0028-the-end-of-day-routine-is-started-through-its-api-trigger.md): a sent day can be sent again.
Amends [ADR 0030](0030-a-closed-days-handwriting-is-deleted-five-days-later.md): the record that keeps Finish Day disabled can be deleted.

## Context

Once a day's routine has been fired, Finish Day stays disabled for that date for good, and Start
over (ADR 0026) does not touch the hand-off. A day used to try the hand-off out could not be
finished again, so every try used up a real day.

## Decision

1. In the binder, once the open day has a hand-off, the toolbar has a Reset Hand-off button. It
   asks "Reset this day's hand-off?" and says what stays in Drive.
2. Confirming calls `HandoffController.resetHandoff(for:)`, which deletes the day's folder in the
   hand-off store (`handoff.json` and `day.pdf`) and removes the day from the Review list. Finish
   Day works again for that date.
3. Nothing in Drive is changed. The next finish uploads a new PDF and creates a new Doc, since the
   stored file and Doc IDs are gone. The old ones stay, and the routine run already started is not
   cancelled.
4. The binder, its handwriting and the added pages are not touched. Start over stays a separate
   action.
5. A reset is ignored while a finish, refresh or action is running. If the delete fails, the
   hand-off stays and a message says so.

## Alternatives considered

- **Resetting from Start over** — it would delete handwriting and the hand-off together, but a
  person may want only one of them.
- **Keeping the Drive file and Doc IDs so the next finish replaces them** — the old Doc would keep
  its closing status and the routine's earlier notes.
- **Deleting the Drive files too** — `drive.file` could delete what Magenda created, but a
  destructive remote action is not needed to try the hand-off again.

## Consequences

- A day that was really sent can be sent twice, and Drive then holds two Docs for it with the
  same name. The routine's idempotency rule (same date, step and checksum does nothing) still
  holds only for an unchanged PDF.
- A purged day's record can be reset too, but its binder is gone, so there is nothing to finish.

## Verification

`AppCore/Sources/Handoff/HandoffController.swift`, `AppCore/Sources/Handoff/HandoffStore.swift`,
`App/Screens/BinderView.swift`, `AppCore/Tests/Handoff/HandoffControllerTests.swift`,
`AppCore/Tests/Handoff/HandoffStoreTests.swift`, `AppUITests/HandoffUITests.swift`.

## Related

ADR 0026, ADR 0028, ADR 0030, [`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
