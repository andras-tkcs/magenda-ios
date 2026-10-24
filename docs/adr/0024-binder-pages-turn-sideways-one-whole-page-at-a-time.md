# ADR 0024: The binder shows one whole page per screen and pages turn with a horizontal swipe

## Status

Accepted — 2026-10-23. Implemented.
Amends [ADR 0020](0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md).

## Context

The binder was a vertical scroll of pages, each fitted to the screen's width. A page is A4
portrait, so fitted to the width it is taller than an iPad screen held in portrait: a page was cut
off, and a jump to the overview, the delegated tasks or the notes, or Add page, could leave the
bottom of the page off screen. The person wants to see a page whole and turn it like a sheet in a
binder.

## Decision

1. The binder is a horizontal paging scroll view (`ScrollView(.horizontal)` over a `LazyHStack`,
   `.scrollTargetBehavior(.paging)`, `.scrollPosition(id:)`). Each page is fitted whole to the
   room the bars leave (`containerRelativeFrame`), and one swipe moves one page. The pages stay
   lazy, so a canvas exists only for pages near the one on screen.
2. The toolbar, the omitted-tasks banner, the message line and the page indicator are stacked in a
   `VStack` around the paging scroll view, not laid over it. A page is therefore fitted to the room
   they leave, and the whole of that room is swipeable.
3. The jump buttons and Add page set the scroll position to a page key, so they show the page whole
   from its top. Undo and Redo go to the page they change the same way.
4. The page is never scrolled inside: there is no vertical scrolling at all.

## Alternatives considered

- **Vertical scrolling with the page fitted to the width** — a page taller than the screen is cut,
  and a jump can leave its bottom off screen.
- **Fit to the width with vertical scrolling inside a page** — the person chose whole pages.
- **The bars as `safeAreaInset`s over the scroll view** — a tall omitted-tasks banner then covered
  the top of the first page and swallowed the swipe that should turn it, so the bars are stacked
  around the scroll view instead.

## Consequences

- A finger swipe turns pages, so the canvas takes only the Pencil for drawing (it already does
  unless finger drawing is switched on for tests), and tests that draw with a finger draw a
  vertical stroke so it does not compete with the page swipe.
- A page is smaller than the width of the screen when the screen is short; there is no zooming.
- The page indicator reads the page on screen from the scroll position.

## Verification

`App/Screens/BinderView.swift`, `App/Screens/BinderToolbar.swift`, `AppUITests/BinderUITests.swift`
(`testAFingerSwipesToTheNextPage`, `testAPageIsShownWhole`,
`testNotesAndOverviewButtonsMoveBetweenPages`).

## Related

ADR 0020.
