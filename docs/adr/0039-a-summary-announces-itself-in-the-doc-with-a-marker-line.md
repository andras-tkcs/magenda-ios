# ADR 0039: A summary announces itself in the Doc with a marker line, and Approve summaries closes the day

## Status

Accepted — 2026-10-26. Implemented.
Amends [ADR 0029](0029-the-days-google-doc-is-the-review-record.md): decisions 1 to 4.

## Context

[ADR 0029](0029-the-days-google-doc-is-the-review-record.md) let the one routine set the Doc's first
line to `Status: Summary ready for review`. With a summary routine per kind of summary
([ADR 0038](0038-summaries-are-written-by-dedicated-summary-routines-that-magenda-starts.md)) several
routines write into one Doc, and none of them owns its status line. Magenda has no server, so a
routine cannot call it back.

## Decision

1. The Doc's first line stays the end-of-day routine's alone, and `Status: Summary ready for review`
   is no longer a status. The statuses are `Waiting for notes`, `Notes ready for review` and
   `Closed`; any other first line reads as unknown.
2. A summary routine appends its summary to the Doc as a section whose first line is the marker
   `Summary ready: <routine ID> <page>`: the routine ID from its payload and the meeting's page
   number. The label and the ID may be in any letter case; the line is otherwise exact, the page is
   1 to 9999 and the ID a UUID. Magenda reads every line of the Doc except the first non-empty one
   and keeps those that are markers. A line that only resembles a marker is ignored.
3. A summary is written when every meeting a routine was asked for has its marker. When all of
   them are, the Review row says `Summaries ready for review` and offers Approve summaries, which
   starts the end-of-day routine's `close` step. Until then the row says `Claude is writing the
   summaries` and offers nothing.
4. Approve notes saves its state before it starts the summary routines. If some could not be
   started the row says `Notes approved. Summaries not yet sent to Claude` and offers Try again.
5. A record saved by an earlier build in a state that already started the old closing steps loads
   as closing, and closes when the Doc's first line says `Closed`.

## Alternatives considered

- **Several routines setting one status line** — a race, and a routine writing a status it does
  not own.
- **A Doc per summary** — Magenda would create and track more files.
- **A callback to the app** — the app has no server.

## Consequences

- Two routines finishing together may interleave their sections. Each appends its section in one
  edit and Magenda matches marker lines only, so this costs readability, not state.
- If the person deletes a marker while editing the Doc, the row stays at `Claude is writing the
  summaries`, and only Reset Hand-off ([ADR 0032](0032-a-sent-days-hand-off-can-be-reset-after-asking.md))
  sends the day again. A routine that is started but never writes its marker leaves the row the same way.

## Verification

`AppCore/Sources/Handoff/DocStatus.swift` (`summaryMarkers(in:)`), `AppCore/Sources/Handoff/DayHandoff.swift`
(`summariesWritten`, `phase`), `AppCore/Sources/Handoff/HandoffController.swift`,
`AppCore/Sources/Handoff/HandoffFixtures.swift`, `AppCore/Tests/Handoff/DocStatusTests.swift`,
`AppCore/Tests/Handoff/DayHandoffTests.swift`, `AppCore/Tests/Handoff/HandoffControllerTests.swift`,
`AppUITests/HandoffUITests.swift`.

## Related

[ADR 0029](0029-the-days-google-doc-is-the-review-record.md),
[ADR 0038](0038-summaries-are-written-by-dedicated-summary-routines-that-magenda-starts.md),
[ADR 0040](0040-the-routine-payload-moves-to-schema-3-and-summaries-have-their-own-schema.md),
[`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
