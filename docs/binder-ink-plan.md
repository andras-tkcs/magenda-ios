# Binder ink (Stage 1 of the adaptive daily binder)

## Goal

On an iPad, Magenda becomes the binder you write in, replacing Noteshelf. Render opens the day's
pages inside the app: the same pages the PDF has today, drawn natively, with a PencilKit canvas on
each one. Handwriting is saved per day and per page, stays with its page when the day is rendered
again, survives relaunches and works offline once the day has been started. A small toolbar gives
four pen colors, an eraser, undo and redo, buttons to jump to the overview, delegated tasks and
notes, and "Add page" to put a blank copy of the current page after it (to extend a meeting or get
another notes page). Share PDF exports the day with the handwriting composited onto each page, so
the end-of-day step (share sheet to Drive, then Claude Code) keeps working. The iPhone keeps
today's read-only PDF preview.

Source: the "Adaptive Daily Binder: Design" doc, Stage 1, with its "Decisions made" and "Code
review" sections. Live content (Stage 3), automatic export (Stage 2), Tasks write access and the
five-day deletion of old days are out of scope.

## Current state

Checked on `main` at `1dd2030`.

- The pipeline runs one way and is rebuilt on every load: `GoogleDataSource` → `AgendaBuilder` →
  `AgendaDraft` → `AgendaDraft.content()` (`AppCore/Sources/Draft/AgendaDraft.swift:100`) →
  `AgendaLayout.plan(for:)` (`AppCore/Sources/Layout/AgendaLayout.swift:16`) → `RenderPlan` →
  `PDFAgendaRenderer.render` (`App/Rendering/PDFAgendaRenderer.swift:25`) → `PreviewView`
  (`App/Screens/PreviewView.swift`) in a read-only `PDFView` with a share button.
- Page order is overview, delegated pages (0…n), one page per meeting (or one blank meeting page),
  further-notes page (`AgendaLayout.swift:16-31`). Pages are addressed only by index; links are
  `.link(PlanRect, targetPage: Int)` (`AppCore/Sources/Layout/RenderPlan.swift:150`), added in
  `AgendaLayout+Links.swift`.
- `PagePlan` (`RenderPlan.swift:154`) has `chrome` and `operations` and no identity.
  `AgendaContent.meetings` is `[String]` of titles (`AppCore/Sources/Agenda/AgendaContent.swift:79`);
  the event IDs (`calendarID|eventID`, stable) are lost in `content()`.
- `AgendaContent`, `TodoItem`, `ScheduleEntry`, `DelegatedItem` and `Theme`
  (`AppCore/Sources/Layout/ThemeColors.swift:138`) are not `Codable`. `CalendarDay`, `Cadence`,
  `FontPack` and `ThemeColors` are.
- `AgendaController` (`AppCore/Sources/Controller/AgendaController.swift`, 390 lines) owns load,
  draft, render. `render()` (line 285) lays out in a detached task and writes the PDF to the
  temporary directory. Nothing but settings (UserDefaults) and tokens (Keychain) is stored.
- `AgendaRendering` (`AgendaController.swift:24`) has one method, `render(_:fileName:)`; fakes are
  `AppCore/Tests/Support/FakeRenderer.swift` and `GatedRenderer.swift`.
- `PDFAgendaRenderer` draws chrome (`drawChrome`) and operations (`draw(_:in:pageHeight:)`) only
  into a PDF context.
- iPad detail column: `AgendaView.detail` (`App/Screens/AgendaView.swift:205`) shows
  `PreviewView` or the `previewPlaceholder`.
- Tests: AppCore is gated at **100% overall line coverage** (`OVERALL_FLOOR = 100.0` in
  `scripts/check_coverage_floor.py`), so every new AppCore line needs a test. UI tests waiting for
  `pdfPreview`: `AppUITests/PreviewUITests.swift:34,89`, `AgendaEditUITests.swift:139`,
  `LongTextUITests.swift:54`, `SettingsUITests.swift:187`, `AgendaScreenUITests.swift:132`; the
  share button is checked at `PreviewUITests.swift:42,120`.
- This container has no Swift toolchain. Every phase takes AppCore's `swift test`, the coverage
  floor and `swift format` from a dispatched `tests.yml` run (`core`, `lint`), and the app build,
  hosted tests and UI tests from its three `app (...)` jobs (`.claude/skills/steward/SKILL.md`).
- No ADR conflicts for Stage 1: scopes stay read-only (ADR 0013), the template is not edited
  (ADR 0011), Google is still read on each load (ADR 0014).

## Design

### D1. Page keys

New file `AppCore/Sources/Layout/PageKey.swift`:

```swift
/// Which page of the binder a page is. Stable across layouts of changed content, so handwriting
/// stays with its page.
public enum PageKey: Hashable, Sendable, Codable {
    case overview
    case delegated(Int)      // 0-based index among the delegated pages
    case meeting(String)     // the event ID; "" for the blank meeting page of a day without meetings
    case notes
    case extra(String)       // ExtraPage.id
}
```

- `public var storageString: String`: `"overview"`, `"delegated:<n>"`, `"meeting:<id>"`,
  `"notes"`, `"extra:<id>"`.
- `public init?(storageString: String)`: split at the **first** `:`. `overview` and `notes` take no
  suffix; `delegated` needs a non-negative `Int`; `meeting` takes any suffix, empty or containing
  `:`; `extra` needs a non-empty suffix. Anything else is `nil`.
- `Codable` encodes and decodes the single string `storageString`; an unknown string throws
  `DecodingError.dataCorruptedError(in:debugDescription: "Unknown page key.")`.
- `PagePlan` gains `public let key: PageKey`; its init becomes
  `init(key: PageKey, chrome: ChromePage, operations: [DrawOperation])`.
- `AgendaContent` gains `public var meetingIDs: [String]` (doc: "The event ID of each meeting
  page, in the order of `meetings`; a meeting without one is keyed by its position.") with init
  parameter `meetingIDs: [String] = []` placed right after `meetings`. `AgendaDraft.content()`
  appends `event.id` to it in the loop that appends `event.title`.
- `AgendaLayout.plan(for:)` keys pages: overview `.overview`; delegated page *i* `.delegated(i)`;
  meeting page *i* `.meeting(content.meetingIDs[i])` when `i < meetingIDs.count`, else
  `.meeting("#\(i)")`; the blank meeting page `.meeting("")`; the notes page `.notes`.
- `LayoutAudit` gets `case duplicatePageKey(PageKey)`, reported on the page index of every repeat
  after the first.
- `Codable` (synthesized) on `AgendaContent`, `TodoItem`, `ScheduleEntry`, `DelegatedItem`,
  `Theme`.

### D2. A binder day

New file `AppCore/Sources/Binder/BinderDay.swift`:

```swift
/// A page the person added: a blank copy of `source`'s printed page, placed right after `after`.
public struct ExtraPage: Equatable, Codable, Sendable {
    public let id: String
    public var after: PageKey
    public let source: PageKey   // never an .extra key
}

/// A page that left the content on a later render but carries handwriting, kept with the content
/// it was laid out from.
public struct RetainedPage: Equatable, Codable, Sendable {
    public let key: PageKey
    public let content: AgendaContent
}

/// What a day's binder is drawn from: the content snapshot taken at Render, the theme, the pages
/// the person added and the pages kept for their handwriting.
public struct BinderDay: Equatable, Codable, Sendable {
    public static let formatVersion = 1
    public let version: Int                 // always formatVersion when created
    public var content: AgendaContent
    public var theme: Theme
    public var extras: [ExtraPage]
    public var retained: [RetainedPage]
    public var date: CalendarDay { content.date }
    public init(content: AgendaContent, theme: Theme, extras: [ExtraPage] = [], retained: [RetainedPage] = [])
    public mutating func addPage(after page: PageKey, id: String)
}
```

- Decoding throws `DecodingError.dataCorruptedError` when `version != formatVersion` (custom
  `init(from:)`; encoding is synthesized).
- `addPage(after:id:)`: `source` is the `source` of the extra named by `page` when `page` is
  `.extra(x)` and that extra exists, else `page`. Every existing extra with `after == page` gets
  `after = .extra(id)`. Then `ExtraPage(id: id, after: page, source: source)` is appended.

### D3. Binder layout

New file `AppCore/Sources/Binder/BinderLayout.swift`:

```swift
/// Lays out a binder day: the content's pages, the retained pages and the added pages, with links
/// pointing at the right pages; and rebuilds a day onto new content without losing handwriting.
public struct BinderLayout: Sendable {
    public init(manifest: TemplateManifest, measurer: any TextMeasuring)
    public func plan(for day: BinderDay) -> RenderPlan
    public func rebased(_ day: BinderDay, onto content: AgendaContent, theme: Theme,
                        inkedKeys: Set<PageKey>) -> BinderDay
}
```

`plan(for:)`, with `layout(theme)` = `AgendaLayout(manifest:measurer:theme:)`:

1. `base = layout(day.theme).plan(for: day.content)`. Every composed page remembers its *origin
   plan* (the plan whose page indexes its `.link` targets refer to).
2. Lay out each distinct `content` among `day.retained` once (first appearance order, compared
   with `==`) with `day.theme`.
3. Start the composed list with `base.pages`. For each `RetainedPage` in order: skip it if its key
   is already in the list or its plan has no page with that key; otherwise insert that page right
   after the last page in the list with the same `chrome`, or, when there is none, right before
   the `.notes` page.
4. Added pages: walk the list; after each page with key *k*, emit (depth first, in `extras` array
   order) every pending extra with `after == k`: a page with key `.extra(id)`, the `chrome` and
   `operations` of the composed page whose key is `source`, and that page's origin plan; then do the
   same after `.extra(id)`. An extra whose `source` is not in the list is dropped.
5. Extras still pending after the walk (their `after` page is gone) whose `source` is in the list:
   in array order, insert each right after the last page of its source's run (the source page and
   the extras directly following it), then emit its own chain as in step 4.
6. Links: on every composed page replace `.link(rect, targetPage: t)` with
   `.link(rect, targetPage: u)`, where `u` is the composed index of the key of page `t` in the
   page's origin plan; drop the operation when `t` is out of range or the key is not composed.
7. Return `RenderPlan(pageWidth:pageHeight:` from `base`, the composed pages,
   `omittedTodoItems: base.omittedTodoItems)`.

`rebased(_:onto:theme:inkedKeys:)`:

1. `old = plan(for: day)`; `oldKeys` = its keys that are not `.extra`.
2. Keep key *k* of `oldKeys` when `inkedKeys` contains *k*, or contains `.extra(e.id)` for an
   extra `e` with `e.source == k`.
3. `newKeys` = keys of `AgendaLayout(theme).plan(for: content)`.
4. `retained` = for every kept key not in `newKeys`, in `old`'s page order: the existing
   `day.retained` entry with that key, or `RetainedPage(key: k, content: day.content)`.
5. `extras` = `day.extras` whose `source` is in `newKeys` or in `retained`'s keys.
6. Return `BinderDay(content: content, theme: theme, extras: extras, retained: retained)`.

So a dropped meeting page with ink stays, after the remaining meeting pages; a dropped page
without ink goes, with any blank added pages copied from it. Ink stays in the store under its key
whether or not the key is still shown.

### D4. Binder store

New file `AppCore/Sources/Binder/BinderStore.swift`:

```swift
/// Why a binder could not be read or saved.
public enum BinderStoreError: Error, Equatable { case unreadable, unwritable }

/// Where binder days and their handwriting are kept on the device.
public protocol BinderStore: Sendable {
    func day(_ date: CalendarDay) throws -> BinderDay?       // nil when nothing is saved
    func saveDay(_ day: BinderDay) throws
    func ink(on date: CalendarDay) throws -> [PageKey: Data]
    func saveInk(_ data: Data, for key: PageKey, on date: CalendarDay) throws   // empty data deletes
}

public final class InMemoryBinderStore: BinderStore, @unchecked Sendable   // NSLock, like InMemorySettingsStore
public struct FileBinderStore: BinderStore { public init(directory: URL) }
```

`FileBinderStore` layout under `directory` (every name generated by the app, never taken from
Google data, joined with `URL.appending(path:)`):

- `<date.isoString>/day.json`: the `BinderDay`, `JSONEncoder` with `.sortedKeys`.
- `<date.isoString>/ink/index.json`: `[String: String]`, `PageKey.storageString` → file name.
- `<date.isoString>/ink/page-<n>.pkdata`: the bytes, `n` = 1 + the largest `n` in the index (1
  when empty).
- All writes are `.atomic`; directories are created with `withIntermediateDirectories: true`.
  Any write or directory failure throws `.unwritable`. A `day.json` or `index.json` that exists
  but cannot be read or decoded throws `.unreadable`. An index entry whose key does not parse or
  whose file is missing is skipped. `saveInk` with empty data removes the file and the entry.
- It never reads file attributes or timestamps (that would need a privacy-manifest reason).
- `FileManager.default` is fetched inside each method, not stored.

The app passes `<Application Support>/Binder` (`FileManager.default.url(for:
.applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)`), not the
temporary directory. Fixture launches use `InMemoryBinderStore()`.

### D5. Binder session and controller

New file `AppCore/Sources/Binder/BinderSession.swift`:

```swift
/// The open binder of one day: its pages, its handwriting, and saving both as they change.
@MainActor @Observable
public final class BinderSession {
    public var date: CalendarDay { day.date }
    public private(set) var day: BinderDay
    public private(set) var plan: RenderPlan
    public private(set) var ink: [PageKey: Data]
    public private(set) var message: String?
    public var inkedKeys: Set<PageKey>                 // keys with non-empty ink
    public func index(of key: PageKey) -> Int?         // in plan.pages
    public func setInk(_ data: Data, on key: PageKey)
    public func addPage(after key: PageKey) -> PageKey // the new page's key
    init(day: BinderDay, plan: RenderPlan, ink: [PageKey: Data], store: any BinderStore,
         layout: BinderLayout, makeID: @escaping @Sendable () -> String)
}
```

- `setInk`: no-op when unchanged; empty data removes the entry; saves through
  `store.saveInk` synchronously; on failure `message = "Couldn't save your handwriting. Free some
  space on this device."`; on success `message = nil`.
- `addPage(after:)`: `id = makeID()`, `day.addPage(after:id:)`, `plan = layout.plan(for: day)`,
  `store.saveDay(day)`; on failure `message = "Couldn't save the new page. Free some space on this
  device."`. Returns `.extra(id)`.

`AgendaController` changes:

- Init gains `binderStore: any BinderStore` (after `renderer:`) and, last,
  `makeID: @escaping @Sendable () -> String = { UUID().uuidString }`.
- `public private(set) var binder: BinderSession?` and `public private(set) var binderExport: URL?`.
- `load()`: right after `status = .loading` and `message = nil`, if `binder?.date != day`, open the
  stored day: `binderStore.day(day)` and `binderStore.ink(on: day)` → a `BinderSession` with
  `BinderLayout.plan(for:)`, or `nil` when nothing is stored. A thrown error sets `binder = nil`
  and `message = "Couldn't read the saved binder for this day."`. This happens before the network
  fetch, so a started day shows even when the fetch fails (offline).
- `render()`: inside the existing detached task also compute the binder day — `rebased` onto
  `draft.content()` with `settings.theme` and the open session's `inkedKeys` when `binder?.date ==
  day`, else `BinderDay(content:theme:)` — and its `BinderLayout` plan. After the existing
  generation check: `binderStore.saveDay`; on success `binder` becomes a new session with that day,
  plan and the previous session's `ink` (or `[:]`); on failure `message = "Couldn't save the
  binder. Free some space on this device and try again."` Then the existing PDF outcome handling
  (its failure message wins).
- `public func exportBinder() async`: with a binder, `renderer.render(binder.plan, ink:
  binder.plan.pages.map { binder.ink[$0.key] }, fileName: binder.date.isoString + ".pdf")` →
  `binderExport`; on failure `message = "Couldn't create the PDF. Try again."`. Status unchanged.
- `public func clearBinderExport()` sets `binderExport = nil`.
- `clearLoadedState()` also sets `binder = nil` and `binderExport = nil`.
- `AgendaRendering` becomes `func render(_ plan: RenderPlan, ink: [Data?], fileName: String)
  async throws -> URL` (`ink[i]` is page *i*'s PencilKit data; a missing index means none), with a
  public extension `render(_ plan:fileName:)` that passes `ink: []`.

### D6. Drawing pages in the app

- New `App/Rendering/PageDrawer.swift`: `final class PageDrawer: @unchecked Sendable` (immutable,
  same comment pattern as `PDFAgendaRenderer`), `init(library: FontLibrary, bundle: Bundle)
  throws` (loads `chrome.pdf`, throws `FontLibraryError.missingTemplate` as the renderer does
  today) and `func draw(_ page: PagePlan, in context: CGContext, pageHeight: Double)`, which draws
  the chrome page and every operation except `.link`. `drawChrome`, `draw`, `drawText`, `cgColor`,
  `cgRect` move here from `PDFAgendaRenderer`.
- Same file: `extension EnvironmentValues { @Entry var pageDrawer: PageDrawer? = nil;
  @Entry var allowsFingerDrawing = false }`.
- `PDFAgendaRenderer.init(drawer: PageDrawer)`; `render(_:ink:fileName:)` draws each page with the
  drawer, then its ink: `PKDrawing(data:)`, imaged with `drawing.image(from: page bounds, scale:
  3)` **inside `UITraitCollection(userInterfaceStyle: .light).performAsCurrent`** (otherwise dark
  mode turns black ink white), drawn into the page bounds; then the link destinations as today.
- `AppEnvironment.makeServices(arguments:bundle:) throws -> AppServices` replaces
  `makeController`; `struct AppServices { let controller: AgendaController; let pageDrawer:
  PageDrawer; let allowsFingerDrawing: Bool }`. `allowsFingerDrawing` is
  `arguments.contains("-MagendaFingerDrawing")`. `previewController` stays (built from
  `makeServices`) and `previewServices(_:)` is added. `MagendaApp` keeps `@State var services:
  AppServices?` and sets `.environment(services.controller)`, `.environment(\.pageDrawer, …)`,
  `.environment(\.allowsFingerDrawing, …)`; `AgendaCommands(controller: services?.controller)`.

### D7. The binder screen (iPad)

- `AgendaView.detail`: on iPad (`UIDevice.current.userInterfaceIdiom == .pad`) show
  `BinderView(binder:)` when `controller.binder` is set, else the placeholder with title "No
  binder yet" and description "Tap Render to start the day's binder."; on iPhone, unchanged. The
  placeholder keeps `ID.previewPlaceholder`. The sidebar is not hidden automatically.
- `App/Screens/BinderView.swift`: `ScrollView(.vertical)` → `LazyVStack(spacing: 16)` of
  `BinderPageView`s, `ForEach(..., id: \.element.key)`, each `.aspectRatio(pageWidth /
  pageHeight, contentMode: .fit)`, with `.scrollTargetLayout()` and `.scrollPosition(id:
  $visibleKey)` (`@State private var visibleKey: PageKey?`), padding 16, background
  `Color(.secondarySystemBackground)`. Free scrolling, no snapping, no zoom.
  - Each page: `.accessibilityIdentifier("binderPage.<index>")`, label from its key ("Overview",
    "Delegated tasks, page <i+1>", "Meeting notes", "Notes", "Added page"), value "Handwritten"
    when `binder.ink[key] != nil`, else "Blank".
  - The scroll view: `.accessibilityIdentifier("binderView")`.
  - Bottom inset: a capsule `Text("Page \(i + 1) of \(n)")`, `i` = index of `visibleKey` (0 when
    nil), identifier `binderPageIndicator`.
  - Top inset: `OmittedTasksBanner(tasks: plan.omittedTodoItems.map(\.text))` when non-empty (the
    banner extracted from `PreviewView` into `App/Screens/OmittedTasksBanner.swift`, identifier
    `omittedTasksBanner` unchanged), and `binder.message` in the same footnote style as
    `AgendaView`'s message inset.
  - Toolbar `.primaryAction`: Button `Label("Share PDF", systemImage: "square.and.arrow.up")`,
    identifier `binderShareButton`, runs `controller.exportBinder()`; a sheet presented while
    `controller.binderExport != nil` shows `ActivityView(url:)` (new `App/Screens/ActivityView.swift`,
    a `UIViewControllerRepresentable` around `UIActivityViewController`), dismiss calls
    `clearBinderExport()`.
- `App/Screens/BinderPageView.swift`: a `UIViewRepresentable` around `BinderPageUIView: UIView`
  holding a `PageBackgroundView` (its `draw(_:)` scales the context by `bounds.width / pageWidth`
  and calls `PageDrawer.draw`; `contentMode = .redraw`; white background) and a `PKCanvasView` on
  top, both filling the bounds. Canvas: `backgroundColor = .clear`, `isOpaque = false`,
  `overrideUserInterfaceStyle = .light`, `drawingPolicy = allowsFingerDrawing ? .anyInput :
  .pencilOnly`, `isScrollEnabled = false`, `contentSize` = the page size in points, and in
  `layoutSubviews` `minimumZoomScale = maximumZoomScale = zoomScale = bounds.width / pageWidth`, so
  strokes are stored in page points whatever the view's size. The coordinator applies `ink`
  only when it differs from the last data it saw, with a flag that makes the delegate ignore the
  resulting `canvasViewDrawingDidChange`; a real change reports `drawing.strokes.isEmpty ? Data() :
  drawing.dataRepresentation()` through `onInkChange`.

### D8. Tools, navigation, links and added pages

- New `AppCore/Sources/Binder/BinderTool.swift`:
  `public enum BinderPen: String, CaseIterable, Sendable { case black, blue, red, green }` with
  `public var color: RGBColor` — black (0, 0, 0), blue (31, 95, 209), red (209, 47, 47),
  green (30, 140, 69) — and `public var name: String` ("Black", "Blue", "Red", "Green");
  `public enum BinderTool: Equatable, Sendable { case pen(BinderPen), eraser }`.
- `RenderPlan.linkTarget(at point: PlanPoint, onPage index: Int) -> Int?`: the target of the last
  `.link` on that page whose rect contains the point (edges included); `nil` for none or an
  index out of range.
- `App/Screens/BinderToolbar.swift`, shown in `BinderView`'s top inset above the banners, one
  row: Overview, Delegated (only when the plan has `.delegated(0)`), Notes | four pen buttons |
  Eraser | Undo, Redo | Add page.

  | Button | Identifier | Accessibility label | Action |
  |---|---|---|---|
  | `square.grid.2x2` | `binderOverviewButton` | Go to overview | scroll to `.overview` |
  | `person.2` | `binderDelegatedButton` | Go to delegated tasks | scroll to `.delegated(0)` |
  | `note.text` | `binderNotesButton` | Go to notes | scroll to `.notes` |
  | filled circle in the pen color | `penButton.<rawValue>` | `<name> pen` | tool = `.pen` |
  | `eraser` | `eraserButton` | Eraser | tool = `.eraser` |
  | `arrow.uturn.backward` | `undoButton` | Undo | undo |
  | `arrow.uturn.forward` | `redoButton` | Redo | redo |
  | `doc.badge.plus` | `addPageButton` | Add page after this one | add page, scroll to it |

  The selected tool's button has `.accessibilityAddTraits(.isSelected)` and a highlighted
  background. The tool starts as `.pen(.black)` and is shared by every page. A pen is
  `PKInkingTool(.pen, color: <sRGB of BinderPen.color>, width: 2)`; the eraser is
  `PKEraserTool(.bitmap, width: 12)`.
- Undo and redo use the `undoManager` of the canvas of the page last drawn on (a `@MainActor`
  `CanvasRegistry` class held in `BinderView`'s `@State`, mapping `PageKey` to a weak
  `PKCanvasView`; pages register in `makeUIView`).
- Links: a `UITapGestureRecognizer` on the canvas with `allowedTouchTypes = [direct]`; its point
  divided by the zoom scale gives a `PlanPoint`; `plan.linkTarget(at:onPage:)` → scroll to that
  page's key.
- Add page: `binder.addPage(after: visibleKey ?? first page's key)`, then scroll to the returned
  key.

### Rejected

- **PKCanvasView over a `PDFView`, or PDF annotations.** The PDF would be regenerated under the
  ink on every render, PDFKit annotations are not PencilKit, and page identity would still be the
  index.
- **Page identity by index.** One added meeting would move every later page's ink.
- **Storing a rendered `RenderPlan` instead of the content.** It is not `Codable`, and the content
  plus theme re-lays out to the same plan.
- **All of a day's ink in one file.** Every stroke would rewrite every page's drawing.
- **Ink file names from the page key** (base64 of the event ID). Google IDs are untrusted and can
  exceed file-name limits; generated names behind an index avoid both.
- **Core Data / SwiftData.** Apple-only, so untestable in AppCore on Linux, for a few files a day.
- **Apple's tool picker.** Many tools the user does not use (decided with the user).
- **Ink on iPhone.** iPad-first per the design doc; the iPhone keeps the preview.
- **Locking a day once it has ink** (decided with the user: re-rendering keeps ink by page).

## ADRs

- **0020** — On iPad the agenda is a binder of native pages: each page of the render plan is drawn
  in the app with a PencilKit canvas on top, and the PDF is only the export, with the ink
  composited in. (Rejects PDFView overlays and PDF annotations, Apple's tool picker, ink on iPhone.)
- **0021** — A binder day is stored on the device in Application Support as the content snapshot
  and theme, plus opaque PencilKit data per stable page key in generated files behind an index;
  re-rendering rebases the day and keeps pages that carry ink. (Rejects index-addressed pages,
  storing the plan, one ink file per day, key-derived file names, Core Data / SwiftData, locking
  a day.)

## Manual steps

None before implementation. After implementation, before the PR merges, on a real iPad with an
Apple Pencil (the simulator has no Pencil and no palm rejection): write and navigate, check
handwriting survives relaunch and works offline, and share the inked PDF through the real
end-of-day path. Step-by-step page: see `manual_steps_artifact` in the manifest.

## Risks and open questions

- **PencilKit inside a SwiftUI `ScrollView`.** With `.pencilOnly` a finger should scroll the outer
  view. If a finger drag neither scrolls nor reaches the canvas, or Pencil strokes scroll the page,
  the p6 worker stops with `status=blocked` and reports what the UI test or simulator showed.
- **Zoom-scaled canvas.** If strokes do not line up with the page after rotation (a stroke drawn
  at the page's center saves far from (297, 421) in page points), stop rather than switching to a
  different coordinate scheme.
- **Shared undo manager.** If a canvas's `undoManager` is `nil` in the UI test, stop and report; do
  not invent another undo mechanism.
- **Two windows on one day** edit the same session; the last stroke saved for a page wins. Accepted.
- **Storage grows** by one folder per started day; nothing is deleted until the end-of-day export
  can confirm a day is done (Stage 2). Accepted for now.
- **Snapshot format.** `BinderDay.formatVersion` is 1; a later change to `AgendaContent`'s fields
  must bump it or decode old days. Not a Stage 1 problem.
- If a test file named in a brief does not exist or a symbol has moved, the worker stops with
  `status=blocked` instead of guessing.

## Implementation manifest

```yaml
plan_slug: binder-ink
feature_branch: feature/binder-ink
max_parallel: 2
manual_steps_artifact: https://claude.ai/artifact/3uYrSCa1Nw3ihoxXTGpCT8
manual_steps_source: docs/binder-ink-plan-manual-steps.html
manual_before: []
manual_after:
  - id: ma1-pencil-on-ipad
    title: Write in the binder with an Apple Pencil on a real iPad
    why: The simulator has no Pencil, pressure or palm rejection; CI draws only with a finger in test mode.
  - id: ma2-offline-and-relaunch
    title: Reopen a started day after a relaunch and with no connection
    why: Proves the Application Support store on a real device and the offline path, which CI only fakes in memory.
  - id: ma3-share-inked-pdf
    title: Share the inked PDF to Drive and run the end-of-day step on it
    why: Checks ink position and colour in the exported PDF in the real end-of-day path.
verify_after_merge:
  - swift test --package-path AppCore
  - python3 -m unittest discover -s scripts/tests
final_checks:
  - docs/binder-ink-plan.md and docs/binder-ink-plan-manual-steps.html are deleted and nothing links to them
  - docs/adr/0020-*.md and docs/adr/0021-*.md exist, are Accepted, and are in docs/adr/README.md's index
  - CHANGELOG.md has [Unreleased] entries and no version heading
  - tests.yml is green on the feature branch head (core, lint, scripts and all three app jobs)
phases:
  - id: p1-page-keys
    title: Stable page keys, meeting IDs and Codable content
    depends_on: []
    complexity: M
    touches:
      - AppCore/Sources/Layout/PageKey.swift
      - AppCore/Sources/Layout/RenderPlan.swift
      - AppCore/Sources/Layout/AgendaLayout.swift
      - AppCore/Sources/Layout/AgendaLayout+Overview.swift
      - AppCore/Sources/Layout/AgendaLayout+Delegated.swift
      - AppCore/Sources/Layout/AgendaLayout+Links.swift
      - AppCore/Sources/Layout/LayoutAudit.swift
      - AppCore/Sources/Layout/ThemeColors.swift
      - AppCore/Sources/Agenda/AgendaContent.swift
      - AppCore/Sources/Draft/AgendaDraft.swift
      - AppCore/Tests/Layout/PageKeyTests.swift
      - AppCore/Tests/Layout/RenderPlanTests.swift
      - AppCore/Tests/Layout/LayoutAuditTests.swift
      - AppCore/Tests/Layout/AgendaLayoutTests.swift
      - AppCore/Tests/Layout/AgendaLayoutDelegatedTests.swift
      - AppCore/Tests/Layout/AgendaLayoutFixtureTests.swift
      - AppCore/Tests/Layout/ThemeColorsTests.swift
      - AppCore/Tests/Agenda/AgendaContentTests.swift
      - AppCore/Tests/Draft/AgendaDraftTests.swift
    brief: |
      Implement Design D1 exactly. Read D1 and "Current state" first.
      1. Create AppCore/Sources/Layout/PageKey.swift with `PageKey` as in D1: the five cases,
         `storageString`, `init?(storageString:)` and single-string Codable. Every public
         declaration gets a `///` comment.
      2. In RenderPlan.swift add `public let key: PageKey` to `PagePlan` and change its init to
         `init(key:chrome:operations:)`.
      3. In AgendaContent.swift add `meetingIDs` (D1 wording and init position) and add `Codable`
         to `TodoItem`, `ScheduleEntry`, `DelegatedItem`, `AgendaContent`. In ThemeColors.swift
         add `Codable` to `Theme`.
      4. In AgendaDraft.content() append `event.id` to a `meetingIDs` array in the same loop that
         appends `event.title`, and pass it to `AgendaContent`.
      5. Key the pages in AgendaLayout.swift (`plan(for:)`, `meetingPage`, `furtherNotesPage`),
         AgendaLayout+Overview.swift (`.overview`), AgendaLayout+Delegated.swift (`.delegated(i)`,
         i = index of the group) and keep the key in AgendaLayout+Links.swift's `PagePlan`
         rebuild. Meeting keys follow D1: `meetingIDs[i]` when present, else "#<i>"; the blank
         page `.meeting("")`. Pass the key through `meetingPage` as a parameter.
      6. In LayoutAudit.swift add `case duplicatePageKey(PageKey)` to `LayoutViolation.Kind` and
         report it on every repeat after the first.
      7. Tests (Swift Testing, existing file style, opening comment per file):
         - new AppCore/Tests/Layout/PageKeyTests.swift: storageString round trip for every case,
           a meeting ID containing ":" and "|", the empty meeting ID, and nil for "", "delegated:x",
           "delegated:-1", "extra:", "overview:x", "unknown"; JSON encode/decode round trip and a
           decode of "\"bogus\"" that throws.
         - AgendaLayoutTests: page keys for no meetings ([.overview, .meeting(""), .notes]), for
           meetings with IDs, and for meetings without IDs ("#0", "#1").
         - AgendaLayoutDelegatedTests: delegated pages are keyed .delegated(0), .delegated(1).
         - AgendaLayoutFixtureTests: every fixture's plan has unique keys (no duplicatePageKey).
         - LayoutAuditTests: two pages with one key give one duplicatePageKey on the second index.
           Update its PagePlan construction to pass keys (use .extra("\(index)")).
         - RenderPlanTests: update the PagePlan construction.
         - AgendaContentTests: Codable round trip of AgendaContentFixtures.typical and .longText.
         - ThemeColorsTests: Theme Codable round trip.
         - AgendaDraftTests: content().meetingIDs equals the IDs of the events with meeting pages,
           in order (extend the test at "The schedule keeps the calendar title...").
      8. No CHANGELOG entry (internal). Run /dod; with no toolchain here, push the phase branch and
         dispatch tests.yml against it, and read core and lint.
      Stop with status=blocked if `PagePlan(` is constructed anywhere not listed in touches.
    acceptance:
      - tests.yml core job green on the phase head, coverage floor passing (100% overall)
      - tests.yml lint job green
      - grep -n "case duplicatePageKey" AppCore/Sources/Layout/LayoutAudit.swift finds one line
      - PageKeyTests, AgendaLayoutTests, AgendaLayoutDelegatedTests, LayoutAuditTests, AgendaContentTests, AgendaDraftTests pass in the core job log
      - tests.yml app jobs green (the app target still compiles with the new PagePlan init)

  - id: p2-binder-layout
    title: BinderDay and BinderLayout (compose, added pages, rebase)
    depends_on: [p1-page-keys]
    complexity: M
    touches:
      - AppCore/Sources/Binder/BinderDay.swift
      - AppCore/Sources/Binder/BinderLayout.swift
      - AppCore/Tests/Binder/BinderDayTests.swift
      - AppCore/Tests/Binder/BinderLayoutTests.swift
      - scripts/check_coverage_floor.py
    brief: |
      Implement Design D2 and D3 exactly, in a new AppCore/Sources/Binder/ folder.
      1. BinderDay.swift: `ExtraPage`, `RetainedPage`, `BinderDay` with `formatVersion = 1`, the
         custom `init(from:)` that throws on another version, and `addPage(after:id:)` per D2.
      2. BinderLayout.swift: `plan(for:)` following D3's seven steps in order, and
         `rebased(_:onto:theme:inkedKeys:)` following its six steps. Keep each step a small
         private function named after it (`composeBase`, `insertRetained`, `insertExtras`,
         `remapLinks`).
      3. Tests with FakeTextMeasurer and TemplateManifest.bundled(), as in
         AppCore/Tests/Layout/AgendaLayoutTests.swift:
         BinderDayTests: addPage after a base page; after an extra (source is inherited, chain
         re-pointed so the new page comes directly after the current one); twice after the same
         page (the second comes first, right after the anchor); Codable round trip; decoding
         version 2 throws.
         BinderLayoutTests:
         - a day with no extras or retained pages equals AgendaLayout's plan (keys, chromes,
           operations).
         - an extra after meeting A sits right after A, copies A's chrome and operations, and its
           header links point at the composed overview and notes indexes.
         - schedule links on the overview point at the right meeting after extras were inserted
           before it.
         - a retained meeting page lands after the last meeting page; a retained delegated page
           when the new content has no delegated pages lands right before notes.
         - an extra whose `after` page is gone lands after its source's run; one whose source is
           gone is dropped.
         - LayoutAudit.violations is empty for plans of days built from every
           AgendaContentFixtures value with two extras and one retained page.
         - rebased: a dropped meeting with ink is retained with the old content; one without ink
           is not; one without ink but with an inked extra is retained; an existing retained page
           keeps its original content; extras whose source survives are kept, others dropped;
           theme and content are the new ones.
      4. Add "AppCore/Sources/Binder/BinderLayout.swift": 100.0 to MODULE_FLOORS in
         scripts/check_coverage_floor.py with the comment "# Places added and kept pages and
         remaps links; an error puts handwriting on the wrong page."
      5. No CHANGELOG entry. Run /dod via a dispatched tests.yml (core, lint, scripts).
      Stop with status=blocked if the composed plan of a D3 example disagrees with D3's text in a
      way the text does not settle.
    acceptance:
      - tests.yml core job green with the coverage floor passing, including the new BinderLayout.swift floor
      - tests.yml lint and scripts jobs green
      - BinderDayTests and BinderLayoutTests appear as passed in the core job log

  - id: p3-binder-store
    title: BinderStore, InMemoryBinderStore and FileBinderStore
    depends_on: [p2-binder-layout]
    complexity: M
    touches:
      - AppCore/Sources/Binder/BinderStore.swift
      - AppCore/Tests/Binder/BinderStoreTests.swift
      - scripts/check_coverage_floor.py
    brief: |
      Implement Design D4 exactly.
      1. BinderStore.swift: `BinderStoreError`, the `BinderStore` protocol, `InMemoryBinderStore`
         (NSLock, same shape and comment as InMemorySettingsStore in
         AppCore/Sources/Settings/AgendaSettings.swift) and `FileBinderStore` with D4's file layout
         and error mapping.
      2. Tests in AppCore/Tests/Binder/BinderStoreTests.swift, run for both stores where the
         behaviour is shared (`@Test(arguments:)` over a factory), each file-store test in a fresh
         `FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)` removed at
         the end:
         - day() is nil when nothing is saved; saveDay then day() returns the equal value.
         - ink is empty for a new day; saveInk for two keys (one a meeting ID with "|" and "/")
           returns both; saving again replaces; empty data removes.
         - two days do not see each other's ink.
         - file store: a garbage day.json throws .unreadable; a garbage index.json throws
           .unreadable; an index entry with an unknown key or a missing file is skipped; a
           directory whose path is an existing regular file makes saveDay and saveInk throw
           .unwritable; page file numbers continue after the highest one in the index.
         - file store writes only under the given directory (list it recursively and check every
           path has the directory as a prefix and only generated names).
      3. Add "AppCore/Sources/Binder/BinderStore.swift": 100.0 to MODULE_FLOORS with the comment
         "# Saves handwriting and the day's snapshot; a wrong branch loses ink."
      4. No CHANGELOG entry. Run /dod via a dispatched tests.yml.
      Stop with status=blocked if FileManager behaves differently on Linux and macOS for a case
      above (the core job runs Linux; the app jobs run AppCore inside the app on macOS).
    acceptance:
      - tests.yml core job green with the coverage floor passing, including the BinderStore.swift floor
      - tests.yml lint and scripts jobs green
      - grep -rn "attributesOfItem\|modificationDate\|creationDate" AppCore/Sources/Binder returns nothing

  - id: p4-binder-session
    title: BinderSession and AgendaController integration
    depends_on: [p3-binder-store]
    complexity: M
    touches:
      - AppCore/Sources/Binder/BinderSession.swift
      - AppCore/Sources/Controller/AgendaController.swift
      - AppCore/Tests/Binder/BinderSessionTests.swift
      - AppCore/Tests/Controller/AgendaControllerTests.swift
      - AppCore/Tests/Controller/AgendaControllerBinderTests.swift
      - AppCore/Tests/Support/FakeRenderer.swift
      - AppCore/Tests/Support/GatedRenderer.swift
      - AppCore/Tests/Support/FailingBinderStore.swift
      - App/Rendering/PDFAgendaRenderer.swift
      - App/AppEnvironment.swift
    brief: |
      Implement Design D5 exactly.
      1. BinderSession.swift per D5 (exact messages from D5).
      2. AgendaController.swift: the `AgendaRendering` change with the `render(_:fileName:)`
         extension; the two init parameters; `binder`, `binderExport`; opening the stored day in
         `load()`; the binder work inside `render()`'s detached task and after its generation
         check; `exportBinder()`, `clearBinderExport()`; `clearLoadedState()`.
      3. Tests support: FakeRenderer implements `render(_:ink:fileName:)` and records `inks:
         [[Data?]]`; GatedRenderer forwards `ink`. New FailingBinderStore (throws a chosen
         BinderStoreError from chosen methods, otherwise in memory).
      4. AgendaControllerTests.swift: `make(...)` gains `binderStore: any BinderStore =
         InMemoryBinderStore()` and passes a deterministic `makeID` (a counter: "id-1", "id-2").
      5. New BinderSessionTests: setInk saves, ignores unchanged data, removes on empty data, sets
         and clears `message`; addPage returns `.extra("id-1")`, puts it after the page, saves
         the day, and sets the message when saving fails; index(of:); inkedKeys.
      6. New AgendaControllerBinderTests:
         - render creates and saves a binder for the day; the session's plan has the base keys.
         - after setInk on a meeting page, rendering again with that meeting switched off keeps
           the page (retained) and the ink.
         - load opens a stored binder for the day before fetching, so it is there when the
           fetch fails (FailingDataSource as in AgendaControllerTests); a day with nothing
           stored has `binder == nil`; setDay to another day swaps the binder.
         - an unreadable store sets "Couldn't read the saved binder for this day."; a failing
           saveDay on render sets the binder message from D5 and leaves the PDF rendered.
         - exportBinder passes the plan and ink in page order and file name "<iso>.pdf", sets
           binderExport; a failing renderer sets "Couldn't create the PDF. Try again.";
           clearBinderExport; signOut clears binder and binderExport.
         - a render overtaken by a load (GatedRenderer, as the existing generation tests) saves
           no binder.
      7. App: PDFAgendaRenderer implements `render(_:ink:fileName:)` and ignores `ink` for now
         (the next phase composites it). AppEnvironment passes `FileBinderStore(directory:
         <Application Support>/Binder)` for live use and `InMemoryBinderStore()` for fixtures.
      8. No CHANGELOG entry yet. Run /dod via a dispatched tests.yml; the app jobs must be green.
      Stop with status=blocked if an existing AgendaControllerTests test changes outcome.
    acceptance:
      - tests.yml core job green with the coverage floor passing (100% overall)
      - tests.yml lint job green
      - tests.yml app (iphone, newest), app (iphone, oldest), app (ipad, newest) green
      - BinderSessionTests and AgendaControllerBinderTests appear as passed in the core job log

  - id: p5-page-drawer
    title: PageDrawer, inked PDF export and app services
    depends_on: [p4-binder-session]
    complexity: M
    touches:
      - App/Rendering/PageDrawer.swift
      - App/Rendering/PDFAgendaRenderer.swift
      - App/AppEnvironment.swift
      - App/MagendaApp.swift
      - AppTests/RenderingTests.swift
    brief: |
      Implement Design D6 exactly.
      1. Create App/Rendering/PageDrawer.swift; move the drawing helpers out of
         PDFAgendaRenderer; add the two `@Entry` environment values.
      2. PDFAgendaRenderer takes `init(drawer:)` and composites ink per D6, using the light
         trait collection.
      3. AppEnvironment: `AppServices`, `makeServices`, `previewController` built from it,
         `previewServices(_:)`. MagendaApp uses `AppServices` and sets the environment values.
         Update every `#Preview` that calls `AppEnvironment.previewController()` only if it
         stops compiling.
      4. AppTests/RenderingTests.swift:
         - change the missingTemplate test to construct `PageDrawer(library:bundle:)`.
         - "Ink is drawn onto its own page": render AgendaContentFixtures.typical's plan with
           `ink: [nil, data]` where data is a PKDrawing of one stroke
           `PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points,
           creationDate: Date()))`, points from (100, 400) to (500, 400) every 20 pt, each
           `PKStrokePoint(location:, timeOffset: 0, size: CGSize(width: 10, height: 10),
           opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)`. Rasterize PDF pages 1 and 2
           at 1x into a UIGraphicsImageRenderer (white fill, flip, `page.draw(with: .mediaBox,
           to:)`) and read the pixel at (300, 400): on page 2 red > 180 and green < 90; on page 1
           not (red > 180 and green < 90).
         - the same with a black stroke while `UITraitCollection(userInterfaceStyle:
           .dark).performAsCurrent` wraps the render: the pixel on page 2 has red, green and blue
           all < 80.
         - "PageDrawer draws a page into a bitmap": draw page 0 of the typical plan into a 595x842
           bitmap; at least one pixel is not white.
      5. No CHANGELOG entry yet. Dispatch tests.yml; all app jobs green.
      Stop with status=blocked if PKDrawing images come out empty in the hosted test on the
      simulator (report the job log), instead of changing the compositing approach.
    acceptance:
      - tests.yml app (iphone, newest), app (iphone, oldest), app (ipad, newest) green, with the three new RenderingTests passed
      - tests.yml lint job green
      - grep -n "performAsCurrent" App/Rendering/PDFAgendaRenderer.swift finds the light trait collection

  - id: p6-binder-view
    title: The iPad binder screen with PencilKit pages and Share PDF
    depends_on: [p5-page-drawer]
    complexity: M
    worker_model: opus
    worker_model_reason: PencilKit inside a SwiftUI ScrollView (gesture routing, zoom-scaled canvas, feedback between the canvas delegate and saved data) cannot be tested on Linux and needs judgement on each simulator run.
    touches:
      - App/Screens/BinderView.swift
      - App/Screens/BinderPageView.swift
      - App/Screens/OmittedTasksBanner.swift
      - App/Screens/ActivityView.swift
      - App/Screens/PreviewView.swift
      - App/Screens/AgendaView.swift
      - AppUITests/BinderUITests.swift
      - AppUITests/PreviewUITests.swift
      - AppUITests/AgendaEditUITests.swift
      - AppUITests/LongTextUITests.swift
      - AppUITests/SettingsUITests.swift
      - AppUITests/AgendaScreenUITests.swift
    brief: |
      Implement Design D7 exactly (D8 is the next phase; start every page with tool
      `.pen(.black)` as a constant and no toolbar).
      1. Extract PreviewView's banner into App/Screens/OmittedTasksBanner.swift
         (`struct OmittedTasksBanner: View { let tasks: [String] }`, same text, identifier
         `omittedTasksBanner`) and use it in PreviewView.
      2. App/Screens/ActivityView.swift per D7.
      3. App/Screens/BinderPageView.swift: BinderPageUIView, PageBackgroundView and the
         coordinator per D7. Inputs: `page: PagePlan`, `pageWidth`, `pageHeight`, `ink: Data?`,
         `allowsFingerDrawing: Bool`, `onInkChange: (Data) -> Void`; the drawer comes from
         `@Environment(\.pageDrawer)`.
      4. App/Screens/BinderView.swift per D7: pages, identifiers, labels and values, page
         indicator, banners, Share PDF and its sheet. `#Preview` uses
         `AppEnvironment.previewServices()` after a render.
      5. AgendaView.detail per D7 (iPad binder or placeholder; iPhone unchanged).
      6. UI tests. In every file listed in touches that waits for "pdfPreview", wait instead for
         `UIDevice.current.userInterfaceIdiom == .pad ? "binderView" : "pdfPreview"` (a private
         static `previewID` per file), and where it checks "shareButton", for `.pad ?
         "binderShareButton" : "shareButton"`. PreviewUITests' iPhone-only test keeps
         "pdfPreview". New AppUITests/BinderUITests.swift (XCTest, file comment like
         PreviewUITests, each test `XCTSkipUnless(... == .pad, "iPad only")`):
         - testRenderShowsTheBinderWithAPageIndicator: render "standard"; `binderView` exists;
           `binderPageIndicator` label matches `^Page 1 of [0-9]+$`.
         - testHandwritingStaysWithTheDay: launch "standard" with "-MagendaFingerDrawing";
           render; `binderPage.0` value "Blank"; drag from normalized (0.3, 0.6) to (0.7, 0.6)
           on it; wait (XCTNSPredicateExpectation, 10 s) for value "Handwritten"; tap
           nextDayButton until `previewPlaceholder` exists (loop as in PreviewUITests); tap
           previousDayButton until `binderView` exists; `binderPage.0` value is "Handwritten".
         - testOverflowShowsTheOmittedTasksBannerOverTheBinder: render "overflow";
           `omittedTasksBanner` exists.
      7. No CHANGELOG entry yet (the retirement phase writes it). Dispatch tests.yml; all app
         jobs green. Never skip, disable or loosen an existing test to get there.
      Stop with status=blocked when: a finger drag in test mode does not change the page value;
      or with ".pencilOnly" the binder cannot be scrolled by a finger in the simulator
      (a swipeUp on binderView leaves binderPage.0 hittable and the indicator unchanged on the
      "overflow" fixture); or a stroke saves at the wrong scale (report the data size and
      bounds). Report what the job log showed.
    acceptance:
      - tests.yml app (iphone, newest), app (iphone, oldest), app (ipad, newest) green
      - BinderUITests' three tests passed on app (ipad, newest) and skipped on the iPhone jobs
      - tests.yml lint job green
      - grep -n "overrideUserInterfaceStyle = .light" App/Screens/BinderPageView.swift finds one line

  - id: p7-binder-tools
    title: Pens, eraser, undo, navigation buttons, links and Add page
    depends_on: [p6-binder-view]
    complexity: M
    touches:
      - AppCore/Sources/Binder/BinderTool.swift
      - AppCore/Sources/Layout/RenderPlan.swift
      - AppCore/Tests/Binder/BinderToolTests.swift
      - AppCore/Tests/Layout/RenderPlanTests.swift
      - App/Screens/BinderToolbar.swift
      - App/Screens/BinderView.swift
      - App/Screens/BinderPageView.swift
      - AppUITests/BinderUITests.swift
    brief: |
      Implement Design D8 exactly.
      1. AppCore/Sources/Binder/BinderTool.swift: `BinderPen` and `BinderTool` with the exact
         colors and names. Tests in AppCore/Tests/Binder/BinderToolTests.swift: every pen's
         color and name, `allCases` order black, blue, red, green.
      2. RenderPlan.linkTarget(at:onPage:) and tests in RenderPlanTests: hit inside, on the edge,
         outside, two overlapping links (last wins), page index out of range, a page without
         links.
      3. App/Screens/BinderToolbar.swift with the table's buttons, identifiers, labels and
         selected trait. BinderPageView takes `tool: BinderTool` and an `onLinkTap: (Int) ->
         Void`, maps the tool to PKInkingTool / PKEraserTool per D8, registers its canvas in a
         `CanvasRegistry`, and adds the direct-touch tap recognizer. BinderView owns the tool,
         the registry, the last-edited key, and scrolls with `withAnimation` by setting
         `visibleKey`.
      4. BinderUITests (iPad only, "standard" unless said):
         - testNotesAndOverviewButtonsMoveBetweenPages: tap binderNotesButton → indicator
           "Page N of N"; tap binderOverviewButton → "Page 1 of N".
         - testAddPageAddsAPageAfterTheCurrentOne: on page 1 tap addPageButton → indicator
           "Page 2 of N+1".
         - testUndoAndRedoAffectTheLastDrawing: with "-MagendaFingerDrawing", draw on
           binderPage.0 → "Handwritten"; undoButton → "Blank"; redoButton → "Handwritten".
         - testPickingAPenSelectsIt: tap penButton.red → it isSelected and penButton.black
           is not; tap eraserButton → it isSelected.
         Link taps are covered by the linkTarget tests in step 2; add no UI test that taps a
         computed position on a page.
      5. No CHANGELOG entry yet. Dispatch tests.yml; all jobs green.
      Stop with status=blocked if a canvas's undoManager is nil in the UI test.
    acceptance:
      - tests.yml core job green with the coverage floor passing
      - tests.yml app (iphone, newest), app (iphone, oldest), app (ipad, newest) green, with the four new BinderUITests passed on iPad
      - tests.yml lint job green

  - id: p8-retire
    title: ADRs, docs, changelog, and retiring the plan
    depends_on: [p7-binder-tools]
    complexity: S
    touches:
      - docs/adr/0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md
      - docs/adr/0021-a-binder-day-is-stored-as-a-content-snapshot-and-ink-per-page-key.md
      - docs/adr/README.md
      - README.md
      - docs/release-testing.md
      - docs/testing-policy.md
      - CHANGELOG.md
      - docs/binder-ink-plan.md
      - docs/binder-ink-plan-manual-steps.html
    brief: |
      1. Write ADR 0020 and ADR 0021 from the plan's "ADRs" bullets, using the template in
         docs/adr/README.md: Context from "Current state", Decision from D6-D8 (0020) and D2-D5
         (0021), Alternatives from "Rejected", Consequences (0021: storage grows until Stage 2's
         export confirms a day; the format version; a started day opens offline), Verification
         naming the source and test files. Status "Accepted — <today>. Implemented." Link only
         to source files, ADRs and commits, never to this plan.
      2. Add both to the index table in docs/adr/README.md.
      3. README.md: a "Binder (iPad)" section after "What goes on the agenda" describing Render
         opening the binder, the toolbar, Add page, Share PDF, ink kept per page on re-render,
         offline once started, and that the iPhone shows the PDF preview; extend the "Layout"
         table rows for App/Screens and AppCore to mention the binder.
      4. docs/release-testing.md: under "What stays manual" add "handwriting with a real Apple
         Pencil on an iPad (pressure, palm rejection), which the simulator does not have"; under
         "Human checks" add "- [ ] On an iPad with an Apple Pencil, write on a binder page,
         relaunch, and the handwriting is still there."
      5. docs/testing-policy.md, "Layout audit and binder rules": one sentence that binder plans
         (added and retained pages) are audited in AppCore too (BinderLayoutTests).
      6. CHANGELOG.md under "## [Unreleased]" → "### Added" (create the subheading if absent):
         - "On iPad, Render opens the day's binder: write on its pages with Apple Pencil, and the
           handwriting is saved with the day, also offline once the day is started."
         - "The binder toolbar has black, blue, red and green pens, an eraser, undo and redo,
           buttons to jump to the overview, delegated tasks and notes, and Add page, which puts a
           blank copy of the current page after it."
         - "Share PDF in the binder shares the day with your handwriting on its pages."
         - "Rendering a day again keeps your handwriting on its pages; a meeting page you wrote
           on stays even when the meeting is no longer on the agenda."
      7. Delete docs/binder-ink-plan.md and docs/binder-ink-plan-manual-steps.html; grep the
         repository for "binder-ink-plan" and remove any remaining link.
      8. Run /dod (dispatched tests.yml for the Swift rows); scripts' no-project-history test
         must pass.
    acceptance:
      - ls docs/adr/0020-*.md docs/adr/0021-*.md lists both; grep -c "Accepted" in each is at least 1
      - grep -n "0020\|0021" docs/adr/README.md finds both index rows
      - grep -rn "binder-ink-plan" . --exclude-dir=.git returns nothing
      - python3 -m unittest discover -s scripts/tests passes
      - grep -n "^## \[[0-9]" CHANGELOG.md shows no new version heading, and "### Added" under [Unreleased] has the four lines
```
