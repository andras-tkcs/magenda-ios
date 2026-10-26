# ADR 0033: A meeting can be sent to the routine before the day ends, as its own PDF and Doc, and its pages are locked afterwards

## Status

Accepted — 2026-10-26. Implemented.
Amends [ADR 0027](0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md): a meeting sent early is a separate PDF with its own name.
Amends [ADR 0029](0029-the-days-google-doc-is-the-review-record.md): there is a Doc per day and per sent meeting.
Amends [ADR 0030](0030-a-closed-days-handwriting-is-deleted-five-days-later.md): only a finished day starts the five-day deletion.

## Context

A meeting's notes and summary are sometimes needed before the day ends, but the hand-off only
started when the whole day was finished. Handwriting added to a meeting page after sending it would
be missing from what the routine read, so the sent pages must stop changing.

## Decision

1. On a meeting page in the binder, Send Meeting renders only that meeting's pages (the meeting
   page and the pages added as copies of it) into their own PDF, creates their own Google Doc and
   starts the routine's `notes` step for them. A page with no calendar event, and the overview,
   delegated and notes pages, have no meeting to send.
2. A sent meeting is a part of the date: record `part-<n>.json` and `part-<n>.pdf` beside the
   day's own, named `Magenda <date> part <n>.pdf` and `Magenda <date> part <n> notes` in Drive.
   Titles stay out of Drive names.
3. A part goes through the same review loop as a day, in its own row of the Review list, and ends
   as Closed.
4. The pages are locked as soon as the send begins and stay locked: the lock is stored with the
   binder day, so it survives a relaunch, a render and a day switch. A failure before the record is
   saved unlocks them again.
5. Send Meeting is refused once the day itself was finished.
6. Only a finished day starts the five-day deletion. When it runs, it also deletes the PDFs of that
   date's parts. A date whose meetings were sent but whose day was never finished is not purged.
7. Rendering again keeps a locked page even without ink.

## Alternatives considered

- **Keeping the lock only in the hand-off records and having views ask the hand-off controller** —
  the agenda controller builds binder sessions and rebases them without knowing the hand-off
  controller, so the lock would have to be pushed into every new session from a view.
- **Leaving the pages writable** — later handwriting would never reach the routine.
- **Sending a meeting inside the day's Doc** — one Doc could not follow two review loops.

## Consequences

- Locking drops the sent pages' undo and redo history ([ADR 0023](0023-binder-undo-uses-a-handwriting-history-kept-by-the-session.md)).
- A locked page that was added cannot be deleted ([ADR 0025](0025-only-added-binder-pages-can-be-deleted.md)), and no page can be added after one.
- A locked page whose meeting is still in the content is laid out from the new content; what was
  sent is the PDF already in Drive.
- A date with only sent meetings keeps its handwriting on the device until the person resets it or
  finishes the day.

## Verification

`AppCore/Sources/Handoff/DayHandoff.swift`, `AppCore/Sources/Handoff/HandoffController.swift`,
`AppCore/Sources/Handoff/HandoffStore.swift`, `AppCore/Sources/Binder/BinderDay.swift`,
`AppCore/Sources/Binder/BinderSession.swift`, `AppCore/Sources/Binder/BinderLayout.swift`,
`AppCore/Sources/Layout/RenderPlan.swift`, `App/Screens/BinderView.swift`,
`AppCore/Tests/Handoff/HandoffControllerTests.swift`, `AppCore/Tests/Handoff/DayHandoffTests.swift`,
`AppCore/Tests/Handoff/HandoffStoreTests.swift`, `AppCore/Tests/Binder/BinderSessionTests.swift`,
`AppUITests/HandoffUITests.swift`.

## Related

ADR 0023, ADR 0025, ADR 0027, ADR 0029, ADR 0030, [ADR 0034](0034-the-payload-moves-to-schema-2-and-marks-pages-sent-earlier.md),
[`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
