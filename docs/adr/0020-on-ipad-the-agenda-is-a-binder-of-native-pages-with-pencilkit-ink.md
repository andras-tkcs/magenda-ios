# ADR 0020: On iPad the agenda is a binder of native pages with PencilKit ink, and the PDF is only the export

## Status

Accepted — 2026-10-22. Implemented.
Amends [ADR 0011](0011-the-agenda-pdf-is-drawn-on-device-from-the-vendored-magenda-template.md).
Amended by [ADR 0023](0023-binder-undo-uses-a-handwriting-history-kept-by-the-session.md): undo and redo use the session's handwriting history.
Amended by [ADR 0024](0024-binder-pages-turn-sideways-one-whole-page-at-a-time.md): pages turn sideways, one whole page per screen.
Amended by [ADR 0025](0025-only-added-binder-pages-can-be-deleted.md): added pages can be deleted.

## Context

Render produced a PDF, shown in a read-only `PDFView` and shared to a handwriting app. The page
plan was rebuilt on every load and its pages were addressed only by index. The user writes on the
agenda with an Apple Pencil on an iPad, so handwriting belongs inside the app, stays with the page
it was written on, and has to survive rendering the day again. Handwriting also still has to leave
the app as a PDF, since the end-of-day step shares that file. The iPhone has no Pencil.

## Decision

1. On iPad, Render opens the day's binder: each page of the render plan is drawn natively by
   `PageDrawer` (`App/Rendering/PageDrawer.swift`), with a `PKCanvasView` on top of it
   (`App/Screens/BinderPageView.swift`, `App/Screens/BinderView.swift`). Strokes are stored in page
   points, whatever size the view is.
2. `PageDrawer` draws the template's chrome page and every drawing operation except links. It is
   the one place that draws a page, both on screen and into the PDF; `PDFAgendaRenderer` draws
   each page with it, then the page's ink, then the link destinations.
3. The PDF is only the export. Share PDF composites each page's PencilKit drawing onto its page,
   imaged in the light appearance so dark mode does not turn black ink white.
4. The toolbar (`App/Screens/BinderToolbar.swift`, `AppCore/Sources/Binder/BinderTool.swift`) is
   ours, not Apple's tool picker: black, blue, red and green pens, a bitmap eraser, undo and redo,
   buttons that scroll to the overview, the delegated tasks and the notes, and Add page. Links in
   the plan are followed by a finger tap on the page.
5. Add page puts a blank copy of the current page's printed page right after it.
6. The canvas takes the Pencil only; finger drawing is switched on by the launch argument
   `-MagendaFingerDrawing`, which the UI tests use.
7. The iPhone keeps the read-only PDF preview.

## Alternatives considered

- **`PKCanvasView` over a `PDFView`, or PDF annotations.** The PDF would be regenerated under the
  ink on every render, PDFKit annotations are not PencilKit, and a page would still be addressed
  by its index.
- **Apple's tool picker.** It offers many tools the user does not use.
- **Ink on iPhone.** The app is iPad-first and the iPhone has no Pencil, so it keeps the preview.
- **Locking a day once it has ink.** Rendering again keeps the ink by page instead
  ([ADR 0021](0021-a-binder-day-is-stored-as-a-content-snapshot-and-ink-per-page-key.md)).

## Consequences

- The template page is drawn by two paths that share one drawer, so the screen and the exported PDF
  cannot drift apart.
- Handwriting is device-local PencilKit data; the shared PDF is the only copy that leaves the app.
- Real Pencil behaviour (pressure, palm rejection) cannot be tested on the simulator and stays a
  manual check ([`docs/release-testing.md`](../release-testing.md)).

## Verification

- `App/Rendering/PageDrawer.swift`, `App/Rendering/PDFAgendaRenderer.swift`,
  `App/Screens/BinderView.swift`, `App/Screens/BinderPageView.swift`,
  `App/Screens/BinderToolbar.swift`, `AppCore/Sources/Binder/BinderTool.swift`.
- `AppCore/Tests/Binder/BinderToolTests.swift`, `AppCore/Tests/Layout/RenderPlanTests.swift`,
  `AppUITests/BinderUITests.swift`.

## Related

- [ADR 0011](0011-the-agenda-pdf-is-drawn-on-device-from-the-vendored-magenda-template.md),
  [ADR 0021](0021-a-binder-day-is-stored-as-a-content-snapshot-and-ink-per-page-key.md).
