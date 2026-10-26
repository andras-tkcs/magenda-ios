# ADR 0029: The day's Google Doc is the review record, and approve buttons start the routine's next step

## Status

Accepted — 2026-10-24. Implemented.
Amended by [ADR 0033](0033-a-meeting-can-be-sent-before-the-day-ends.md): a Doc per day and per sent meeting.
Amended by [ADR 0039](0039-a-summary-announces-itself-in-the-doc-with-a-marker-line.md): summaries are announced by markers.

## Context

After a day is sent, the routine writes notes, may write a summary and then closes the day. The
person reviews each result and corrects it. The review needs a place to read and edit the text, and
Magenda needs to know how far the day has come without keeping that text itself.

## Decision

1. Magenda creates the day's Google Doc when it uploads the PDF, with the single first line
   `Status: Waiting for notes`. The routine owns the Doc from then on and keeps its first line to
   one of `Status: Waiting for notes`, `Status: Notes ready for review`,
   `Status: Summary ready for review` and `Status: Closed`.
2. Magenda reads only that first line, with Drive's plain-text export, when the app becomes active,
   when the Review list opens or is pulled to refresh, and once after an approve. Any other first
   line reads as unknown and offers nothing. The notes themselves stay in the Doc.
3. A Review list shows every finished day with its state, a link that opens the Doc, and the one
   button the state calls for: Try again for a day that is not yet uploaded or sent, Approve notes
   for `Notes ready for review`, Approve for `Summary ready for review`. A day in any other state
   has no button.
4. An approve button fires the routine's next step ([ADR 0028](0028-the-end-of-day-routine-is-started-through-its-api-trigger.md))
   and moves the day on only when the fire succeeded.
5. Finish Day is refused once notes were requested, so a day has one PDF and one Doc for the routine
   to reconcile. Before that, finishing again replaces the PDF in place and keeps the Doc.
6. Only a day that is waiting to upload is uploaded by a refresh. A day that is uploaded but not
   sent waits for Try again, so a refresh never fires.

## Alternatives considered

- **Re-finishing a day after it was sent** — the Doc would still show the earlier notes' status and
  the routine would have to reconcile two PDFs.
- **Keeping the notes in the app** — a second editor for text the person already edits well in a
  Doc, and a copy that can disagree with it.
- **A per-day record in a database or in the Doc's properties** — the status line is visible, can
  be fixed by hand, and needs no extra scope.

## Consequences

- A person who edits the first line by hand changes what Magenda offers. A wrong line reads as
  unknown, which offers nothing and stops nothing else.
- The Doc is the only place the notes live; deleting it in Drive leaves the Review row with a
  "couldn't find that file" message.
- Magenda needs network access to see a status change, and shows the last status it read without it.

## Verification

`AppCore/Sources/Handoff/DocStatus.swift`, `AppCore/Sources/Handoff/DayHandoff.swift` (`phase`),
`AppCore/Sources/Handoff/HandoffController.swift`, `AppCore/Sources/Handoff/HandoffFixtures.swift`,
`App/Screens/ReviewView.swift`, `App/Screens/BinderView.swift`, `AppCore/Tests/Handoff/DocStatusTests.swift`,
`AppCore/Tests/Handoff/DayHandoffTests.swift`, `AppCore/Tests/Handoff/HandoffControllerTests.swift`,
`AppUITests/HandoffUITests.swift`.

## Related

[ADR 0027](0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md),
[ADR 0028](0028-the-end-of-day-routine-is-started-through-its-api-trigger.md),
[ADR 0030](0030-a-closed-days-handwriting-is-deleted-five-days-later.md),
[`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
