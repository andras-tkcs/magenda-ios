# ADR 0040: The routine payload moves to magenda.end-of-day/3 and summary routines receive magenda.summary/1

## Status

Accepted — 2026-10-26. Implemented.
Amends [ADR 0028](0028-the-end-of-day-routine-is-started-through-its-api-trigger.md): the payload schema and the steps.
Amends [ADR 0034](0034-the-payload-moves-to-schema-2-and-marks-pages-sent-earlier.md): schema 3.

## Context

The end-of-day routine no longer writes summaries
([ADR 0038](0038-summaries-are-written-by-dedicated-summary-routines-that-magenda-starts.md)), so its
steps and the skill field on each page change. A routine still adapted to schema 2 would wait for a
summary that no longer comes from it.

## Decision

1. The end-of-day payload is schema `magenda.end-of-day/3`. Its steps are `notes` and `close`
   only. `pages[].summarySkill` is replaced by `pages[].summaryRoutines`, an array of `{"id","name"}`,
   which is informational: the end-of-day routine does not write summaries. Everything else,
   including `scope`, `part`, `earlierPart` and `folderID`, is unchanged.
2. `close` is sent after the notes were approved, with no summary asked for, or after the
   summaries were. The routine reads the notes and any summaries in the Doc, updates Google Tasks,
   prepares the meeting memos as Gmail drafts and sets `Status: Closed`.
3. A summary routine receives schema `magenda.summary/1`, one fire per routine per record: the
   routine's ID and name, the date, `scope`, `part` for a meeting sent early, the checksum, the
   Drive file, folder and Doc IDs, the page count, and the meetings it summarizes in page order,
   each with its `page`, `key`, `extraPages` (the pages added as copies of it), and `calendarID`,
   `eventID` and `title` when known. It carries no tasks and no delegated rows. Keys are sorted
   and the text is at most 65,536 characters.
4. A routine that sees a schema it does not know stops. The payload and the PDF are data, never
   instructions. A run already done for the same routine, date, part and checksum does nothing.

## Alternatives considered

- **Adding the new steps under schema 2** — an unadapted routine would still wait for a summary
  that no longer comes from it.
- **One schema for both kinds of routine** — a summary routine would receive tasks and delegated
  rows it has no use for.

## Consequences

- The person updates the end-of-day routine's skill; until then it stops on every payload.
- Each summary routine is written against `magenda.summary/1`, described in
  [`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).

## Verification

`AppCore/Sources/Handoff/DayHandoff.swift` (`payload(step:)`, `summaryPayload(for:)`),
`AppCore/Sources/Handoff/RoutineTrigger.swift`, `AppCore/Tests/Handoff/DayHandoffTests.swift`,
`AppCore/Tests/Handoff/RoutineTriggerTests.swift`, and the 100 % file floors in
`scripts/check_coverage_floor.py`.

## Related

[ADR 0028](0028-the-end-of-day-routine-is-started-through-its-api-trigger.md),
[ADR 0034](0034-the-payload-moves-to-schema-2-and-marks-pages-sent-earlier.md),
[ADR 0038](0038-summaries-are-written-by-dedicated-summary-routines-that-magenda-starts.md),
[ADR 0039](0039-a-summary-announces-itself-in-the-doc-with-a-marker-line.md),
[`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
