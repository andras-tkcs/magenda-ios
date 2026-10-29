# ADR 0050: A summary routine can have a page of its own at the end of the binder

## Status

Accepted — 2026-10-29. Implemented.
Extends [ADR 0038](0038-summaries-are-written-by-dedicated-summary-routines-that-magenda-starts.md): decision 2 (a meeting asks for a summary) gains a second way in.

## Context

Some summaries belong to no meeting. A weekly project update, for example, gets a line on any day
of the week, from any conversation. Asking for it by ticking a meeting means picking a meeting it
has nothing to do with, and a day on which nothing was written must not start the routine.

## Decision

1. A summary routine has a setting, **Own page** (`SummaryRoutine.hasPage`, off by default), in
   Settings → Summary routines.
2. A routine with it on adds one page to every day's binder, after the further-notes page and in the
   order the routines were added. The page has the further-notes chrome and is titled with the
   routine's name. Its key is `routine:<routine ID>`. The page is part of the content snapshot
   (`AgendaContent.routinePages`), so a day keeps the names it was rendered with.
3. When the day is finished, the page asks for its routine only if the page, or a page added as a
   copy of it, carries handwriting. Otherwise the page is sent like any other, nothing asks for the
   routine, and the routine is not started. Nothing else changes: Approve notes starts the routine
   once, with the page in `meetings` (its `key` is `routine:<id>`, `title` the routine's name),
   and the routine writes the usual marker for that page.
4. Switching the setting off removes the page from days not yet written on. A page that already has
   handwriting stays, as any page switched off after handwriting does, and still starts its routine.
5. Each day has its own page. Nothing carries over from one day to the next: the person writes on
   the page of the day the thing happened, and every day with writing starts the routine.

## Alternatives considered

- **One page for the whole week** — the binder is a set of independent days; a page that lives
  across days would need its own storage, locking and deletion rules.
- **Using the further-notes page** — it is shared by every routine and the end-of-day notes, so
  nothing says which routine its handwriting is for.
- **Starting the routine every day and letting it find the page empty** — a routine run costs
  money and a session each time, and the person asked for it only when something was written.

## Consequences

- Every day's PDF has one more page per routine with a page of its own.
- `SummaryRoutine` carries `hasPage` in its settings and content snapshots, and in payloads only
  when true.
- A routine forgotten after a day was sent keeps failing for that day as before (ADR 0038).

## Verification

`AppCore/Sources/Settings/SummaryRoutine.swift`, `AppCore/Sources/Layout/PageKey.swift`,
`AppCore/Sources/Layout/AgendaLayout.swift`, `AppCore/Sources/Draft/AgendaDraft.swift`,
`AppCore/Sources/Handoff/DayHandoff.swift`, `AppCore/Sources/Handoff/HandoffController.swift`,
`App/Screens/SettingsView.swift`, and their tests under `AppCore/Tests/`.

## Related

[ADR 0038](0038-summaries-are-written-by-dedicated-summary-routines-that-magenda-starts.md),
[`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
