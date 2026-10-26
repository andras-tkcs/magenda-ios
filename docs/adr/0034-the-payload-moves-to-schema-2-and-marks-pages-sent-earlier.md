# ADR 0034: The routine payload moves to magenda.end-of-day/2 and marks the pages of meetings sent earlier

## Status

Accepted — 2026-10-26. Implemented.
Amends [ADR 0028](0028-the-end-of-day-routine-is-started-through-its-api-trigger.md): the payload schema.
Amended by [ADR 0040](0040-the-routine-payload-moves-to-schema-3-and-summaries-have-their-own-schema.md): schema 3.

## Context

Once a meeting can be sent before the day ends ([ADR 0033](0033-a-meeting-can-be-sent-before-the-day-ends.md)),
the routine gets two kinds of run: a meeting's and a day's. The day's PDF still holds the meeting's
pages, and processing them again would write the meeting's notes, summary, memo and task updates
twice.

## Decision

1. `Payload.schema` is `magenda.end-of-day/2`. The routine contract says a routine that sees
   another value stops, so a routine not yet adapted stops instead of processing a meeting twice.
2. `scope` is always present: `day` or `meeting`. A meeting run adds `part`, the part number, and
   has no `tasks` or `delegated`; its `pages` and `pageCount` describe its own PDF.
3. In a day run, a page already sent in a meeting carries `earlierPart`, that part's number, and
   the routine skips it.
4. The day's PDF keeps the meetings sent earlier. When the payload is cut down to fit, `earlierPart`
   is kept, because a routine that loses it would process the page twice.

## Alternatives considered

- **Leaving the sent meetings out of the day's PDF** — the day's PDF would be incomplete, and the
  person chose a complete day PDF.
- **Adding the keys under schema 1** — an old routine would ignore the mark and process the
  meeting twice.

## Consequences

- The routine's skill must be updated; until then it stops on every payload, the day's too.
- A payload queued before the update is built when it is fired, so it is sent as schema 2.

## Verification

`AppCore/Sources/Handoff/DayHandoff.swift`, `AppCore/Sources/Handoff/HandoffFixtures.swift`,
`AppCore/Tests/Handoff/DayHandoffTests.swift`, `AppCore/Tests/Handoff/HandoffFixturesTests.swift`,
`AppCore/Tests/Handoff/HandoffControllerTests.swift`.

## Related

ADR 0028, ADR 0033, [`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
