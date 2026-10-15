# ADR 0012: Text layout is computed in AppCore against a measuring protocol and audited

## Status

Accepted — 2026-10-15. Implemented.

## Context

Event titles and task names are arbitrary text: a 200-character word, emoji, CJK or Arabic text,
embedded newlines. The Python Magenda fits text with rules that break on these inputs: it wraps
only at spaces (a long word runs into the next column), cuts single-line text with no ellipsis,
raises when to-dos need more than 18 rows, and finds the to-do grid at render time by querying
the chrome's drawings and leaves stray strokes. Platform text frameworks (CoreText, TextKit)
cannot be exercised on Linux, and frame setters silently drop what does not fit.

## Decision

1. `AgendaLayout` (AppCore) turns an `AgendaContent` into a fully positioned `RenderPlan`: every
   text run has a font, a baseline, bounds and the container it must stay inside. It measures only
   through the `TextMeasuring` protocol; `App/` supplies `CoreTextMeasurer` and executes the plan
   without deciding anything.
2. `TextFitter` is the only place text is fitted, with fixed rules:
   - whitespace and control characters collapse to single spaces;
   - single-line text that does not fit is cut at a whole `Character` and ends with "…";
   - wrapped text breaks at spaces, and a word wider than the line is broken at `Character`
     boundaries; text past the line cap ends with "…";
   - a to-do task shrinks from 12 pt to 9 pt before it wraps, with at most three lines, and its
     notes take one line;
   - to-dos that do not fit the grid are never drawn and are reported as omitted tasks, which the
     preview lists.
3. The to-do grid is erased by one white fill over its measured area and redrawn in full.
4. `LayoutAudit.violations(in:)` checks every plan: a run outside its container, a container outside
   the page, two runs overlapping, a link to a missing page, an empty plan. The audit runs in
   AppCore tests against a deterministic fake font over the long-text fixtures
   (`AgendaContentFixtures`), and in `AppTests` against the real fonts.

## Alternatives considered

- **Let CoreText or TextKit fit text into rectangles at draw time.** Untestable on Linux and
  silently drops overflow.
- **Copy the Python rules unchanged** (cut without ellipsis, wrap only at spaces, raise on a full
  list). They produce the broken pages described above.
- **Query the chrome's drawings at render time to find the to-do grid.** Not possible with
  `CGPDFDocument`, and it leaves artifacts.
- **Wrap or shrink long meeting titles.** Wrapping breaks the meeting page; shrinking a 20 pt
  title makes pages inconsistent. A title is cut on one line with "…" instead.

## Consequences

- Layout is tested on Linux at 100% line coverage; a new layout rule needs a fixture the audit
  reads.
- A long title is shortened on the page, never wrapped; the full title stays on the review screen.
- The app cannot lay text out with a framework feature that the `TextMeasuring` protocol cannot
  express.

## Verification

`AppCore/Sources/Layout/TextFitter.swift`, `AgendaLayout.swift`, `AgendaLayout+Overview.swift`,
`AgendaLayout+Delegated.swift`, `LayoutAudit.swift` (each has a 100% floor in
`scripts/check_coverage_floor.py`); `AppCore/Tests/Layout/`; `AppTests/RenderingTests.swift`.

## Related

ADR 0007; ADR 0011.
