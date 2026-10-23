# Plan: binder paging, delete page, continued titles and Start over

## Goal

Five changes to the iPad binder, requested by the maintainer directly (there is no issue):

1. **Swipe left/right between pages** instead of scrolling vertically. Each page is shown whole,
   scaled to fit the screen, one page per swipe.
2. **The jump buttons (Overview, Delegated tasks, Notes) and Add page show the whole page**, from
   its top. Paging gives this. Delegated jumps to the first delegated page, as it already does.
3. **An added copy of a meeting page is titled `cont. <meeting title>`**, right after the printed
   "Meeting title:" label, on every added copy (the second, third, … page of that meeting).
4. **Delete page**: a toolbar button that deletes the page on screen after an "are you sure"
   alert. Only pages made with Add page can be deleted; the button is disabled on every other page.
5. **Start over**: on a day whose binder is started, a toolbar action that, after an "are you
   sure" alert saying all notes will be deleted, deletes the day's handwriting and added pages and
   renders the day fresh. Render itself keeps working as it does today (it keeps handwriting on
   its pages).

## Current state

- `App/Screens/BinderView.swift:75-105`: the binder is a `ScrollView(.vertical)` with a
  `LazyVStack`, `.scrollTargetLayout()`, `.scrollPosition(id: $visibleKey)` and
  `.contentMargins(.bottom, 600, for: .scrollContent)` (the margin exists only so the last page
  can reach the top). `scroll(to:)` (`:47-51`) sets `visibleKey` with animation; `addPage()`
  (`:53-60`) scrolls to the returned key; the page indicator (`:133-140`) reads `visibleIndex`.
  The page is A4 portrait (595.3 × 841.9 pt, `slots.json`), so fitted to the width it is taller
  than an iPad screen in portrait, and a jump can leave its bottom off screen.
- `App/Screens/BinderToolbar.swift`: the toolbar row; `button(_:_:_:action:)` makes an icon
  button with label and identifier. Identifiers live in `BinderView.ID`.
- `App/Screens/BinderPageView.swift`: the canvas is `.pencilOnly` unless `-MagendaFingerDrawing`
  is passed, so a finger pans the enclosing scroll view.
- `AppUITests/BinderUITests.swift`: `draw(on:)` draws a horizontal finger stroke (dx 0.3 → 0.7)
  with `-MagendaFingerDrawing`. In a horizontal paging scroll view that drag competes with the
  page swipe.
- `AppCore/Sources/Binder/BinderDay.swift:86-99`: `addPage(after:id:)`; `ExtraPage` has `id`,
  `after`, `source` (never `.extra`).
- `AppCore/Sources/Binder/BinderSession.swift:59-71`: `addPage(after:)` re-plans and saves the
  day; `setInk` (`:43-57`) saves ink; `store.saveInk(Data(), …)` deletes a page's ink
  (`BinderStore.swift:50-52`, `:106-133`).
- `AppCore/Sources/Binder/BinderLayout.swift`: `plan(for:)` (`:23-41`) composes base, retained and
  added pages; `insertExtras` (`:69-115`) and its `copy(of:)` (`:79-85`) copy the source page's
  operations verbatim; `remapLinks` (`:117-134`) runs afterwards. `origins` is
  `[base.plan] + contents.map { … }`, where `contents` are the retained pages' distinct contents;
  `ComposedPage.origin` indexes it.
- `AppCore/Sources/Layout/AgendaLayout.swift:115-147`: `meetingTitles(of:)` and
  `meetingKey(at:in:)` (both `private`), and `meetingPage(title:key:)`, which emits the label runs
  of `meeting_unit` (the "Meeting title:" label, `slots.json` id `meeting.label`) followed by the
  title runs in the `meeting.title` slot, fitted with `fitter.singleLine(… maxWidth:
  TemplateGeometry.meetingTitleWidth)` (ellipsized with `…`, U+2026). `plan(for:)` then appends the
  header runs and `addingLinks` (`AgendaLayout+Links.swift`) the links; header links are found by
  the header slots' containers, never the title's. `TextPlacer.place` places no run for an empty
  line.
- Rendering a started day: `AgendaController.render()` (`AgendaController.swift:299-341`) rebases
  the open day onto the new content (`BinderLayout.rebased`, ADR 0021), keeping handwriting and
  added pages; `saveBinder` (`:405-430`) rebases again from the open session if it changed during
  the render, then updates the session in place or creates one with the store's ink. There is no
  way to discard a day's notes. The Render button is `AgendaView.swift:217-223`, enabled by
  `canRender` (`:35-37`); the Agenda menu has its own Render (`AgendaCommands.swift:26-30`).
- The store keeps a day's ink under page keys, including keys no longer shown (ADR 0021,
  Consequences). `BinderStore.ink(on:)` lists all of them; `saveInk(Data(), for:on:)` removes one.
- `scripts/check_coverage_floor.py` has `OVERALL_FLOOR = 100.0` and holds `AgendaLayout.swift`,
  `BinderLayout.swift` and `BinderStore.swift` at 100% by name: every line of new AppCore code must
  run in a test.
- This container has no Swift toolchain; `swift test`, coverage and `swift format` come from the
  `core` and `lint` jobs of a dispatched `tests.yml`, the app and UI tests from its `app` and `ui`
  jobs (`.claude/skills/steward/SKILL.md`). UI test classes not named in a shard run in `rest`.

## Design

### D1. Continued meeting titles (`AgendaLayout.swift`, `BinderLayout.swift`)

- In `AgendaLayout`, extract the title-run code of `meetingPage(title:key:)` into
  `func meetingTitleRuns(_ title: String) -> [TextRun]` (internal) and have `meetingPage` call it.
  The output of `plan(for:)` must not change.
- Add to `AgendaLayout`, in `AgendaLayout.swift` (it needs the `private` helpers):
  ```swift
  /// The text a continued meeting page shows as its title.
  static func continuedTitle(_ title: String) -> String {
      title.isEmpty ? "cont." : "cont. \(title)"
  }

  /// `page`'s operations with its meeting title replaced by the continued title, when `page` is a
  /// meeting page laid out from `content`; otherwise its operations unchanged.
  func continuedOperations(of page: PagePlan, in content: AgendaContent) -> [DrawOperation] {
      guard page.chrome == .meeting,
          let index = meetingTitles(of: content).indices.first(where: {
              meetingKey(at: $0, in: content) == page.key
          })
      else {
          return page.operations
      }
      let title = meetingTitles(of: content)[index]
      // A meeting page's operations start with its label runs, then its title runs.
      let start = labelRuns(of: slots(on: "meeting_unit")).count
      let end = start + meetingTitleRuns(title).count
      return Array(page.operations[..<start])
          + meetingTitleRuns(Self.continuedTitle(title)).map { .text($0) }
          + page.operations[end...]
  }
  ```
  An empty or whitespace-only title places no runs, so `end == start` and the continued title is
  inserted right after the label.
- `BinderLayout.plan(for:)`: build `let originContents = [day.content] + contents` next to
  `origins`. Change `insertExtras` to
  `insertExtras(_ extras: [ExtraPage], into pages: [ComposedPage], layout agenda: AgendaLayout, contents: [AgendaContent])`,
  called as
  `insertExtras(day.extras, into: withRetained, layout: layout(day.theme), contents: originContents)`.
  In `copy(of:)`, the operations become
  `agenda.continuedOperations(of: entry.source.page, in: contents[entry.source.origin])`. Links
  are remapped afterwards as today. Every added copy of a meeting page, chained or not, gets the
  prefix, since its `source` is always the meeting page. Add to `plan(for:)`'s doc comment: "An
  added copy of a meeting page is titled as continued."
- Rejected: storing the title in `ExtraPage` (a format change for a derived value); editing the
  already-ellipsized run text (it would ellipsize twice).

### D2. Deleting an added page (`BinderDay.swift`, `BinderSession.swift`)

- `BinderDay`:
  ```swift
  /// Removes the added page `id`; pages that followed it follow the page it followed. Nothing
  /// happens when there is no such page.
  public mutating func removePage(id: String)
  ```
  `guard let removed = extras.first(where: { $0.id == id }) else { return }`; for every extra with
  `after == .extra(id)`, set `after = removed.after`; then `extras.removeAll { $0.id == id }`.
- `BinderSession`:
  ```swift
  /// Whether `key` is a page the person added, which they can delete.
  public func canDelete(_ key: PageKey) -> Bool

  /// Deletes the added page `key` and its handwriting, saves the day, and returns the key of the
  /// page to show instead: the one before it. Returns nil and changes nothing when `key` is not an
  /// added page of this day.
  public func deletePage(_ key: PageKey) -> PageKey?
  ```
  `canDelete`: `guard case .extra(let id) = key else { return false }; return day.extras.contains { $0.id == id }`.
  `deletePage`:
  `guard canDelete(key), case .extra(let id) = key, let index = self.index(of: key) else { return nil }`;
  `day.removePage(id: id)`; `plan = layout.plan(for: day)`; `ink[key] = nil`;
  `do { try store.saveDay(day); try store.saveInk(Data(), for: key, on: date); message = nil } catch { message = "Couldn't delete the page. Free some space on this device." }`;
  return `plan.pages[max(0, min(index - 1, plan.pages.count - 1))].key` (one expression, so no
  unreachable branch; the overview is first and never deletable, so this is the page before).
- `BinderDay.formatVersion` stays 1: nothing new is stored.

### D3. Horizontal paging (`BinderView.swift`)

Replace the body's scroll view with:
```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 0) {
        ForEach(Array(plan.pages.enumerated()), id: \.element.key) { index, page in
            BinderPageView(...)   // unchanged arguments
                .aspectRatio(plan.pageWidth / plan.pageHeight, contentMode: .fit)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(ID.binderPage(index))
                .accessibilityLabel(Self.label(for: page.key))
                .accessibilityValue(binder.ink[page.key] == nil ? "Blank" : "Handwritten")
                .padding(16)
                .containerRelativeFrame([.horizontal, .vertical])
        }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.paging)
.scrollIndicators(.hidden)
.scrollPosition(id: $visibleKey)
```
Remove `.contentMargins(.bottom, 600, for: .scrollContent)` and its comment. Keep everything else
(`safeAreaInset`s, toolbar, sheet). Doc comments: the type becomes "The day's binder on iPad: its
pages side by side, one whole page per screen, each with a canvas to write on, the page
indicator, and Share PDF with the handwriting on the pages."; `visibleIndex` becomes "The
position of the page on screen; the first page until it moves."; `addPage()` becomes "Adds a
blank page after the one on screen and shows it." The code of `scroll(to:)` and `addPage()` stays.

Rejected: vertical scrolling (a page taller than the screen is cut and a jump can leave its bottom
off screen); fit-to-width with vertical scrolling inside a page (the maintainer chose whole pages).

### D4. Delete button and alert (`BinderView.swift`, `BinderToolbar.swift`)

- `BinderView.ID`: add `static let deletePageButton = "deletePageButton"`,
  `static let confirmDeletePageButton = "confirmDeletePageButton"` and
  `static let cancelDeletePageButton = "cancelDeletePageButton"`.
- `BinderToolbar`: declare `let canDeletePage: Bool` and `let deletePage: () -> Void` after
  `let addPage`, and pass them last, in that order, in `BinderView`'s `BinderToolbar(…)` call.
  Right after the Add page button:
  `button("trash", "Delete this page", BinderView.ID.deletePageButton) { deletePage() }.disabled(!canDeletePage)`.
  The type's doc comment becomes "The binder's controls in one scrolling row: go to a page, pick a
  pen or the eraser, undo and redo, and add or delete a page."
- `BinderView`: `@State private var confirmsDelete = false`; pass
  `canDeletePage: visibleKey.map { binder.canDelete($0) } ?? false` and
  `deletePage: { confirmsDelete = true }`. After the `.sheet`:
  ```swift
  .alert("Delete this page?", isPresented: $confirmsDelete) {
      Button("Delete", role: .destructive, action: deleteVisiblePage)
          .accessibilityIdentifier(ID.confirmDeletePageButton)
      Button("Cancel", role: .cancel) {}
          .accessibilityIdentifier(ID.cancelDeletePageButton)
  } message: {
      Text("The page and its handwriting will be removed. This can't be undone.")
  }
  ```
  and
  ```swift
  /// Deletes the added page on screen and shows the page before it.
  private func deleteVisiblePage() {
      guard let key = visibleKey, let next = binder.deletePage(key) else {
          return
      }
      if lastEditedKey == key {
          lastEditedKey = nil
      }
      scroll(to: next)
  }
  ```
- Rejected: deleting the overview, delegated, meeting or notes pages. They come from Google
  Calendar and Tasks and would come back on the next Render, or need a stored list of hidden pages
  and a `BinderDay` format change.

### D5. Start over (`AgendaController.swift`, `AgendaView.swift`)

- `AgendaController`, next to `render()`:
  ```swift
  /// Deletes the day's handwriting and added pages and renders the day fresh, as if it had never
  /// been started.
  public func startOver() async {
      guard draft != nil else {
          return
      }
      do {
          for key in try binderStore.ink(on: day).keys {
              try binderStore.saveInk(Data(), for: key, on: day)
          }
      } catch {
          message =
              "Couldn't delete this day's handwriting. Free some space on this device and try again."
          return
      }
      binder = nil
      binderExport = nil
      await render()
  }
  ```
  With `binder` nil, `render()` takes no base and no inked keys, builds a fresh `BinderDay` (no
  extras, no retained pages), and `saveBinder` saves it over the stored day and opens a new session
  with the store's (now empty) ink. Every stored ink key is removed, including keys no longer shown,
  so nothing comes back on a later Render. `BinderStore` gets no new method.
- `AgendaView.ID`: add `static let startOverButton = "startOverButton"`,
  `static let confirmStartOverButton = "confirmStartOverButton"` and
  `static let cancelStartOverButton = "cancelStartOverButton"`.
- `AgendaView`: `@State private var confirmsStartOver = false`. In `toolbar`, before the Render
  item:
  ```swift
  if UIDevice.current.userInterfaceIdiom == .pad, controller.binder != nil {
      ToolbarItem(placement: .primaryAction) {
          Button("Start Over", systemImage: "arrow.counterclockwise") {
              confirmsStartOver = true
          }
          .disabled(!canRender)
          .accessibilityLabel("Start this day over")
          .accessibilityIdentifier(ID.startOverButton)
      }
  }
  ```
  On the `NavigationSplitView` (next to its other modifiers):
  ```swift
  .alert("Start this day over?", isPresented: $confirmsStartOver) {
      Button("Start Over", role: .destructive) {
          Task { await controller.startOver() }
      }
      .accessibilityIdentifier(ID.confirmStartOverButton)
      Button("Cancel", role: .cancel) {}
          .accessibilityIdentifier(ID.cancelStartOverButton)
  } message: {
      Text(
          "All your notes on this day will be deleted: the handwriting and the pages you added. The binder is then rendered again from your calendar and tasks. This can't be undone."
      )
  }
  ```
- The Agenda menu (`AgendaCommands.swift`) gets no Start Over item: the confirmation lives in the
  view, and a menu item without it would delete notes with one keystroke.
- Rejected: making Render itself start over with a warning (it would lose the ink-keeping re-render
  of ADR 0021, which the maintainer wants to keep); deleting the day's folder through a new
  `BinderStore` method (removing every ink key with the existing API does the same, with no new
  protocol requirement).

### D6. Exact strings

- Title: `cont.` / `cont. <title>`.
- Delete: toolbar label `Delete this page`; alert title `Delete this page?`; message
  `The page and its handwriting will be removed. This can't be undone.`; buttons `Delete`,
  `Cancel`; save failure `Couldn't delete the page. Free some space on this device.`
- Start over: button `Start Over`, accessibility label `Start this day over`; alert title
  `Start this day over?`; message `All your notes on this day will be deleted: the handwriting and the pages you added. The binder is then rendered again from your calendar and tasks. This can't be undone.`;
  buttons `Start Over`, `Cancel`; failure
  `Couldn't delete this day's handwriting. Free some space on this device and try again.`

## ADRs

- **ADR 0022**: The binder shows one whole page per screen and pages turn with a horizontal swipe.
  Amends ADR 0020.
- **ADR 0023**: Only pages added in the binder can be deleted, with their handwriting, after a
  confirmation; an added copy of a meeting page is titled "cont." at layout time and not stored.
  Amends ADR 0020.
- **ADR 0024**: Render keeps a started day's handwriting; Start over is a separate, confirmed
  action that deletes all of the day's handwriting and added pages and renders it fresh. Amends
  ADR 0021.

## Manual steps

None before implementation. The real-iPad check (swiping with a finger while the Pencil writes)
is added to `docs/release-testing.md`'s release checklist by the last phase, so every release runs
it; no `manual_after` item and no step-by-step page.

## Risks and open questions

- **`containerRelativeFrame` and the insets.** If the page sits under the toolbar or the page
  indicator, `testAPageIsShownWhole` fails. p1 tries one fallback (a `GeometryReader`) and
  otherwise stops with `status=blocked`.
- **Finger drawing in a paging scroll view.** The drawing UI tests switch to a vertical stroke. If
  one still turns pages, p1 stops with `status=blocked`.
- **Alert button identifiers.** SwiftUI may not expose them to XCUITest. The fallback is
  `app.alerts.firstMatch.buttons["…"]` by text, as `AppUITests/SettingsUITests.swift:222-223` finds
  its confirmation dialog's button, with a comment saying why. If that fails too, stop.
- **Meeting page operation order.** D1 assumes a meeting page's operations are its label runs,
  then its title runs. If the reworked `addedPage` test shows the original title still on the copy,
  stop.
- **Start over while a render runs.** `render()` already drops an overtaken render's result by
  generation; `startOver` calls `render()`, so the later call wins. If
  `AgendaControllerBinderTests`' existing overtaking test fails, stop.

## Implementation manifest

```yaml
plan_slug: binder-paging-and-start-over
feature_branch: feature/binder-paging-and-start-over
max_parallel: 2
manual_before: []
manual_after: []
verify_after_merge:
  - swift test --package-path AppCore --filter "Binder|AgendaLayout|AgendaController"
final_checks:
  - docs/binder-paging-and-start-over-plan.md is deleted and nothing links to it
  - docs/adr/0022-*.md, docs/adr/0023-*.md and docs/adr/0024-*.md exist, are Accepted, and are in docs/adr/README.md's index
  - CHANGELOG.md has [Unreleased] entries for paging, Delete page, cont. titles and Start over, and no new version heading
  - BinderDay.formatVersion is still 1
phases:
  - id: p1-binder-pages
    title: Horizontal paging, Delete page and continued meeting titles in the binder
    depends_on: []
    complexity: M
    touches:
      - AppCore/Sources/Layout/AgendaLayout.swift
      - AppCore/Sources/Binder/BinderLayout.swift
      - AppCore/Sources/Binder/BinderDay.swift
      - AppCore/Sources/Binder/BinderSession.swift
      - App/Screens/BinderView.swift
      - App/Screens/BinderToolbar.swift
      - AppCore/Tests/Layout/AgendaLayoutTests.swift
      - AppCore/Tests/Binder/BinderLayoutTests.swift
      - AppCore/Tests/Binder/BinderDayTests.swift
      - AppCore/Tests/Binder/BinderSessionTests.swift
      - AppUITests/BinderUITests.swift
    brief: |
      Implement the plan's Design sections D1, D2, D3, D4 and the strings in D6 exactly as written.
      Do not edit docs, CHANGELOG.md or ADRs; the last phase does.
      1. AgendaLayout.swift: extract meetingTitleRuns(_:), add continuedTitle(_:) and
         continuedOperations(of:in:) (D1).
      2. BinderLayout.swift: originContents, the new insertExtras(_:into:layout:contents:)
         signature, copy(of:) uses continuedOperations, the plan(for:) doc comment line (D1).
      3. BinderDay.swift: removePage(id:). BinderSession.swift: canDelete(_:), deletePage(_:) (D2).
      4. BinderView.swift: horizontal paging (D3); the delete alert, deleteVisiblePage and the new
         ID constants (D4). BinderToolbar.swift: canDeletePage, deletePage and the trash button (D4).
      5. AppCore/Tests/Binder/BinderLayoutTests.swift:
         - addedPage: keep its keys, chrome and targets(plan.pages[2]) == [0, 4] expectations;
           replace the operations-equality expectation with texts(plan.pages[2]).contains("cont. A"),
           !texts(plan.pages[2]).contains("A") and texts(plan.pages[1]).contains("A").
         - New "Every added copy of a meeting page is titled as continued": addPage(after:
           .meeting("a"), id: "x"), then addPage(after: .extra("x"), id: "y"); both extra pages'
           texts contain "cont. A".
         - New "An added copy of the blank meeting page is titled cont.": binder(content([])),
           addPage(after: .meeting(""), id: "x"); the extra's texts contain "cont.", at the index
           of "Meeting title:" plus one.
         - New "An added copy of a retained meeting page is titled from its own content": a day
           with retained: [RetainedPage(key: .meeting("gone"), content: content(["gone"]))] and
           addPage(after: .meeting("gone"), id: "x"); the extra's texts contain "cont. GONE".
         - New "Added copies of other pages keep their text": extras after .overview and after
           .notes; each extra's texts equal its source page's texts.
         - audit: after the two existing addPage calls add
           let meeting = try #require(base.first { if case .meeting = $0 { true } else { false } })
           and bound.addPage(after: meeting, id: "e3"); the count expectation becomes base.count + 4.
         - Update the file's opening comment to mention continued meeting titles.
      6. AppCore/Tests/Layout/AgendaLayoutTests.swift (its layout() and content(meetings:)
         helpers): "A continued title that is too wide is ellipsized to the title width" (a title
         of 200 "x"; the run after the label runs starts with "cont. ", ends with "…" and has
         width <= TemplateGeometry.meetingTitleWidth); "A page whose key is not in the content
         keeps its operations" (the meeting page of content(meetings: ["A"]) rebuilt as
         PagePlan(key: .meeting("zz"), chrome: page.chrome, operations: page.operations));
         "A page that is not a meeting page keeps its operations" (the overview page). Update the
         opening comment.
      7. AppCore/Tests/Binder/BinderDayTests.swift: "Removing an added page makes the pages after
         it follow the page it followed" (x after .meeting("a"), y after .extra("x"), remove x:
         extras == [ExtraPage(id: "y", after: .meeting("a"), source: .meeting("a"))]); "Removing an
         unknown page changes nothing". Update the opening comment.
      8. AppCore/Tests/Binder/BinderSessionTests.swift:
         - "a deleted page goes with its handwriting, and the page before it is shown":
           InMemoryBinderStore; let key = session.addPage(after: meeting);
           session.setInk(Data([1]), on: key); deletePage(key) == meeting; index(of: key) == nil;
           ink[key] == nil; try store.day(date)?.extras == []; try store.ink(on: date)[key] == nil;
           message == nil.
         - "only added pages can be deleted": canDelete(.overview), canDelete(meeting),
           canDelete(.extra("zz")) are false; deletePage(.overview) == nil and the plan is unchanged.
         - "a failed save of a deletion leaves a message": session on
           FailingBinderStore(.unwritable, failing: [.saveDay]); let key = session.addPage(after:
           meeting); deletePage(key) == meeting; message == "Couldn't delete the page. Free some
           space on this device."
         - Add no API to the stores. Update the opening comment.
      9. AppUITests/BinderUITests.swift:
         - draw(on:) becomes a vertical stroke from CGVector(dx: 0.5, dy: 0.4) to
           CGVector(dx: 0.5, dy: 0.7); doc comment "Draws a vertical stroke down the middle of
           `page` with a finger."
         - Rename testAFingerScrollsTheBinder to testAFingerSwipesToTheNextPage, using
           binder.swipeLeft().
         - New testAPageIsShownWhole: after render, binderView.frame.contains(page.frame) for
           binderPage.0, and page.frame.minY >= element(app, "binderOverviewButton").frame.maxY.
         - Extract the retry loop of testAddPageAddsAPageAfterTheCurrentOne into
           private func addPage(_ app: XCUIApplication) -> Int returning the new page count; the
           test keeps its assertion on top of it.
         - New testDeletingAnAddedPageAsksFirst: let total = addPage(app); deletePageButton is
           enabled; tap it; tap cancelDeletePageButton; waitForIndicator(app, matching:
           "Page 2 of \(total)") equals "Page 2 of \(total)"; tap deletePageButton; tap
           confirmDeletePageButton; waitForIndicator(app, matching: "Page 1 of \(total - 1)")
           equals "Page 1 of \(total - 1)".
         - New testDeletingIsDisabledOnAPrintedPage: after render, deletePageButton exists and
           isEnabled == false.
         - Every new test starts with
           try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only").
           Update the opening comment to mention swiping and deleting pages.
      10. Push and dispatch tests.yml on the phase branch; read core, lint, scripts, app and ui.
      Stop with status=blocked if: plainDay in BinderLayoutTests fails after step 1; the reworked
      addedPage shows the original title on the copy or the label missing; a drawing UI test turns
      pages instead of drawing; testAPageIsShownWhole fails after one try of wrapping the
      ScrollView in a GeometryReader and giving each page
      .frame(width: proxy.size.width, height: proxy.size.height) instead of
      .containerRelativeFrame; the alert buttons are not found by identifier nor by
      app.alerts.firstMatch.buttons["Delete"] / ["Cancel"] (use that fallback, with a comment that
      SwiftUI does not expose alert button identifiers to XCUITest, as SettingsUITests.swift:222
      finds its dialog's button by text); the coverage floor fails for a file outside touches.
    acceptance:
      - grep -n "ScrollView(.horizontal)" App/Screens/BinderView.swift and grep -n "scrollTargetBehavior(.paging)" App/Screens/BinderView.swift match; grep -n "contentMargins\|ScrollView(.vertical)" App/Screens/BinderView.swift matches nothing
      - grep -n "Delete this page?" App/Screens/BinderView.swift matches
      - grep -n "formatVersion = 1" AppCore/Sources/Binder/BinderDay.swift matches
      - tests.yml on the phase branch is green in core (with the coverage floor), lint, scripts, the three app jobs and the nine ui jobs
      - BinderLayoutTests, BinderDayTests, BinderSessionTests and AgendaLayoutTests pass, including the new tests named in the brief
      - on ui (ipad, newest, …), testAFingerSwipesToTheNextPage, testAPageIsShownWhole, testDeletingAnAddedPageAsksFirst, testDeletingIsDisabledOnAPrintedPage, testAddPageAddsAPageAfterTheCurrentOne, testNotesAndOverviewButtonsMoveBetweenPages, testHandwritingStaysWithTheDay, testHandwritingSurvivesARelaunch and testUndoAndRedoAffectTheLastDrawing pass

  - id: p2-start-over
    title: Start over deletes a started day's notes and renders it fresh, after a confirmation
    depends_on: []
    complexity: S
    touches:
      - AppCore/Sources/Controller/AgendaController.swift
      - AppCore/Tests/Controller/AgendaControllerBinderTests.swift
      - App/Screens/AgendaView.swift
      - AppUITests/StartOverUITests.swift
    brief: |
      Implement the plan's Design section D5 and the Start over strings in D6 exactly as written.
      Do not edit docs, CHANGELOG.md or ADRs; the last phase does.
      1. AgendaController.swift: add startOver() right after render() (D5).
      2. AgendaView.swift: the three ID constants, @State confirmsStartOver, the Start Over toolbar
         item before Render, and the alert on the NavigationSplitView (D5). Do not touch
         AgendaCommands.swift.
      3. AppCore/Tests/Controller/AgendaControllerBinderTests.swift (use its started(_:), make(…)
         and Context helpers; context.binderStore is the store; use context.controller.day for the
         date):
         - "starting over deletes the handwriting and added pages and renders a fresh day":
           started(.standard); render(); let binder = controller.binder; binder.setInk(Data([1]),
           on: .overview); _ = binder.addPage(after: .overview); also
           context.binderStore.saveInk(Data([2]), for: .meeting("gone"), on: day) (a key no longer
           shown); await controller.startOver(); controller.binder is not nil and
           !== the old binder; its ink is empty; its day.extras and day.retained are empty;
           try context.binderStore.ink(on: day) is empty; the stored day == the new binder's day;
           its plan's keys == baseKeys(controller); controller.message == nil.
         - "start over without a draft does nothing": make() without start(); startOver(); binder
           is nil and binderStore.day(day) is nil.
         - "a failed delete of the handwriting leaves the binder and a message": make(binderStore:
           FailingBinderStore(.unwritable, failing: [])) and start(); render(); setInk(Data([1]),
           on: .overview) on the binder; store.setFailing([.saveInk]); startOver(); the binder is
           the same object with ink [.overview: Data([1])], and message == "Couldn't delete this
           day's handwriting. Free some space on this device and try again."
         - Update the file's opening comment to mention starting over.
      4. New AppUITests/StartOverUITests.swift, class StartOverUITests, modelled on
         BinderUITests.swift (its launch, element, render, draw and waitForValue helpers, copied as
         private helpers, with draw(on:) as a vertical stroke from CGVector(dx: 0.5, dy: 0.4) to
         CGVector(dx: 0.5, dy: 0.7)); opening comment: "Start over on iPad: it asks first, and
         confirming deletes the day's handwriting and renders it fresh. Layer 2 of
         docs/testing-policy.md; elements are found by identifier."
         - testStartOverIsOfferedOnlyOnceTheDayIsStarted: iPad only; launch "standard"; before
           render, startOverButton does not exist; after render it exists.
         - testStartOverAsksAndThenDeletesTheHandwriting: iPad only; launch "standard" with
           "-MagendaFingerDrawing"; render; draw on binderPage.0 and wait for "Handwritten"; tap
           startOverButton, tap cancelStartOverButton, binderPage.0 is still "Handwritten"; tap
           startOverButton, tap confirmStartOverButton; waitForValue(binderPage.0, "Blank") is
           "Blank".
         - Both start with try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only").
      5. Push and dispatch tests.yml on the phase branch; read core, lint, scripts, app and ui.
      Stop with status=blocked if: an existing AgendaControllerBinderTests test fails (in
      particular "a render overtaken by a load saves no binder"); the alert buttons are not found
      by identifier nor by app.alerts.firstMatch.buttons["Start Over"] / ["Cancel"] (use that
      fallback with a comment that SwiftUI does not expose alert button identifiers to XCUITest);
      the Start Over toolbar item is not reachable by identifier on the iPad simulator (it may be
      folded into an overflow menu); the coverage floor fails for a file outside touches.
    acceptance:
      - grep -n "func startOver" AppCore/Sources/Controller/AgendaController.swift matches
      - grep -n "Start this day over?" App/Screens/AgendaView.swift matches; grep -n "Start Over" App/Screens/AgendaCommands.swift matches nothing
      - tests.yml on the phase branch is green in core (with the coverage floor), lint, scripts, the three app jobs and the nine ui jobs
      - AgendaControllerBinderTests passes, including the three new tests
      - on ui (ipad, newest, …), testStartOverIsOfferedOnlyOnceTheDayIsStarted and testStartOverAsksAndThenDeletesTheHandwriting pass

  - id: p3-retire-plan
    title: ADRs 0022 to 0024, docs and changelog; delete the plan
    depends_on: [p1-binder-pages, p2-start-over]
    complexity: S
    touches:
      - docs/adr/0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md
      - docs/adr/0021-a-binder-day-is-stored-as-a-content-snapshot-and-ink-per-page-key.md
      - docs/adr/0022-binder-pages-turn-sideways-one-whole-page-at-a-time.md
      - docs/adr/0023-only-added-binder-pages-can-be-deleted.md
      - docs/adr/0024-start-over-is-separate-from-render.md
      - docs/adr/README.md
      - README.md
      - docs/release-testing.md
      - CHANGELOG.md
      - docs/binder-paging-and-start-over-plan.md
    brief: |
      Write the ADRs and docs for what p1 and p2 built, then delete this plan. Read the plan's
      Design and ADRs sections first. No project history anywhere (ADR 0008): no phase names, plan
      ids or bare issue numbers.
      1. ADRs, following the template and rules in docs/adr/README.md (one decision per ADR;
         Status, Context, Decision, Alternatives considered, Consequences, Verification with source
         and test files, Related). Status: "Accepted — <output of date +%F>. Implemented." plus
         the Amends line below.
         - docs/adr/0022-binder-pages-turn-sideways-one-whole-page-at-a-time.md: Amends ADR 0020.
           Decision from D3; alternatives from D3's "Rejected". Index row: "The binder shows one
           whole page per screen and pages turn with a horizontal swipe".
         - docs/adr/0023-only-added-binder-pages-can-be-deleted.md: Amends ADR 0020. Decision from
           D2 and D4; alternatives from D4's "Rejected"; Consequences: an added copy of a meeting
           page is titled "cont. <title>", computed at layout time (D1), so neither adding nor
           deleting pages changes the stored format. Index row: "Only pages added in the binder
           can be deleted, with their handwriting, after a confirmation".
         - docs/adr/0024-start-over-is-separate-from-render.md: Amends ADR 0021. Decision from D5
           (Render keeps handwriting as before; Start over, on iPad, after a confirmation, removes
           every stored ink key of the day, including keys no longer shown, and renders a fresh
           day; it is not in the Agenda menu); alternatives from D5's "Rejected". Index row:
           "Render keeps a started day's handwriting; Start over is a separate, confirmed action
           that deletes it and renders the day fresh".
         - Add to ADR 0020's Status the lines
           "Amended by [ADR 0022](0022-binder-pages-turn-sideways-one-whole-page-at-a-time.md)."
           and "Amended by [ADR 0023](0023-only-added-binder-pages-can-be-deleted.md).", and to ADR
           0021's Status "Amended by [ADR 0024](0024-start-over-is-separate-from-render.md).".
           Change nothing else in either.
         - Add the three rows to docs/adr/README.md's index.
      2. README.md "Binder (iPad)": pages are swiped left and right, one whole page at a time; the
         toolbar also has Delete page, which removes a page you added after asking; a page added
         after a meeting page is titled "cont." before the meeting's title; Render again keeps
         your handwriting on its pages, and Start over (in the agenda's toolbar, after asking)
         deletes all of the day's handwriting and added pages and renders it fresh. Change
         "(ADR 0020, ADR 0021)" to "(ADR 0020 to ADR 0024)".
      3. docs/release-testing.md: change "scroll it off screen and back" to "swipe to another page
         and back"; add "- [ ] On an iPad with an Apple Pencil, swipe between binder pages with a
         finger while the Pencil writes, and no stroke turns into a swipe or a swipe into a stroke."
      4. CHANGELOG.md, under the existing "## [Unreleased]" "### Added" (the binder is not in a
         stable release yet, so rewrite its bullets; no new heading):
         - Replace the first bullet with: "On iPad, Render opens the day's binder: one whole page
           at a time, swiped left and right. Write on its pages with Apple Pencil, and the
           handwriting is saved with the day, also offline once the day is started."
         - Replace the toolbar bullet with: "The binder toolbar has black, blue, red and green
           pens, an eraser, undo and redo, buttons to jump to the overview, delegated tasks and
           notes, Add page, which puts a blank copy of the current page after it (titled "cont."
           before the meeting's title on a meeting page), and Delete page, which removes a page
           you added after asking."
         - Add after the "Rendering a day again keeps your handwriting…" bullet: "Start over, on a
           started day, deletes all of its handwriting and added pages after asking and renders it
           fresh."
      5. git rm docs/binder-paging-and-start-over-plan.md; grep -rn
         "binder-paging-and-start-over-plan" . (excluding .git) finds nothing.
      6. Push; dispatch tests.yml; the scripts job (including the no-project-history guard) is green.
      Stop with status=blocked if the code on the branch does not match the Design (for example
      Start Over is in AgendaCommands.swift, or the stored format version changed).
    acceptance:
      - ls docs/adr/0022-*.md docs/adr/0023-*.md docs/adr/0024-*.md lists three files, each with "Accepted" in its Status
      - grep -c "Amended by" docs/adr/0020-*.md prints 2 and grep -c "Amended by" docs/adr/0021-*.md prints 1
      - grep -n "0022\|0023\|0024" docs/adr/README.md shows three index rows
      - grep -n "Start over" CHANGELOG.md README.md matches in both; grep -n "^## \[" CHANGELOG.md shows no heading that is not already on main
      - test ! -e docs/binder-paging-and-start-over-plan.md and grep -rn "binder-paging-and-start-over-plan" --exclude-dir=.git . finds nothing
      - python3 -m unittest discover -s scripts/tests passes
```
