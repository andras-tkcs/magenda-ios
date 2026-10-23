# ADR 0011: The agenda PDF is drawn on the device from the Python Magenda's compiled template

## Status

Accepted — 2026-10-15. Implemented.
Amended by [ADR 0020](0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md): the template page is drawn by `PageDrawer`.

## Context

The agenda has to look like the page the Python [Magenda](https://github.com/andras-tkcs/magenda)
produces from its Word template: the same shaded bands, grid, checkboxes and delegated table, in
the same places, so a binder built by the app is interchangeable with one built by the workflow it
replaces. Python Magenda compiles that template into two artifacts: `assets/compiled/chrome.pdf`
(four blank A4 page shells with no themable text) and `assets/compiled/slots.json` (the rectangle,
role, weight, size and alignment of every piece of text), plus 15 SIL OFL fonts (three packs of
five weights).

The agenda is read from the user's own Google data, so rendering it on a server would send that
data off the device and fail offline.

## Decision

1. The PDF is rendered on the device. `App/Rendering/PDFAgendaRenderer.swift` draws a page of
   `chrome.pdf` as the background of each output page and then executes a `RenderPlan` of fills,
   strokes, text runs and links on top (ADR 0012).
2. `App/Resources/Template/chrome.pdf`, `AppCore/Sources/Resources/slots.json` and the 15 TTFs under
   `App/Resources/Fonts/` (with their OFL texts) are byte copies of the Python repository's files at
   commit `3c15fc11fcbcf47bb9907e3a761e6c57d04cd2bd`. `chrome.pdf` has SHA-256
   `b2e7eb2aafeed0c17db5f33fe1b8f900d5866194989d890035e458770edabfe3`; `slots.json` has
   `ff9ed22ec6aece4d2f0daf764f0a8bd2a1507c813aa0fa5363afee8a9aa902bb`.
3. Updating the template means copying both files again from a newer commit of that repository,
   together, and updating the hashes and commit here in a new ADR. Neither file is edited by hand.
4. Fonts are loaded from the bundle as descriptors and never registered system-wide.

## Alternatives considered

- **Render on a server with the Python Magenda.** Needs hosting, sends the user's calendar off the
  device, and fails offline.
- **Redraw the template natively in SwiftUI or CoreGraphics.** Hundreds of hand-copied coordinates
  that drift from the Word template. Vendoring the exact artifacts the Python runtime uses means
  only the parts that change are redrawn.

## Consequences

- The app's pages match the Python output wherever the content is the same.
- The repository carries a binary PDF and 15 font files; the fonts' licence texts ship with them.
- The template can only change by replacing both artifacts; text positions never live in Swift
  except for the few regions the layout redraws (the to-do grid and the delegated table).

## Verification

`AppCore/Tests/Layout/TemplateManifestTests.swift` loads `slots.json`; `AppTests/RenderingTests.swift`
renders pages from the bundled `chrome.pdf` with the real fonts; `App/Resources/`.

## Related

ADR 0007 (logic in AppCore, drawing in `App/`); ADR 0012 (the layout the template is filled by);
https://github.com/andras-tkcs/magenda at the commit above.
