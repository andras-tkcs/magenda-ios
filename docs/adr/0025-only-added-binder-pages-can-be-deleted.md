# ADR 0025: Only pages added in the binder can be deleted, with their handwriting and undo history, after a confirmation

## Status

Accepted — 2026-10-23. Implemented.
Amends [ADR 0020](0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md).
Amends [ADR 0023](0023-binder-undo-uses-a-handwriting-history-kept-by-the-session.md).

## Context

Add page puts a blank copy of a page after it, and a page added by mistake stayed for good. The
binder's other pages are derived from Google Calendar and Google Tasks on every render, and the
history of ADR 0023 only ever grew.

## Decision

1. The toolbar has a Delete page button. It is enabled only while the page on screen is one the
   person added (`BinderSession.canDelete`), and tapping it asks "Delete this page?" first.
2. Confirming calls `BinderSession.deletePage`: the added page is removed from the day
   (`BinderDay.removePage(id:)`; pages that followed it follow the page it followed), the day is
   re-planned and saved, its handwriting is removed from the store, and the page before it is shown.
3. The page's changes are removed from the undo and redo stacks, so Undo never writes handwriting
   back for a page that no longer exists, and `canUndo` and `canRedo` stay truthful. The history of
   the other pages is kept.
4. A failed save leaves a message, "Couldn't delete the page. Free some space on this device."

## Alternatives considered

- **Deleting any page** — the overview, delegated, meeting and notes pages come from Google
  Calendar and Tasks and would come back on the next Render, or need a stored list of hidden pages
  and a change to the stored day's format.
- **Keeping the history of a deleted page** — Undo would resurrect ink for a page that is not
  there.

## Consequences

- Deleting a page cannot be undone, which is why it asks first.
- An added copy of a meeting page is titled "cont. <meeting title>" (just "cont." when the
  meeting has no title). That is computed when the page is laid out, from the copied page's own
  meeting, so neither adding nor deleting pages changes the stored format: `BinderDay` still
  stores only the added page's id, its place and its source.
- The undo history no longer only grows: deleting a page trims it.

## Verification

`AppCore/Sources/Binder/BinderDay.swift`, `AppCore/Sources/Binder/BinderSession.swift`,
`AppCore/Sources/Binder/BinderLayout.swift`, `AppCore/Sources/Layout/AgendaLayout.swift`,
`App/Screens/BinderView.swift`, `App/Screens/BinderToolbar.swift`,
`AppCore/Tests/Binder/BinderDayTests.swift`, `AppCore/Tests/Binder/BinderSessionTests.swift`,
`AppCore/Tests/Binder/BinderLayoutTests.swift`, `AppCore/Tests/Layout/AgendaLayoutTests.swift`,
`AppUITests/BinderUITests.swift`.

## Related

ADR 0020, ADR 0023.
