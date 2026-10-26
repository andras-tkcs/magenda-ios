# ADR 0030: A closed day's handwriting is deleted from the device five days after Magenda first reads Closed

## Status

Accepted — 2026-10-24. Implemented.
Amends [ADR 0021](0021-a-binder-day-is-stored-as-a-content-snapshot-and-ink-per-page-key.md): "nothing deletes a stored day".
Amended by [ADR 0033](0033-a-meeting-can-be-sent-before-the-day-ends.md): only a finished day starts the deletion.

## Context

Every started day kept its content snapshot and ink forever. Once the routine has closed a day, its
handwriting is in the PDF in Drive and its content is in the Doc, so the local copy only takes
space and keeps private notes on the device. The routine might also be corrected right after it
closes, so deleting at once would be too early.

## Decision

1. Magenda records the day it first reads `Status: Closed` for a finished day (`closedOn`).
2. On a refresh, once `closedOn` plus five days is on or before today, Magenda deletes the binder
   day and all its ink (`BinderStore.deleteDay`) and the local copy of the PDF, then marks the
   record purged. A failure leaves the day for the next refresh.
3. The day that is open in the binder is never purged.
4. The small hand-off record (`handoff.json`) stays. It keeps Finish Day disabled for that date
   and shows the day in the Review list as "Closed. Handwriting deleted."
5. Nothing in Drive is deleted: the PDF and the Doc stay.
6. `deleteDay` removes the day's folder and succeeds when nothing is stored.

## Alternatives considered

- **Deleting the whole hand-off record at purge** — the day could then be finished, uploaded and
  sent again, creating a second Doc. Only the files go.
- **Deleting when the Doc closes** — leaves no time to notice a mistake in the closing step.
- **Never deleting** — keeps handwriting on the device with no use, which grows without limit.

## Consequences

- Deleted handwriting cannot be recovered on the device; the PDF in Drive is the copy.
- A closed day older than five days cannot be opened in the binder, though it can be rendered from
  Google again as a fresh day.
- Purging runs only when the app refreshes, so a device that is not opened keeps the files longer.

## Verification

`AppCore/Sources/Binder/BinderStore.swift` (`deleteDay`), `AppCore/Sources/Handoff/HandoffController.swift`,
`AppCore/Sources/Handoff/HandoffStore.swift`, `AppCore/Tests/Binder/BinderStoreTests.swift`,
`AppCore/Tests/Handoff/HandoffControllerTests.swift`, `AppCore/Tests/Handoff/HandoffStoreTests.swift`,
`AppUITests/HandoffUITests.swift`.

## Related

[ADR 0021](0021-a-binder-day-is-stored-as-a-content-snapshot-and-ink-per-page-key.md),
[ADR 0029](0029-the-days-google-doc-is-the-review-record.md).
