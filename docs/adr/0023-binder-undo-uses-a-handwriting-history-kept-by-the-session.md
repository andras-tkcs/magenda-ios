# ADR 0023: Binder undo and redo use a handwriting history kept by the binder session, not PencilKit's undo manager

## Status

Accepted — 2026-10-23. Implemented.
Amends [ADR 0020](0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md).
Amended by [ADR 0025](0025-only-added-binder-pages-can-be-deleted.md): deleting a page removes its history.
Amended by [ADR 0026](0026-start-over-is-separate-from-render.md): Start over begins an empty history.

## Context

The pages' canvases live in a lazy stack. PencilKit's undo actions are registered on the window's
undo manager against a canvas that is released when its page scrolls away, so Undo did nothing for
a page that was off screen.

## Decision

1. `BinderSession` keeps a binder-wide history of handwriting changes
   (`AppCore/Sources/Binder/BinderSession.swift`). Each change records the page and what it held
   before and after. `setInk` records one and clears the redo stack; at most
   `BinderSession.historyLimit` (100) are kept, the oldest forgotten.
2. `undo()` and `redo()` write the page's earlier or later handwriting through the same save as
   `setInk`, move the change to the other stack, and return the page's key. A failed save sets the
   same message as `setInk`; the stacks still move. `canUndo` and `canRedo` are observed, so the
   toolbar dims Undo and Redo when there is nothing to do.
3. Adding a page and rendering the day again do not touch the history. A render updates the same
   session, so the history survives it; a new day gets a new session and an empty history.
4. `BinderView` scrolls to the page an undo or redo changed, unless it is already the visible page
   or is not shown. The canvases are no longer registered anywhere.

## Alternatives considered

- **PencilKit's undo manager** — it belongs to the window, its actions act on a canvas that the
  lazy stack releases when the page scrolls away, and it cannot be tested on Linux.
- **Only dimming the buttons when the edited page is off screen** — Undo would still lose the
  change.

## Consequences

- Undo reaches every page of the open day and survives a render, but not a day switch or a
  relaunch.
- At most 100 changes can be undone.
- Add page is not undoable.
- iPadOS's own undo gestures and ⌘Z still reach PencilKit's undo manager for an on-screen canvas,
  and a change they make is recorded in the history like any other stroke.
- Undo can restore ink on a page a render has since dropped (written, then fully erased before the
  render), in which case Undo does not scroll and the ink stays in the store unshown until a later
  render retains it.

## Verification

`AppCore/Sources/Binder/BinderSession.swift`, `App/Screens/BinderView.swift`,
`App/Screens/BinderToolbar.swift`, `App/Screens/BinderPageView.swift`,
`AppCore/Tests/Binder/BinderSessionTests.swift`, `AppUITests/BinderUITests.swift`.

## Related

https://github.com/andras-tkcs/magenda-ios/pull/7, ADR 0020, ADR 0021.
