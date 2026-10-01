# Plan: Magenda for iOS, fed by Google Calendar and Google Tasks

## Goal

Port [Magenda](https://github.com/andras-tkcs/magenda) to this iOS app. Today Magenda is a macOS MCP
server: Claude hands it a date, meetings, a daily schedule, to-dos and delegated tasks, and it
renders a daily agenda PDF laid out exactly like its Word template. The iOS app does the same
without Claude: the user signs in with Google, picks a date, reviews what the app pulled from
**Google Calendar** (meetings and the daily schedule) and **Google Tasks** (the to-do list, and the
delegated-tasks page from a second task list), optionally unticks or edits items, taps **Render**,
sees the PDF in an in-app **preview**, and sends it anywhere with the iOS **share** button.
Settings choose the calendars, the two task lists, the font pack and the five accent colors. iOS's
own calendar (EventKit) is not used.

Long event titles and long task names must never break the layout, in the PDF or in the app's
screens: the PDF fits text with fixed rules (shrink, wrap, cut with "…", cap lines, move what does
not fit to a warning), and every rendered plan is checked by an automated layout audit, on Linux
with a deterministic fake font and on simulators with the real fonts.

There is no tracking issue.

## Current state

**This repository** is the iOS app template, unchanged:

- `App/MagendaApp.swift:5` shows `ContentView`; `App/ContentView.swift:8-41` is a placeholder
  (a name field, `Greeting.message(for:)`, and the version row with identifier `version`).
- `AppCore/Sources/Greeting.swift` and `AppCore/Sources/AppInfo.swift` are the only logic;
  `AppCore/Package.swift:9-15` has one target, `AppCore`, path `Sources`, no resources.
- `AppUITests/MainScreenUITests.swift` drives the placeholder (`nameField`, `greeting`, `version`).
- `AppTests/BundleInfoTests.swift` checks the bundle's Info.plist.
- `project.yml`: deployment target iOS 18.0 (`project.yml:9`), bundle ID `name.felhasznalo.magenda`
  (`project.yml:39`), `sources: - App` (everything under `App/` is compiled or copied as a
  resource; `.pdf`, `.ttf`, `.txt` and `.xcprivacy` files become bundle resources at the bundle
  root, so resource file names must be unique).
- `scripts/check_coverage_floor.py:32` — **AppCore's overall line-coverage floor is 100%.** Every
  line a phase adds to `AppCore/Sources/` must be executed by a test. Design error paths so a test
  can reach them (pass the failing input in), rather than leaving an unreachable `throw`.
- No Swift toolchain in cloud sessions by default (`.claude/hooks/session-start.sh`): `swift test`
  and `swift format` results come from a dispatched `tests.yml` (`core`, `lint`); the app's tests
  only ever run on `tests.yml`'s three `app (...)` jobs (`.claude/skills/steward/SKILL.md`).

**The Python Magenda** at commit `3c15fc11fcbcf47bb9907e3a761e6c57d04cd2bd` (clone with
`git clone https://github.com/andras-tkcs/magenda /tmp/magenda && git -C /tmp/magenda checkout
3c15fc11fcbcf47bb9907e3a761e6c57d04cd2bd`; it is public):

- `assets/compiled/chrome.pdf` (78,619 bytes, 4 A4 pages, 595.304 × 841.890 pt): blank vector
  page shells — page 0 overview, 1 delegated tasks, 2 meeting notes, 3 further notes. No themable
  text is baked in. SHA-256 `b2e7eb2aafeed0c17db5f33fe1b8f900d5866194989d890035e458770edabfe3`.
- `assets/compiled/slots.json` (41,700 bytes): where every piece of text goes. Top-level keys
  `template_docx_sha256`, `page_width`, `page_height`, `chrome_pages`
  (`{"overview":0,"delegated_shell":1,"meeting_unit":2,"further_notes":3}`), `header_slots` (20,
  repeated on every page), `page_slots` (`overview` 101, `delegated_shell` 4, `meeting_unit` 2,
  `further_notes` 1) and `delegated` (`table_top_left` `[56.796, 129.5008]`,
  `row_overhead_twips` `995.9998`). A slot is `{id, rect:[x0,y0,x1,y1] (pt, top-left origin),
  role, weight, size_half_points, align, text}`; `text` is fixed content for a static label and
  `null` for a dynamic one. SHA-256
  `ff9ed22ec6aece4d2f0daf764f0a8bd2a1507c813aa0fa5363afee8a9aa902bb`.
- `assets/fonts/`: 15 TTFs, three packs × five weights: `Outfit-`, `Roboto-`, `JetBrainsMono-`
  × `Thin`, `ExtraLight`, `Regular`, `SemiBold`, `Black` (`.ttf`). All SIL OFL 1.1.
- `src/magenda/pdf_assembler.py:662-698` assembles: overview, delegated pages, one page per
  meeting, further notes; header on every page; links. `src/magenda/agenda_state.py` fits text at
  mutation time; `src/magenda/text_fit.py` measures with PIL; `src/magenda/calendar_math.py`
  does the header and "next four weeks" dates; `src/magenda/layout_constants.py` holds the
  numbers; `src/magenda/theme.py` maps a slot's role to a color.

Measured problems in the Python output that this port must not copy (rendered with the commit
above):

1. `text_fit._wrap_words` splits on spaces only, so a 62-character word in a to-do task is drawn
   as one line wider than its cell and runs into the Due column.
2. `pdf_assembler._draw_todo_list` finds and erases the chrome to-do grid by querying the page's
   drawings and leaves partial checkbox strokes next to wrapped tasks.
3. Single-line slots (schedule entries, meeting titles) are cut with no ellipsis, so a reader
   cannot tell the title was cut.
4. `add_todo_tasks` raises when tasks need more than 18 rows; nothing caps a single task's height.

Measured template geometry this plan uses (pt, top-left origin; from `chrome.pdf` page 0 and 1):

| What | Value |
|---|---|
| To-do grid | x 56.7 – 297.0; first row top 144.95; base row height 28.35; 18 base rows; bottom 655.25 |
| To-do ruled line | color `083050`, width 0.75 (17 lines between the 18 chrome rows) |
| To-do checkbox | 6.48 × 6.48 square, centered at x 65.8, stroke `000000`, width 0.75 |
| To-do task / due text boxes | x 97.4 – 216.4 / x 222.4 – 293.0 |
| "TO-DO LIST" / "DAILY SCHEDULE" shaded bands | x 56.7 – 293.15 / x 326.0 – 574.05 |
| Schedule column | ruled lines x 361.05 – 574.1; text x 366.9 – 568.7 (22 half-hour slots, 8:00–18:59) |
| Meeting title | x 236.8 – 566.95 (page content right edge) |
| Header content right edge | 574.1 |
| Delegated table | x 56.796; columns number 30.75, task 173.2, owner 84.45, status 229.0 (right edge 574.196); first row top 129.5008; base row 49.8 (996 twips); rows may reach y 628.2 (footer label y0 634.2 − 6) |
| Delegated chrome line to erase | a 0.5 pt black line at y 179.05 across the table, baked into page 1 |
| Header worst cases (Outfit) | "30 WEDNESDAY" 18 pt Black = 143.7 wide from x 152.95; "SEPTEMBER" 14 pt = 78.8 from x 450.9 (year starts at 536.35) |

## Design

### Architecture

Everything that decides something lives in AppCore (ADR 0007) and is tested on Linux; `App/` only
executes it with Apple frameworks.

```
Google APIs ─▶ GoogleSession (OAuth, refresh) ─▶ GoogleCalendarClient / GoogleTasksClient
                                                   │ Google models
                                                   ▼
Settings ─▶ AgendaController ─▶ AgendaBuilder ─▶ AgendaDraft (review, toggles, edits)
                    │                                │ content()
                    │                                ▼
                    │            AgendaLayout (TemplateManifest + TextMeasuring + Theme)
                    │                                │ RenderPlan (every glyph run positioned)
                    ▼                                ▼
            AgendaRendering (App: PDFAgendaRenderer, CoreText + chrome.pdf) ─▶ PDF file ─▶ Preview + ShareLink
```

AppCore source folders (tests mirror them under `AppCore/Tests/<same folder>/`):
`Agenda/`, `Layout/`, `Google/`, `Settings/`, `Draft/`, `Controller/`, `Resources/`.
App folders: `App/Rendering/`, `App/Resources/Template/`, `App/Resources/Fonts/`, `App/Platform/`,
`App/Screens/`. Shared test fakes go in `AppCore/Tests/Support/`, one file per fake, created by the
phase that introduces the protocol and not edited by later phases.

### Ownership rules every phase follows

- **`CHANGELOG.md`, `README.md`, `docs/*.md`, the ADRs and
  `scripts/check_coverage_floor.py` belong to the last phase only.** Earlier phases do not touch
  them, even for user-visible changes, so parallel phases never conflict there.
- No third-party package. Apple frameworks and the standard library only (`Foundation` and
  `Observation` in AppCore — ADR 0015 records the `Observation` exception to ADR 0007's
  "Foundation at most"; `SwiftUI`, `PDFKit`, `CoreText`, `CoreGraphics`,
  `UIKit`, `AuthenticationServices`, `CryptoKit`, `Security` in `App/`).
- Every `public` AppCore declaration gets a `///` comment; no other comments unless the *why* is
  non-obvious; no plan or phase names anywhere in code (ADR 0008).
- No force unwraps, no `try!`.
- Never log tokens or the user's calendar/task text.
- **Access levels.** Every type, property, function and initializer named in this Design is
  `public`, and every public struct or class gets an explicit `public init` taking all its stored
  properties in declaration order (Swift's memberwise initializer is internal), unless listed
  here as internal: `TextPlacer`, `TextAlignment`, `TemplateGeometry`, and the private helpers of
  `AgendaLayout`'s extensions. Test files use `@testable import AppCore` only when they need one
  of those internal types; otherwise plain `import AppCore`.
- **Coverage-friendly code.** Colors are written as `RGBColor(red: 0x08, green: 0x30, blue: 0x50)`
  literals, never through the failable `RGBColor(hex:)`. A template slot missing from the
  manifest is skipped inside one expression (optional chaining or `compactMap`), never with a
  `guard … else` block whose else-lines only a broken manifest could reach.

### Agenda model (`AppCore/Sources/Agenda/`)

```swift
public struct CalendarDay: Hashable, Comparable, Codable, Sendable {
    public let year: Int; public let month: Int; public let day: Int
    public init?(year: Int, month: Int, day: Int)          // nil for an impossible date
    public init?(isoString: String)                         // "YYYY-MM-DD", first 10 chars of a longer string accepted
    public static func today(in timeZone: TimeZone, now: Date) -> CalendarDay
    public var isoString: String                            // "2026-10-01"
    public var weekdayIndex: Int                            // Monday 0 … Sunday 6
    public var isoWeek: Int                                 // ISO 8601 week number
    public func adding(days: Int) -> CalendarDay
    public func startDate(in timeZone: TimeZone) -> Date    // local midnight
}
```

All arithmetic uses `Calendar(identifier: .gregorian)` with `TimeZone(identifier: "UTC")` internally,
and `Calendar(identifier: .iso8601)` for `isoWeek`.

`CalendarMath` (enum):

- `static let weekdayNames = ["MONDAY", …, "SUNDAY"]`, `monthNames = ["JANUARY", …, "DECEMBER"]`,
  `monthAbbreviations = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
  "Nov", "Dec"]`.
- `static func header(for day: CalendarDay) -> HeaderFields` with `heading` (`"1 THURSDAY"`),
  `calendarWeek` (`"CW 40"`), `month` (`"OCTOBER"`), `year` (`"2026"`), `weekDays: [Int]` (the
  seven day-of-month numbers, Monday to Sunday, of the day's week).
- `static func nextFourWeeks(from day: CalendarDay) -> [WeekRow]`: the day's week and the next
  three; `WeekRow { calendarWeek: String; days: [Int] }` ("CW 40", Monday..Sunday numbers).

`ScheduleSlot` (enum): `static let count = 22`;
`static func index(hour: Int, minute: Int) -> Int?` returns `(hour − 8) * 2 + (minute < 30 ? 0 : 1)`
for hour 8…18 and nil otherwise.

`AgendaContent` — the plain data a PDF is drawn from:

```swift
public enum Cadence: String, Codable, CaseIterable, Sendable { case daily, weekly, monthly
    public var label: String                                // "Daily", "Weekly", "Monthly"
}
public struct TodoItem: Equatable, Sendable { public var text: String; public var due: String }
public struct ScheduleEntry: Equatable, Sendable { public var slot: Int; public var text: String; public var meetingIndex: Int? }
public struct DelegatedItem: Equatable, Sendable {
    public var text: String; public var owner: String; public var cadence: Cadence
    public var marked: Bool; public var status: [String]
}
public struct AgendaContent: Equatable, Sendable {
    public var date: CalendarDay
    public var todoItems: [TodoItem]
    public var schedule: [ScheduleEntry]     // at most one entry per slot; layout uses the first if not
    public var meetings: [String]            // one meeting page each; empty means one blank meeting page
    public var delegated: [DelegatedItem]
}
extension Array where Element == DelegatedItem {
    public func sortedForPage() -> [DelegatedItem]   // stable: marked first, then daily, weekly, monthly
}
```

### Fonts, theme and text fitting (`AppCore/Sources/Layout/`)

```swift
public enum FontPack: String, Codable, CaseIterable, Sendable {
    case outfit, roboto, jetbrainsMono = "jetbrains_mono"
    public var displayName: String        // "Outfit", "Roboto", "JetBrains Mono"
    public var sizeScale: Double          // 1.0, 1.0, 0.9
    public func fontFileName(_ weight: FontWeight) -> String   // "Outfit-Thin", "JetBrainsMono-ExtraLight", …
}
public enum FontWeight: String, Codable, CaseIterable, Sendable {
    case thin, extralight, regular, semibold, black   // file suffixes Thin, ExtraLight, Regular, SemiBold, Black
}
public struct FontSpec: Hashable, Sendable {
    public let pack: FontPack; public let weight: FontWeight; public let size: Double   // size already scaled
    public static func nominal(_ pack: FontPack, _ weight: FontWeight, _ points: Double) -> FontSpec  // size = points * pack.sizeScale
}
public struct FontMetrics: Equatable, Sendable { public let ascent: Double; public let descent: Double   // both positive
    public var lineHeight: Double { ascent + descent } }
public protocol TextMeasuring: Sendable {
    func width(of text: String, font: FontSpec) -> Double
    func metrics(for font: FontSpec) -> FontMetrics
}
public struct RGBColor: Hashable, Codable, Sendable {
    public let red: UInt8; public let green: UInt8; public let blue: UInt8
    public init(red: UInt8, green: UInt8, blue: UInt8)
    public init?(hex: String)     // exactly 6 hex digits after trimming whitespace and one optional leading "#"; case-insensitive
    public var hex: String        // uppercase, no "#": "215E99"
    public static let black, white
}
public enum TextRole: String, Codable, Sendable { case heading, label, accent, notes, weekend, body }
public struct ThemeColors: Equatable, Codable, Sendable {
    public var weekend: RGBColor, heading: RGBColor, label: RGBColor, accent: RGBColor, notes: RGBColor
    // defaults EE0000, 215E99, BF4E14, 3A7C22, 00B0F0, written as RGBColor(red:green:blue:) literals
    public static let `default`
    public func color(for role: TextRole) -> RGBColor   // body is always 000000
}
public struct Theme: Equatable, Sendable { public var fontPack: FontPack = .outfit; public var colors: ThemeColors = .default }
```

`ThemeColors` encodes each color as its hex string; decoding an invalid or missing color falls back
to that color's default (never fails).

`TextFitter` (struct, `init(measurer: any TextMeasuring)`), the only place text is fitted:

- `static func normalized(_ text: String) -> String`: every run of whitespace or control
  characters (newline, tab, `\r`, other `Character.isWhitespace`) becomes one space; leading and
  trailing spaces removed.
- `func ellipsized(_ text: String, font: FontSpec, maxWidth: Double) -> String`: the longest prefix
  of whole `Character`s (so an emoji or a ZWJ family is never split), with trailing spaces removed,
  such that `prefix + "…"` measures ≤ `maxWidth`; returns `prefix + "…"`, or `""` if even `"…"`
  does not fit. Always appends the ellipsis (U+2026).
- `func singleLine(_ text: String, font: FontSpec, maxWidth: Double) -> String`: `normalized(text)`;
  returned unchanged if it fits, else `ellipsized`.
- `func wrap(_ text: String, font: FontSpec, maxWidth: Double, maxLines: Int) -> [String]`:
  `normalized(text)`; empty gives `[]`. Greedy by words split on `" "`. A word wider than
  `maxWidth` on its own is broken at `Character` boundaries: take the longest prefix that fits (at
  least one `Character`), emit it as a line, continue with the rest (this also handles CJK text
  with no spaces). If the result has more than `maxLines` lines, keep the first `maxLines − 1` and
  make the last one `ellipsized(remaining lines joined with " ")`.
- `func downsizeOrWrap(_ text: String, pack: FontPack, weight: FontWeight, maxPoints: Double,
  minPoints: Double, maxWidth: Double, maxLines: Int) -> FittedText` (`FittedText { lines:
  [String]; font: FontSpec }`): for nominal sizes `maxPoints, maxPoints − 1, …, minPoints`, return
  the first size at which `normalized(text)` fits on one line; otherwise `wrap` at `minPoints`.
  Fonts are built with `FontSpec.nominal`.

### Template manifest and render plan (`AppCore/Sources/Layout/`, `AppCore/Sources/Resources/`)

`AppCore/Sources/Resources/slots.json` is a byte-for-byte copy of the Python repo's
`assets/compiled/slots.json` (SHA-256 above). `Package.swift` becomes:

```swift
.target(name: "AppCore", path: "Sources", resources: [.copy("Resources/slots.json")]),
```

```swift
public struct TemplateSlot: Equatable, Decodable, Sendable {
    public let id: String; public let rect: PlanRect; public let role: TextRole
    public let weight: FontWeight; public let sizeHalfPoints: Int; public let align: String; public let text: String?
    public var points: Double { Double(sizeHalfPoints) / 2 }
}
public struct TemplateManifest: Equatable, Sendable {
    public let pageWidth: Double; public let pageHeight: Double
    public let headerSlots: [TemplateSlot]
    public let pageSlots: [String: [TemplateSlot]]    // "overview", "delegated_shell", "meeting_unit", "further_notes"
    public let delegatedTableTopLeft: PlanPoint
    public let delegatedRowOverhead: Double            // row_overhead_twips / 20
    public init(data: Data) throws(TemplateError)      // explicit CodingKeys for the snake_case keys (never keyDecodingStrategy, which would also rewrite page_slots' dictionary keys); a missing key or bad value throws .malformed
    public init(contentsOf url: URL?) throws(TemplateError)   // nil URL throws .missing; unreadable throws .missing
    public static func bundled() throws(TemplateError) -> TemplateManifest   // contentsOf: Bundle.module.url(forResource: "slots", withExtension: "json")
    public func slot(_ id: String) -> TemplateSlot?    // searches headerSlots then every page's slots
}
public enum TemplateError: Error, Equatable { case missing, malformed }
```

`PlanRect` decodes from a 4-number JSON array. `rect` values are used as-is; the "padded box" of a
slot is `PlanRect(x0: x0 − 1.5, y0: y0 − 3, x1: x1 + 1.5, y1: y1 + 4)`.

```swift
public struct PlanPoint: Equatable, Sendable { public let x: Double; public let y: Double }
public struct PlanRect: Equatable, Sendable {
    public let x0: Double; public let y0: Double; public let x1: Double; public let y1: Double
    public var width: Double; public var height: Double
    public func intersects(_ other: PlanRect, tolerance: Double) -> Bool   // overlap deeper than tolerance on both axes
    public func contains(_ other: PlanRect, tolerance: Double) -> Bool
}
public enum ChromePage: Int, Sendable { case overview = 0, delegated = 1, meeting = 2, furtherNotes = 3 }
public struct TextRun: Equatable, Sendable {
    public let text: String; public let font: FontSpec; public let color: RGBColor
    public let x: Double; public let baseline: Double              // left end of the line, baseline y
    public let width: Double; public let ascent: Double; public let descent: Double   // as measured
    public let container: PlanRect                                 // the box it must stay inside
    public var bounds: PlanRect { PlanRect(x0: x, y0: baseline − ascent, x1: x + width, y1: baseline + descent) }
}
public enum DrawOperation: Equatable, Sendable {
    case fill(PlanRect, RGBColor)
    case stroke(PlanRect, RGBColor, lineWidth: Double)
    case line(from: PlanPoint, to: PlanPoint, RGBColor, lineWidth: Double)
    case text(TextRun)
    case link(PlanRect, targetPage: Int)
}
public struct PagePlan: Equatable, Sendable { public let chrome: ChromePage; public var operations: [DrawOperation] }
public struct RenderPlan: Equatable, Sendable {
    public let pageWidth: Double; public let pageHeight: Double
    public var pages: [PagePlan]
    public var omittedTodoItems: [TodoItem]
}
```

Operations are executed in array order, on top of the chrome page.

`TextPlacer` (struct, `init(measurer:)`):
`func place(_ lines: [String], font: FontSpec, color: RGBColor, in box: PlanRect, container: PlanRect,
alignment: TextAlignment, indents: [Double] = []) -> [TextRun]` with `enum TextAlignment { case left,
center }`. Metrics `m = measurer.metrics(for: font)`; block height `lines.count × m.lineHeight`;
`top = box.y0 + (box.height − blockHeight) / 2`; line *i* has `baseline = top + m.ascent + i ×
m.lineHeight`; left: `x = box.x0 + (indents[i] if present else 0)`; center: `x = box.x0 +
(box.width − width) / 2`. Empty strings produce no run.

### Layout rules (`AgendaLayout`)

`public struct AgendaLayout: Sendable { init(manifest: TemplateManifest, measurer: any TextMeasuring,
theme: Theme); func plan(for content: AgendaContent) -> RenderPlan }`.

Constants live in `TemplateGeometry` (enum, `AppCore/Sources/Layout/TemplateGeometry.swift`) with
the values from the "Measured template geometry" table above. Names: `contentRight = 574.1`,
`meetingTitleRight = 566.95`, `todoGridX0 = 56.7`, `todoGridX1 = 297.0`, `todoTop = 144.95`,
`todoBaseRow = 28.35`, `todoBottom = 655.25`, `todoLineColor = 083050`, `todoLineWidth = 0.75`,
`checkboxSize = 6.48`, `checkboxCenterX = 65.8`, `checkboxLineWidth = 0.75`, `todoTaskBox = 97.4…216.4`,
`todoDueBox = 222.4…293.0`, `todoBand = 56.7…293.15`, `scheduleBand = 326.0…574.05`,
`scheduleTextX0 = 366.9`, `scheduleTextX1 = 568.7`, `delegatedColumns` (number 30.75, task 173.2,
owner 84.45, status 229.0), `delegatedCellInset = 5.4`, `delegatedMaxY = 628.2`,
`delegatedErase = PlanRect(56.2, 178.3, 574.6, 179.8)`, `markedFill = D6FCEC`,
`delegatedThickBorder = 3.0`, `delegatedThinBorder = 0.5`, `todoErase = PlanRect(55.7, 146.0, 298.0, 656.5)`.
p4 adds the non-delegated constants; p5 adds the delegated ones (`delegatedColumns`,
`delegatedCellInset`, `delegatedMaxY`, `delegatedErase`, `markedFill`, `delegatedThickBorder`,
`delegatedThinBorder`), so no constant exists before a test reads it.

Every text run takes its color from `theme.colors.color(for: slot.role)` (or the role named below),
its font from `FontSpec.nominal(theme.fontPack, weight, points)`.

**Page order:** overview, then the delegated pages (zero or more), then one meeting page per
`content.meetings` entry (exactly one blank one when the list is empty), then further notes.
`PagePlan.chrome` is the matching `ChromePage`.

**Header (every page):** every `manifest.headerSlots` slot. Static slots draw their `text`;
dynamic ones draw `header.heading` → `HeaderFields.heading`, `header.cw` → `calendarWeek`,
`header.month`, `header.year`, `header.dayno.<i>` → `weekDays[i]`. Placement: left alignment in the
slot's padded box; the container is the padded box widened to `x1 = contentRight`. No fitting
(fixed vocabulary; the audit proves it fits).

**Overview page, in this order:**

1. `fill(todoErase, white)` — removes the chrome to-do grid's lines and checkboxes.
2. Static overview slots (`text != nil`): `todo.label` centered in `todoBand` × the slot's padded
   y-range; `schedule.label` centered in `scheduleBand` × padded y-range; every other static slot
   left in its padded box, container widened to `contentRight`.
3. To-do rows from `y = todoTop`, for each `TodoItem` in order:
   - `fitted = downsizeOrWrap(text, pack, .thin, maxPoints: 12, minPoints: 9, maxWidth: 119.0,
     maxLines: 4)`; `lh = metrics(fitted.font).lineHeight`; `baseLines = max(1, floor(28.35 / lh))`;
     `rowHeight = 28.35 + max(0, fitted.lines.count − baseLines) × lh`.
   - If `y + rowHeight > todoBottom + 0.5`, this item and every later one go to
     `omittedTodoItems` and the loop stops (order is kept; no later item jumps ahead).
   - Unless it is the first row: `line((56.7, y) → (297.0, y), 083050, 0.75)`.
   - `stroke(square of side 6.48 centered at (65.8, y + rowHeight / 2), black, 0.75)`.
   - Task lines left in box `(97.4, y, 216.4, y + rowHeight)` (container = that box), role `body`.
   - Due: `singleLine(due, thin 12 pt, maxWidth: 70.6)` left in `(222.4, y, 293.0, y + rowHeight)`.
   - `y += rowHeight`.
   Then blank rows of 28.35 (separator line + checkbox, no text) while `y + 28.35 ≤ todoBottom + 0.5`.
4. Schedule: for each `ScheduleEntry`, `singleLine(text, thin 12 pt, maxWidth: 201.8)` left in
   the padded box of `schedule.slot.<slot>`, with x0 = 366.9 − 1.5 and container
   `(365.4, padded y0, 568.7, padded y1)`.
5. Next four weeks: `next4weeks.week.<w>.cw` ← `WeekRow.calendarWeek`, `next4weeks.week.<w>.day.<i>`
   ← `days[i]`, left in padded boxes, container widened to `contentRight`.

**Meeting page:** static `meeting.label`; `meeting.title` ← `singleLine(title, extralight 20 pt,
maxWidth: 566.95 − 236.8)`, left in its padded box with container x1 = 566.95. A blank meeting page
draws only the label.

**Further notes page:** static `further_notes.label` only.

**Delegated pages** (only when `content.delegated` is non-empty), items in `sortedForPage()` order:

- Column x: number starts at 56.796; each next column starts where the previous one ends.
- Per item: `task = downsizeOrWrap(text, pack, .extralight, maxPoints: 11, minPoints: 9, maxWidth:
  173.2 − 10.8, maxLines: 6)`; task cell lines are `[cadence.label] + task.lines`, all at
  `task.font`. `owner = singleLine(owner, extralight 11 pt, maxWidth: 84.45 − 10.8)`. Status: with
  `bullet = "• "` and `bw = width("• ", extralight 11 pt)`, each status string is wrapped with
  `maxWidth: 229.0 − 10.8 − bw` and `maxLines` = what is left of a 10-line budget; its first line
  is drawn as `"• " + line` at indent 0, continuation lines as the bare line at indent `bw`. When
  the budget runs out and status strings remain, the last line drawn keeps its prefix and indent
  (`"• "` at indent 0 if it was a first line, bare at indent `bw` otherwise) and its text becomes
  `ellipsized(lastLineText + " " + remaining strings joined with " ", maxWidth: 229.0 − 10.8 − bw)`.
- `lh = metrics(extralight 11 pt).lineHeight`; `contentLines = max(1 + task.lines.count,
  statusLines.count, 1)`; `rowHeight = 49.8 + max(0, contentLines − 2) × lh`.
- Pagination: rows start at y 129.5008; a row that would end below 628.2 starts a new page (a page
  always takes at least one row).
- Each delegated page, in order: `fill(delegatedErase, white)`; header labels "Task & cadence",
  "Owner", "Status" centered across their full column width, y-range from the padded
  `delegated.header.task/owner/status` slots, each slot's own weight and size (black 14 pt), role
  `label`, container = that centering box; static `delegated.footer_label`; then
  per row: if marked `fill(row rect, D6FCEC)`; top border `line` across the table, 3.0 for the
  page's first row and 0.5 otherwise, black; number (running count across pages, starting at 1)
  centered in the number column, black weight 14 pt, role `label`; task lines left in the task
  column inset by 5.4; owner centered in the owner column inset by 5.4; status lines left in the
  status column inset by 5.4, with the indents above; all body text role `body`. After the last
  row of every page except the last delegated page: a closing 0.5 black line.

**Links** (appended last on each page):

- On every page except the first: `link(bounds of the "<< Overview" run, targetPage: 0)`.
- On every page except the last: `link(bounds of the "Notes >>" run, targetPage: lastIndex)`.
- On the overview: for each schedule entry with a `meetingIndex`, `link(bounds of that entry's run,
  targetPage: 1 + delegatedPageCount + meetingIndex)`.

### Layout audit (`AppCore/Sources/Layout/LayoutAudit.swift`)

`public enum LayoutAudit { static func violations(in plan: RenderPlan) -> [LayoutViolation] }`,
`LayoutViolation: Equatable, Sendable` with `page: Int` and `kind`:

- `.outsideContainer(text: String)` — a run's `bounds` is not inside its `container` (tolerance 0.5).
- `.outsidePage(text: String)` — a run's container is not inside `0…pageWidth × 0…pageHeight`.
- `.overlap(String, String)` — two runs on the same page whose `bounds` intersect by more than 0.5.
- `.badLinkTarget(Int)` — a link to a page index that does not exist.
- `.noPages` — the plan has no pages.

`AgendaContentFixtures` (public enum, `AppCore/Sources/Layout/AgendaContentFixtures.swift`), all
for `CalendarDay(year: 2026, month: 9, day: 30)` (a Wednesday in September, the widest month and
weekday names):

| Name | Content |
|---|---|
| `typical` | 3 to-dos ("Call the bank" due "Today"; "Send the slides" due "28 Sep"; "Book flights" due ""), schedule slot 2 "Team sync" (meetingIndex 0) and slot 5 "1:1 with Anna" (meetingIndex 1), meetings ["Team sync", "1:1 with Anna"], delegated ("Hire a designer", owner "Anna", weekly, marked, status ["Interviews scheduled", "Two candidates left"]) and ("Renew the office lease", owner "Ben", monthly, not marked, status ["Waiting for the landlord"]) |
| `longText` | for i in 0…5 with s = `longStrings[i]`: to-do (s, due s); schedule entry slot `i * 4`, text s, meetingIndex i; meeting s; delegated (text s, owner s, cadence `Cadence.allCases[i % 3]`, marked `i % 2 == 0`, status [s, `longStrings[(i + 1) % 7]`, `longStrings[(i + 2) % 7]`]) |
| `overflow` | 30 to-dos (`longStrings[0]`, due "Today"); 22 schedule entries, slot i, text `longStrings[1]`, meetingIndex i; 25 meetings `"Meeting <i>: " + longStrings[0]`; 40 delegated (text `"Delegated task <i>: " + longStrings[0]`, owner "Alexandra Montgomery-Smith", cadence `Cadence.allCases[i % 3]`, marked `i % 4 == 0`, status five copies of `longStrings[0]`) |
| `empty` | nothing but the date |

`public static let longStrings: [String]`, exactly:

0. `"Quarterly business review with the extended leadership team, finance, legal and the regional sales directors to agree next year's targets and hiring plan"`
1. `String(repeating: "Supercalifragilistic", count: 10)` (200 characters, no space)
2. `String(repeating: "🎉🚀 Launch party 👩‍👩‍👧‍👦👩🏽‍💻 ", count: 8)`
3. `String(repeating: "四半期業務レビュー会議と来年度の目標設定および採用計画", count: 3)`
4. `"مراجعة الأعمال الفصلية مع فريق القيادة الموسع والمالية والشؤون القانونية والمبيعات"`
5. `"Line one\nline two\ttabbed   and   spaced"`
6. `String(repeating: "word ", count: 400)`

### Google sign-in (`AppCore/Sources/Google/`)

OAuth 2.0 authorization code with PKCE (RFC 7636, S256), Google "iOS" client type (no client
secret), presented by `ASWebAuthenticationSession` in `App/`. Scopes, exactly:
`https://www.googleapis.com/auth/calendar.readonly` and
`https://www.googleapis.com/auth/tasks.readonly`.

```swift
public enum HTTPMethod: String, Sendable { case get = "GET", post = "POST" }
public struct HTTPRequest: Equatable, Sendable { public var method: HTTPMethod; public var url: URL
    public var headers: [String: String]; public var body: Data?; public var timeout: TimeInterval = 30 }
public struct HTTPResponse: Equatable, Sendable { public var status: Int; public var body: Data }
public protocol HTTPClient: Sendable { func send(_ request: HTTPRequest) async throws -> HTTPResponse }   // throws only for transport failure
public protocol SHA256Hashing: Sendable { func sha256(_ data: Data) -> Data }

public struct GoogleOAuthConfiguration: Equatable, Sendable {
    public init?(clientID: String)       // trimmed; must match ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$
    public let clientID: String
    public var redirectScheme: String    // "com.googleusercontent.apps." + the part before ".apps.googleusercontent.com"
    public var redirectURI: String       // redirectScheme + ":/oauth2redirect"
    public static let scopes: [String]
}
public struct AuthorizationRequest: Equatable, Sendable { public let url: URL; public let state: String; public let verifier: String }
public struct OAuthTokens: Codable, Equatable, Sendable { public let accessToken: String; public let refreshToken: String; public let expiresAt: Date }
public enum GoogleOAuth {
    static func authorizationRequest(configuration:, random: inout some RandomNumberGenerator, hasher: any SHA256Hashing) -> AuthorizationRequest
    static func authorizationCode(from callback: URL, for request: AuthorizationRequest, configuration:) throws -> String
    static func tokenRequest(code: String, verifier: String, configuration:) -> HTTPRequest
    static func refreshRequest(refreshToken: String, configuration:) -> HTTPRequest
    static func revokeRequest(token: String) -> HTTPRequest
    static func tokens(from response: HTTPResponse, previousRefreshToken: String?, requireScopes: Bool, now: Date) throws -> OAuthTokens
}
```

- Verifier: 64 characters drawn from `A–Z a–z 0–9 - . _ ~` with `random`; state: 32 characters from
  the same set. Challenge: base64url without padding of `hasher.sha256(Data(verifier.utf8))`. Test
  vector (RFC 7636 appendix B): verifier `dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk` → challenge
  `E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`.
- Authorization URL: `https://accounts.google.com/o/oauth2/v2/auth` built with `URLComponents`,
  query items in this order: `client_id`, `redirect_uri`, `response_type=code`, `scope` (the two
  scopes joined by one space), `code_challenge`, `code_challenge_method=S256`, `state`.
- Callback: scheme must equal `redirectScheme`, `state` must equal the request's state, else
  `.authorizationFailed`. An `error` query item `access_denied` → `.authorizationCancelled`; any
  other `error` → `.authorizationFailed`; no `code` → `.authorizationFailed`.
- Token endpoint `https://oauth2.googleapis.com/token`, `POST`,
  `Content-Type: application/x-www-form-urlencoded`. Bodies (form-encoded, each value
  percent-encoded so only `A–Z a–z 0–9 - . _ ~` stay literal): exchange
  `code, client_id, redirect_uri, code_verifier, grant_type=authorization_code`; refresh
  `client_id, refresh_token, grant_type=refresh_token`. Revoke: `POST
  https://oauth2.googleapis.com/revoke`, `Content-Type: application/x-www-form-urlencoded`, body
  `token=<token>` encoded the same way.
- `tokens(from:)`: status 200 with JSON `access_token` (non-empty), `expires_in` (number),
  `token_type` equal to `Bearer` ignoring case, optional `refresh_token`, optional `scope`.
  `expiresAt = now + expires_in`. Refresh token = response's, else `previousRefreshToken`, else
  `.unexpectedResponse`. With `requireScopes`, `scope` must contain both scopes (space-separated)
  or `.missingScopes`; without it, a present `scope` missing one is also `.missingScopes`. Status
  400 with `"error": "invalid_grant"` → `.signedOut`; any other non-200 → `.authorizationFailed`;
  undecodable JSON → `.unexpectedResponse`.

```swift
public enum GoogleAPIError: Error, Equatable, Sendable {
    case notConfigured, authorizationCancelled, authorizationFailed, missingScopes, signedOut
    case forbidden, rateLimited, network, unexpectedResponse
    public var userMessage: String
}
```

| Case | `userMessage` |
|---|---|
| `notConfigured` | Google sign-in isn't set up in this build. |
| `authorizationCancelled` | Google sign-in was cancelled. |
| `authorizationFailed` | Google sign-in didn't complete. Try again. |
| `missingScopes` | Magenda needs to see your calendars and tasks. Sign in again and allow both. |
| `signedOut` | Your Google sign-in expired. Sign in again. |
| `forbidden` | Google refused the request. Check that the Calendar and Tasks APIs are enabled for this app. |
| `rateLimited` | Google is limiting requests right now. Try again in a minute. |
| `network` | Couldn't reach Google. Check your connection and try again. |
| `unexpectedResponse` | Google sent an unexpected response. Try again later. |

```swift
public protocol TokenStore: Sendable { func load() throws -> OAuthTokens?; func save(_ tokens: OAuthTokens) throws; func delete() throws }
public protocol AuthorizedHTTPSending: Sendable { func send(_ request: HTTPRequest) async throws -> HTTPResponse }
public protocol GoogleAccount: Sendable {
    func isSignedIn() async -> Bool
    func signIn(authenticate: @escaping @Sendable (URL, String) async throws -> URL) async throws   // (authorization URL, callback scheme) → callback URL
    func signOut() async
}
public actor GoogleSession: GoogleAccount, AuthorizedHTTPSending {
    public init(configuration: GoogleOAuthConfiguration, http: any HTTPClient, tokens: any TokenStore,
                hasher: any SHA256Hashing, now: @escaping @Sendable () -> Date)
}
public struct UnconfiguredGoogleAccount: GoogleAccount   // never signed in; signIn throws .notConfigured
```

`GoogleSession` behaviour:

- `isSignedIn()`: `tokens.load()` returns a value; a thrown load counts as signed out.
- `signIn`: builds an `AuthorizationRequest` with `SystemRandomNumberGenerator`, calls
  `authenticate(request.url, configuration.redirectScheme)`. A thrown `GoogleAPIError` is
  rethrown; any other error becomes `.authorizationFailed`. Then parses the callback, exchanges
  the code (`requireScopes: true`), saves the tokens (a save error becomes `.authorizationFailed`).
  An `HTTPClient` throw becomes `.network`.
- `send(_:)`: loads tokens (none → `.signedOut`). If `expiresAt − 60 s ≤ now()`, refreshes first.
  Concurrent callers share one in-flight refresh (`Task` stored on the actor). Adds
  `Authorization: Bearer <access token>`. Response 401 → refresh once and retry once; a second 401
  deletes the tokens and throws `.signedOut`. A refresh that returns `.signedOut` deletes the
  tokens. Status mapping after that: 2xx returned; 403 `.forbidden`; 429 `.rateLimited`; anything
  else `.unexpectedResponse`; transport throw `.network`.
- `signOut()`: if tokens exist, sends the revoke request for the refresh token and ignores its
  result or error; then deletes the tokens (ignoring a delete error).

### Google Calendar and Tasks clients (`AppCore/Sources/Google/`)

```swift
public struct GoogleCalendar: Equatable, Identifiable, Sendable { public let id: String; public let title: String; public let isPrimary: Bool }
public enum EventStart: Equatable, Sendable { case allDay(CalendarDay), timed(Date) }
public struct GoogleEvent: Equatable, Sendable {
    public let calendarID: String; public let id: String; public let iCalUID: String?
    public let title: String?; public let status: String?; public let start: EventStart
    public let eventType: String?; public let selfResponse: String?
}
public struct GoogleTaskList: Equatable, Identifiable, Sendable { public let id: String; public let title: String }
public struct GoogleTask: Equatable, Sendable {
    public let id: String; public let title: String?; public let notes: String?
    public let status: String; public let due: CalendarDay?; public let position: String?
}
public protocol GoogleDataSource: Sendable {
    func calendars() async throws -> [GoogleCalendar]
    func events(calendarID: String, on day: CalendarDay, timeZone: TimeZone) async throws -> [GoogleEvent]
    func taskLists() async throws -> [GoogleTaskList]
    func openTasks(listID: String) async throws -> [GoogleTask]
}
public struct GoogleCalendarClient: Sendable { public init(sender: any AuthorizedHTTPSending) }  // calendars(), events(...)
public struct GoogleTasksClient: Sendable { public init(sender: any AuthorizedHTTPSending) }     // taskLists(), openTasks(listID:)
public struct LiveGoogleDataSource: GoogleDataSource { public init(calendar: GoogleCalendarClient, tasks: GoogleTasksClient) }
```

Requests (all `GET`, URLs built with `URLComponents` / `URL.appending(path:)`, never string
concatenation of IDs):

- Calendars: `https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader&maxResults=250`.
  `title = summaryOverride ?? summary ?? id`; `isPrimary = primary == true`.
- Events: `https://www.googleapis.com/calendar/v3/calendars/<calendarId>/events` with
  `timeMin` = the day's local midnight, `timeMax` = the next day's local midnight, both written
  in UTC with a `Z` suffix (`2026-09-29T22:00:00Z`) so the query never contains a `+` (which
  Google would read as a space); use a new `ISO8601DateFormatter` per call with time zone UTC
  (the formatter is not `Sendable`, so never a shared `static let`). `singleEvents=true`,
  `orderBy=startTime`, `maxResults=250`, `timeZone=<identifier>`. `start.dateTime` (RFC 3339,
  with or without fractional seconds) → `.timed`; `start.date` → `.allDay`; neither → the event
  is skipped. `selfResponse` = the `responseStatus` of the attendee with `"self": true`.
- Task lists: `https://tasks.googleapis.com/tasks/v1/users/@me/lists?maxResults=100`.
- Tasks: `https://tasks.googleapis.com/tasks/v1/lists/<listId>/tasks?showCompleted=false&showHidden=false&maxResults=100`.
  `due` → `CalendarDay(isoString:)` of its first 10 characters.
- Every list follows `nextPageToken` (`pageToken=` query item) for at most 10 pages.
- A body that does not decode throws `.unexpectedResponse`; errors from the sender pass through.
- Recorded responses for tests: `AppCore/Tests/Google/Fixtures/*.json`, read with
  `Bundle.module.url(forResource:withExtension:subdirectory: "Fixtures")` from the test target
  (`resources: [.copy("Google/Fixtures")]` on the test target in `Package.swift`).

### From Google data to a draft (`AppCore/Sources/Settings/`, `AppCore/Sources/Draft/`)

```swift
public struct AgendaSettings: Equatable, Codable, Sendable {
    public var fontPack: FontPack = .outfit
    public var colors: ThemeColors = .default
    public var calendarIDs: [String] = []        // empty means the primary calendar
    public var todoListID: String? = nil         // nil means the first task list
    public var delegatedListID: String? = nil    // nil means no delegated page
    public var theme: Theme { get }
}
public protocol SettingsStore: Sendable { func load() -> AgendaSettings; func save(_ settings: AgendaSettings) }
public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {   // state guarded by an NSLock; a comment says so
    public init(_ settings: AgendaSettings = AgendaSettings())
}
```

Decoding is tolerant: an unknown `fontPack` becomes `.outfit`; a missing field takes its default.

`DelegatedNotes.parse(_ notes: String?) -> DelegatedNotes` (`owner`, `cadence`, `marked`,
`status: [String]`, `warning: String?`). Notes format, documented for users in the README:

```
Owner: Anna
Cadence: weekly
Marked: yes
Interviews scheduled
Two candidates left
```

Lines are split on `\n`. Leading lines matching `^\s*(owner|cadence|marked)\s*:\s*(.*)$`
(case-insensitive) are fields, in any order, until the first non-empty line that does not match;
blank lines among them are skipped. Every remaining non-empty trimmed line is one status bullet.
Defaults: owner `""`, cadence daily, marked false. Cadence values daily/weekly/monthly ignoring
case; anything else gives daily and `warning = "Unknown cadence “<value>” — shown as Daily."`.
Marked is true for `yes`, `y`, `true`, `x`, `1` ignoring case.

```swift
public struct DraftEvent: Equatable, Identifiable, Sendable {
    public let id: String                 // "<calendarID>|<event id>"
    public let originalTitle: String; public var title: String
    public let start: Date; public let timeText: String   // "HH:mm", 24-hour, local
    public let scheduleSlot: Int?         // nil when the event starts before 8:00 or after 18:59
    public var includesMeetingPage: Bool  // true by default
}
public struct DraftTask: Equatable, Identifiable, Sendable {
    public let id: String; public let originalText: String; public var text: String
    public let dueText: String; public var isIncluded: Bool   // true by default
}
public struct DraftDelegated: Equatable, Identifiable, Sendable {
    public let id: String; public let originalText: String; public var text: String
    public let owner: String; public let cadence: Cadence; public let marked: Bool
    public let status: [String]; public let warning: String?; public var isIncluded: Bool
}
public struct AgendaDraft: Equatable, Sendable {
    public let date: CalendarDay
    public var events: [DraftEvent]; public var tasks: [DraftTask]; public var delegated: [DraftDelegated]
    public mutating func setTitle(_ text: String, forEvent id: String)       // normalized; blank → originalTitle
    public mutating func setText(_ text: String, forTask id: String)
    public mutating func setText(_ text: String, forDelegated id: String)
    public mutating func setMeetingPage(_ on: Bool, forEvent id: String)
    public mutating func setIncluded(_ on: Bool, forTask id: String)
    public mutating func setIncluded(_ on: Bool, forDelegated id: String)
    public func content() -> AgendaContent
}
public struct AgendaBuilder: Sendable {
    public init(timeZone: TimeZone)
    public func draft(for day: CalendarDay, events: [GoogleEvent], tasks: [GoogleTask], delegated: [GoogleTask]) -> AgendaDraft
}
```

Builder rules:

- Events: drop `status == "cancelled"`, `.allDay` starts, `eventType` in `workingLocation`,
  `outOfOffice`, `birthday`, `selfResponse == "declined"`, and events whose local start day is not
  `day`. Deduplicate by `iCalUID ?? id`, keeping the first (input order is calendar order). Sort by
  start, then title. Title = `TextFitter.normalized(title ?? "")`, or `(No title)` when empty.
- To-do tasks: `status == "needsAction"`, normalized title non-empty, `due == nil || due <= day`.
  Order: dated tasks by due ascending (ties by `position`, then input order), then undated tasks
  by `position` (nil last, then input order). `dueText`: nil → `""`; equal to `day` → `Today`;
  otherwise `"<day> <monthAbbreviation>"` (`28 Sep`).
- Delegated: `status == "needsAction"`, normalized title non-empty, notes parsed as above, input
  order (the layout sorts).
- `content()`: schedule groups every event that has a `scheduleSlot` (toggles do not remove events
  from the schedule) by slot, in start order; text = their titles joined with `" / "`;
  `meetingIndex` set only when the slot holds exactly one event and that event has a meeting page,
  and then it is that event's position within `meetings` (not within `events`).
  `meetings` = titles of events with `includesMeetingPage`, in order. `todoItems` = included tasks
  `(text, dueText)`. `delegated` = included items.

### Controller (`AppCore/Sources/Controller/`)

```swift
public struct RenderedAgenda: Equatable, Sendable { public let url: URL; public let pageCount: Int; public let omittedTasks: [String] }
public protocol AgendaRendering: Sendable { func render(_ plan: RenderPlan, fileName: String) async throws -> URL }

@MainActor @Observable
public final class AgendaController {
    public enum Status: Equatable { case starting, signedOut, signingIn, loading, ready, rendering, failed(String) }
    public private(set) var status: Status = .starting
    public private(set) var day: CalendarDay
    public private(set) var draft: AgendaDraft?
    public private(set) var settings: AgendaSettings
    public private(set) var calendars: [GoogleCalendar] = []
    public private(set) var taskLists: [GoogleTaskList] = []
    public private(set) var rendered: RenderedAgenda?
    public private(set) var message: String?          // last error or notice shown on the current screen
    public init(account: any GoogleAccount, data: any GoogleDataSource, settingsStore: any SettingsStore,
                measurer: any TextMeasuring, renderer: any AgendaRendering, manifest: TemplateManifest,
                timeZone: TimeZone, today: CalendarDay)
    public func start() async            // signed in → load(); else .signedOut
    public func signIn(authenticate: @escaping @Sendable (URL, String) async throws -> URL) async
    public func signOut() async          // → .signedOut; clears draft, calendars, taskLists, rendered
    public func load() async
    public func setDay(_ day: CalendarDay) async      // then load()
    public func updateSettings(_ change: (inout AgendaSettings) -> Void) async   // save; load() if calendarIDs, todoListID or delegatedListID changed
    public func updateDraft(_ change: (inout AgendaDraft) -> Void)
    public func render() async
}
```

- `load()`: `.loading`, `message = nil`, `rendered = nil`. Fetch calendars and task lists. Calendars
  to read = `settings.calendarIDs` that still exist in the list, or `["primary"]` when that is
  empty. To-do list = `todoListID` if it exists, else the first list, else none. Delegated list =
  `delegatedListID` if it exists and differs from the to-do list, else none. Fetch events for each
  calendar in that order, then the open tasks of each list, build the draft, `.ready`.
  `GoogleAPIError.signedOut` → `.signedOut` with `message` = its `userMessage`; any other
  `GoogleAPIError` → `.failed(userMessage)`; any other error → `.failed(unexpectedResponse's message)`.
- `signIn`: `.signingIn`; success → `load()`; `authorizationCancelled` → `.signedOut`, `message`
  nil; other errors → `.signedOut` with the error's `userMessage`.
- `updateDraft` and `updateSettings` clear `rendered`.
- `render()`: needs a draft. `.rendering`; plan = `AgendaLayout(manifest:, measurer:, theme:
  settings.theme).plan(for: draft.content())`; url = `renderer.render(plan, fileName: "Agenda
  <day.isoString>.pdf")`; `rendered = RenderedAgenda(url, plan.pages.count,
  plan.omittedTodoItems.map(\.text))`; `.ready`. A renderer error → `.ready` with
  `message = "Couldn't create the PDF. Try again."`.

Fixtures for UI tests and SwiftUI previews (AppCore, public):

- `GoogleFixture: String, CaseIterable` — `standard`, `longText`, `overflow`, `empty`;
  `init?(launchArguments: [String])` reads the value after `-MagendaFixture`.
- `FixtureGoogleDataSource(fixture)`: calendars `GoogleCalendar(id: "primary", title: "Work",
  isPrimary: true)` and `GoogleCalendar(id: "family", title: "Family", isPrimary: false)`; task
  lists `GoogleTaskList(id: "todo", title: "My Tasks")` and `GoogleTaskList(id: "delegated",
  title: "Delegated")`. Events exist only on calendar `primary`, built on the requested day in the
  requested time zone, status `confirmed`, ids `e0`, `e1`, …; tasks have ids `t0`, `t1`, … and
  status `needsAction`; `openTasks(listID: "todo")` returns the to-dos, `"delegated"` the
  delegated tasks, any other ID `[]`.
  - `standard`: events 09:00 "Team sync", 10:30 "1:1 with Anna", 13:00 "Lunch with Sam",
    19:00 "Dinner"; to-dos "Call the bank" (due the requested day), "Send the slides" (due two
    days earlier), "Book flights" (no due); delegated "Hire a designer" with notes
    `"Owner: Anna\nCadence: weekly\nMarked: yes\nInterviews scheduled\nTwo candidates left"` and
    "Renew the office lease" with notes `"Owner: Ben\nCadence: monthly\nWaiting for the landlord"`.
  - `longText`: events at 08:00, 09:30, 11:00, 13:30, 15:00, 17:30 titled `longStrings[0]` …
    `longStrings[5]`; to-dos titled `longStrings[0]` … `longStrings[5]`, no due; three delegated
    tasks titled `longStrings[0]`, `longStrings[1]`, `longStrings[3]`, each with notes
    `"Owner: " + longStrings[1] + "\nCadence: weekly\n" + longStrings[0] + "\n" + longStrings[2]`.
  - `overflow`: 22 events, event *i* at hour `8 + i / 2`, minute `(i % 2) * 30`, titled
    `longStrings[1]`; 30 to-dos titled `longStrings[0]`, no due; 40 delegated tasks titled
    `"Delegated task <i>: " + longStrings[0]` with notes `"Owner: Alexandra Montgomery-Smith\nCadence: "`
    + `["daily", "weekly", "monthly"][i % 3]` + five lines of `longStrings[0]`, each preceded by `"\n"`.
  - `empty`: the calendars and lists above, no events, no tasks.
- `FixtureGoogleAccount: GoogleAccount` (actor) — `init(signedIn: Bool)`; `signIn` succeeds without
  calling `authenticate`.

### App (`App/`)

**Template and fonts** (`App/Resources/Template/chrome.pdf`, `App/Resources/Fonts/*.ttf`,
`App/Resources/Fonts/OFL-Outfit.txt`, `OFL-Roboto.txt`, `OFL-JetBrainsMono.txt`): byte copies of
the Python repo's files at the pinned commit; the OFL texts are
`https://raw.githubusercontent.com/google/fonts/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/{outfit,roboto,jetbrainsmono}/OFL.txt`.

**Rendering** (`App/Rendering/`):

- `FontLibrary` (final class): `init(bundle: Bundle) throws` loads all 15 TTFs once with
  `CTFontManagerCreateFontDescriptorFromData`; a missing file or a nil descriptor throws
  `FontLibraryError.missingFont(String)`. `func font(_ spec: FontSpec) -> CTFont`. Fonts are never
  registered system-wide. It and `CoreTextMeasurer` hold only immutable CoreText objects; if the
  compiler rejects their `Sendable` conformance, mark them `@unchecked Sendable` with a comment
  saying why (immutable, and CoreText fonts are thread-safe).
- `CoreTextMeasurer: TextMeasuring`: width = `CTLineGetTypographicBounds` of a `CTLine` made from
  the string with that `CTFont` (CoreText's font fallback covers emoji, CJK and Arabic); metrics
  = `CTFontGetAscent` / `CTFontGetDescent`.
- `PDFAgendaRenderer: AgendaRendering`: `UIGraphicsPDFRenderer` with bounds 595.304 × 841.890.
  Per page: draw `chrome.pdf`'s page `chrome.rawValue + 1` with `saveGState`,
  `translateBy(x: 0, y: pageHeight)`, `scaleBy(x: 1, y: -1)`, `drawPDFPage`, `restoreGState`;
  then the operations in order: fills, strokes and lines with `CGContext` in UIKit's top-left
  coordinates; text with `saveGState`, `translateBy(x: x, y: baseline)`, `scaleBy(x: 1, y: -1)`,
  `textPosition = .zero`, `CTLineDraw` of a `CTLine` built exactly as the measurer builds it,
  `restoreGState`; links with
  `UIGraphicsAddPDFContextDestinationAtPoint("page-<n>", .zero)` at the start of every page and
  `UIGraphicsSetPDFContextDestinationForRect("page-<target>", rect)`. Writes to
  `FileManager.default.temporaryDirectory/Agendas/<fileName>`, replacing an existing file.

**Platform** (`App/Platform/`):

- `URLSessionHTTPClient: HTTPClient` (ephemeral configuration, `timeoutInterval` from the request).
- `KeychainTokenStore: TokenStore`: generic password, service `name.felhasznalo.magenda.google`
  (an init parameter, so tests use their own), account `oauth-tokens`, JSON-encoded
  `OAuthTokens`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- `CryptoKitHasher: SHA256Hashing` (`SHA256.hash(data:)`).
- `UserDefaultsSettingsStore: SettingsStore` (key `agendaSettings`, JSON; the `UserDefaults`
  instance is an init parameter).
- `BundledGoogleClient.configuration(bundle:) -> GoogleOAuthConfiguration?` reads
  `GoogleOAuthClientID.txt` from the bundle.
- `App/PrivacyInfo.xcprivacy`: `NSPrivacyTracking` false, no tracking domains, no collected data
  types, accessed API type `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`.
- `App/GoogleOAuthClientID.txt` holds the iOS OAuth client ID (one line). The user fills it in on
  the plan branch before implementation (manual step mb3). It is a public identifier: Google ships
  it inside every iOS app; there is no client secret.

**Wiring** (`App/AppEnvironment.swift`):
`static func makeController(arguments: [String], bundle: Bundle) throws -> AgendaController`. It
loads `TemplateManifest.bundled()` and `FontLibrary(bundle:)` first (their errors propagate).
With `GoogleFixture(launchArguments: arguments)` non-nil: `FixtureGoogleAccount(signedIn:
!arguments.contains("-MagendaSignedOut"))`, `FixtureGoogleDataSource(fixture)`,
`InMemorySettingsStore(AgendaSettings(todoListID: "todo", delegatedListID: "delegated"))` (other
fields default; `AgendaSettings` has a public init with every field defaulted),
`TimeZone.current`, today 2026-09-30. Otherwise:
`GoogleSession(configuration:http:tokens:hasher:now:)` with `URLSessionHTTPClient`,
`KeychainTokenStore`, `CryptoKitHasher` and `{ Date() }` as both the account and the sender of a
`LiveGoogleDataSource`. When `BundledGoogleClient.configuration(bundle:)` returns nil, the account
is `UnconfiguredGoogleAccount()` and the data source `FixtureGoogleDataSource(.empty)` (nothing
loads while signed out, and sign-in shows "Google sign-in isn't set up in this build.").
Shared by both: `UserDefaultsSettingsStore(defaults: .standard)`, `CoreTextMeasurer`,
`PDFAgendaRenderer`, `TimeZone.current`, `CalendarDay.today(in: .current, now: Date())`.
`MagendaApp` holds the controller in `@State`, injects it with `.environment`, calls `start()` in
`.task`, and shows `RootView(appInfo:)` with the `AppInfo` it already builds today; `RootView`
passes it to `AgendaView(appInfo:)`, which passes it to `SettingsView(appInfo:)` for the version
row. If `makeController` throws, it shows only
`Text("Couldn't load the agenda template. Reinstall Magenda.")` with identifier `templateError`.

**Screens** (`App/Screens/`, one per file, each with an `ID` enum and a `#Preview` using the
fixtures):

| File | Shows | Identifiers |
|---|---|---|
| `RootView.swift` | `.starting` → `ProgressView`; `.signedOut`/`.signingIn` → SignInView; otherwise AgendaView in a `NavigationStack` | — |
| `SignInView.swift` | Title "Magenda"; text "Make a printable agenda from your Google Calendar and Google Tasks."; button "Sign in with Google" (disabled while signing in); `message` below in secondary style | `signInButton`, `signInMessage` |
| `AgendaView.swift` | Toolbar: `DatePicker` "Date" (date only), Settings gear (label "Settings"), "Render" button (disabled unless `.ready` with a draft). Sections "Schedule and meetings", "To-do list", "Delegated" (only when a delegated list is set), each row described below. `.loading` shows `ProgressView`; `.failed(message)` shows the message and a "Try again" button; `.rendering` shows `ProgressView("Rendering…")`. Pull to refresh calls `load()`. After a successful render it pushes PreviewView. | `agendaScreen` (the List), `datePicker`, `settingsButton`, `renderButton`, `loadingIndicator`, `errorMessage`, `retryButton`, `eventRow.<n>`, `eventToggle.<n>`, `eventScheduleNote.<n>`, `taskRow.<n>`, `taskToggle.<n>`, `delegatedRow.<n>`, `delegatedToggle.<n>` (n = 0-based position) |
| `EditTextSheet.swift` | Title "Edit text"; multi-line `TextField` (1…5 lines); "Done" saves, "Cancel" discards; caption "Changes only affect this agenda. Nothing is changed in Google." | `editField`, `editDone`, `editCancel` |
| `PreviewView.swift` | `PDFKitView` (a `UIViewRepresentable` around `PDFView`, `autoScales`, single page continuous); toolbar `ShareLink(item: url)` labelled "Share PDF"; when `omittedTasks` is non-empty a banner "<n> task(s) didn't fit on the to-do list and were left out:" followed by their texts, `lineLimit(3)` | `pdfPreview`, `shareButton`, `omittedTasksBanner` |
| `SettingsView.swift` | Sections "Calendars" (multi-select checkmarks; footnote "None selected uses your primary calendar."), "Task lists" (Picker "To-do list"; Picker "Delegated tasks" with "None" first and the to-do list excluded), "Look" (three rows "Outfit", "Roboto", "JetBrains Mono", each a button showing a checkmark when selected; five rows "Weekend", "Date heading", "Section labels", "Accent", "Notes heading", each a color swatch and a hex `TextField` that saves on submit when `RGBColor(hex:)` accepts it and otherwise shows "Use six hex digits, like 215E99."; button "Reset colors"), "Account" (button "Sign out"), "About" (version row as today, footnote "Fonts: Outfit, Roboto and JetBrains Mono, under the SIL Open Font License 1.1.") | `calendarRow.<n>`, `todoListPicker`, `delegatedListPicker`, `fontOption.<rawValue>` (`fontOption.outfit`, `fontOption.roboto`, `fontOption.jetbrains_mono`), `colorField.<role>` (weekend, heading, label, accent, notes), `colorError`, `resetColorsButton`, `signOutButton`, `version` |

Rows (event, task, delegated): an `HStack` whose leading part is a `Button` (identifier
`eventRow.<n>` / `taskRow.<n>` / `delegatedRow.<n>`) holding the title `Text` with `.lineLimit(2)`
and `.truncationMode(.tail)` and a secondary line (event: `timeText`, plus a
`Text("Not on the schedule")` with identifier `eventScheduleNote.<n>` when `scheduleSlot` is nil;
task: `dueText`; delegated: cadence label, owner, and `warning` in orange when set); tapping it
opens `EditTextSheet`. That button's `accessibilityLabel` is the full, untruncated title. The
trailing part is a `Toggle` (identifier `eventToggle.<n>` / `taskToggle.<n>` /
`delegatedToggle.<n>`) with visible label "Notes page" (events) or "Include" (tasks, delegated)
and accessibility label "Notes page for <title>" / "Include <title>". The row is not combined into
one accessibility element.

### Rejected alternatives

- **Render on a server with the Python Magenda.** Needs hosting, sends the user's calendar off the
  device, and fails offline. Rejected for on-device rendering from the same compiled template.
- **Redraw the template natively in SwiftUI/CoreGraphics.** Hundreds of hand-copied coordinates
  that drift from `template.docx`. Rejected: vendor `chrome.pdf` + `slots.json`, the exact artifacts
  the Python runtime uses, and redraw only the parts that change.
- **Let CoreText/TextKit fit text into rectangles at draw time.** Untestable on Linux, and frame
  setters silently drop what does not fit. Rejected for an AppCore layout that positions every
  run against a measuring protocol and an audit that checks every run.
- **Copy Python's fitting rules unchanged** (cut without ellipsis, wrap only at spaces, raise on a
  full to-do list). Rejected for the reasons under "Measured problems".
- **Query chrome drawings at render time to find the to-do grid** (as Python does). Not possible
  with `CGPDFDocument`, and it left artifacts. Rejected for one white fill over the measured grid
  area and a full redraw.
- **The GoogleSignIn SDK.** A third-party dependency for what `ASWebAuthenticationSession` plus
  ~150 lines of PKCE do; ADR-gated by CONTRIBUTING.md. Rejected.
- **EventKit (iOS Calendar).** The user asked for Google's APIs; EventKit has no Google Tasks and
  would need a calendar permission prompt. Rejected.
- **Delegated tasks stored in the app.** Not synced and invisible to Google; the user chose a
  Google Tasks list with a notes format.
- **The client ID in `project.yml` or an Info.plist key.** Custom Info.plist keys need a plist
  file that `GENERATE_INFOPLIST_FILE` does not manage, and `ASWebAuthenticationSession` needs no
  URL type registration. A one-line bundled text file is simpler and editable on GitHub.
- **Narrower `calendar.calendarlist.readonly` + `calendar.events.readonly` scopes.** Two scopes
  for the same read access; one well-known `calendar.readonly` is enough and still read-only.

## ADRs

The last phase writes these (next free number is 0011):

- **0011** — The agenda PDF is drawn on the device from the Python Magenda's compiled template
  (`chrome.pdf` and `slots.json`, plus its OFL fonts), vendored from `andras-tkcs/magenda` at a
  pinned commit; updating the template means copying both files again.
- **0012** — Text layout is computed in AppCore against a `TextMeasuring` protocol into a fully
  positioned `RenderPlan` with fixed fitting rules (ellipsis, character-level breaking, line caps,
  omitted to-dos reported), and every plan is checked by `LayoutAudit`; `App/` only executes it.
- **0013** — Google sign-in is OAuth 2.0 with PKCE implemented in AppCore and presented by
  `ASWebAuthenticationSession`, not the GoogleSignIn SDK; tokens live only in the Keychain; scopes
  are read-only `calendar.readonly` and `tasks.readonly`; the public iOS client ID ships in
  `App/GoogleOAuthClientID.txt`.
- **0014** — The agenda's inputs are Google Calendar and Google Tasks, not EventKit; delegated tasks
  come from a chosen Google Tasks list whose notes carry `Owner:`, `Cadence:` and `Marked:` lines.
- **0015** — AppCore may import the toolchain's `Observation` module (it ships with Swift on Linux)
  so the `@Observable` controller is tested on Linux; this amends ADR 0007's "Foundation at most".
  Rejected: keeping the controller in `App/` (untested on Linux) or a hand-written observer.

## Manual steps

Step-by-step page: https://claude.ai/artifact/DZxBnKphSDuV8PDN5XCo6t (source
`docs/google-agenda-pdf-plan-manual-steps.html`).

- **Before** (`manual_before`): create a Google Cloud project with the Calendar and Tasks APIs
  enabled; configure the OAuth consent screen in Testing mode with your Google account as a test
  user and the two read-only scopes; create an iOS OAuth client for `name.felhasznalo.magenda`
  and commit its client ID into `App/GoogleOAuthClientID.txt` on `plan/google-agenda-pdf`.
- **After** (`manual_after`): on a real iPhone, sign in, render, preview and share; check long
  titles with real Google data and at the largest text size; check the delegated page from a real
  Tasks list; set the App Store Connect privacy answers.

## Risks and open questions

- **`Bundle.module` resources on Linux.** If `swift test` cannot find `slots.json` or the test
  fixtures on the `core` job, the phase stops with `status=blocked` and quotes the error; it does
  not inline the JSON as a Swift string.
- **`Observation` on the Linux toolchain.** If `import Observation` (the controller) fails on
  the `core` job, stop blocked with the compiler output.
- **Static template text overlapping under a font pack.** If `LayoutAudit` reports an overlap or
  overflow between two static labels (not text this plan fits) with the real fonts on the
  simulator, that is a template finding: stop blocked with the violation list rather than moving
  coordinates.
- **PDF link destinations.** If `UIGraphicsSetPDFContextDestinationForRect` links do not appear
  as `PDFAnnotation`s with a destination in `PDFKit`, stop blocked with what was observed.
- **Google consent in Testing mode** expires refresh tokens after 7 days; the app then shows
  "Your Google sign-in expired. Sign in again." That is expected until the OAuth app is published
  and verified, which is outside this plan.
- **The client ID file.** If `App/GoogleOAuthClientID.txt` on the feature branch still holds the
  placeholder, the app builds and shows "Google sign-in isn't set up in this build." Phases do not
  edit the file; the `scripts/tests` check added in p13 fails until mb3 is done.
- **Coverage at 100%.** A phase that cannot reach a line from a test restructures the code so the
  failing input can be injected; it never lowers a floor.

## Implementation manifest

```yaml
plan_slug: google-agenda-pdf
feature_branch: feature/google-agenda-pdf
max_parallel: 2
manual_steps_artifact: https://claude.ai/artifact/DZxBnKphSDuV8PDN5XCo6t
manual_steps_source: docs/google-agenda-pdf-plan-manual-steps.html
manual_before:
  - id: mb1-google-cloud-project
    title: Create a Google Cloud project and enable the Google Calendar API and the Google Tasks API
    why: Every live request the app makes (p8b's clients, wired into the app by p14a) fails with 403 until both APIs are enabled.
    done_when: Both APIs show "API enabled" on their Google Cloud console pages for the new project.
  - id: mb2-oauth-consent-screen
    title: Configure the OAuth consent screen (External, Testing) with your Google account as a test user and the calendar.readonly and tasks.readonly scopes
    why: Google refuses sign-in for an unconfigured consent screen or a user who is not a test user; the manual_after device checks need it.
    done_when: The Audience page shows Publishing status "Testing" with your address under Test users, and Data access lists both read-only scopes.
  - id: mb3-ios-client-id
    title: Create an iOS OAuth client for bundle ID name.felhasznalo.magenda and commit its client ID into App/GoogleOAuthClientID.txt on plan/google-agenda-pdf
    why: p13's scripts test and the app's live sign-in read this file; with the placeholder the app reports that sign-in isn't set up.
    done_when: git show origin/plan/google-agenda-pdf:App/GoogleOAuthClientID.txt prints one line matching ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$
manual_after:
  - id: ma1-device-sign-in-render-share
    title: On a real iPhone, sign in with Google, render today's agenda, check the preview and share the PDF to Files, AirDrop or Print
    why: ASWebAuthenticationSession against real Google, the Keychain on a device and the share sheet cannot run in CI.
  - id: ma2-long-text-real-data
    title: With real Google data containing very long titles, an unbroken long word, emoji and the largest Dynamic Type size, check the app's lists and the rendered PDF
    why: Confirms the audited layout with real accounts and real fonts as a person sees them.
  - id: ma3-delegated-list
    title: Create a Google Tasks list with tasks in the Owner/Cadence/Marked notes format, choose it as the delegated list and check the delegated page
    why: Confirms the notes format against the real Google Tasks app.
  - id: ma4-app-store-privacy
    title: Set App Store Connect's App Privacy answers to "Data Not Collected"
    why: The app reads Google data only on the device and sends nothing to the developer; App Store Connect needs the answer before review.
verify_after_merge:
  - swift test --package-path AppCore --enable-code-coverage && python3 scripts/check_coverage_floor.py "$(swift test --package-path AppCore --show-codecov-path)"
final_checks:
  - docs/google-agenda-pdf-plan.md and docs/google-agenda-pdf-plan-manual-steps.html are deleted and nothing links to them
  - ADRs 0011, 0012, 0013, 0014 and 0015 exist, are Accepted, and are in docs/adr/README.md's index
  - CHANGELOG.md has [Unreleased] entries and no version heading
  - AppCore/Sources/Greeting.swift, App/ContentView.swift and AppUITests/MainScreenUITests.swift are gone
  - App/GoogleOAuthClientID.txt holds a real client ID (python3 -m unittest discover -s scripts/tests passes)
phases:
  - id: p1-calendar-and-content
    title: Calendar math, schedule slots and the agenda content model in AppCore
    depends_on: []
    complexity: S
    touches:
      - AppCore/Sources/Agenda/CalendarDay.swift
      - AppCore/Sources/Agenda/CalendarMath.swift
      - AppCore/Sources/Agenda/AgendaContent.swift
      - AppCore/Tests/Agenda/CalendarDayTests.swift
      - AppCore/Tests/Agenda/CalendarMathTests.swift
      - AppCore/Tests/Agenda/AgendaContentTests.swift
    brief: |
      Read the plan's Design sections "Architecture", "Ownership rules every phase follows" and
      "Agenda model". The Python originals are src/magenda/calendar_math.py and
      src/magenda/agenda_state.py at the pinned commit (see "Current state").
      1. Create AppCore/Sources/Agenda/CalendarDay.swift with `CalendarDay` exactly as specified.
      2. Create AppCore/Sources/Agenda/CalendarMath.swift with `CalendarMath`, `HeaderFields`,
         `WeekRow` and `ScheduleSlot` exactly as specified.
      3. Create AppCore/Sources/Agenda/AgendaContent.swift with `Cadence`, `TodoItem`,
         `ScheduleEntry`, `DelegatedItem`, `AgendaContent` and `sortedForPage()`.
      4. Tests (Swift Testing, one @Suite per behavior, file header comment as in
         AppCore/Tests/GreetingTests.swift): CalendarDayTests (invalid dates such as 2026-02-30
         return nil; isoString round trip; init(isoString:) accepts "2026-10-01T00:00:00.000Z" and
         rejects "2026-1-1" and ""; weekdayIndex for 2026-10-01 is 3; isoWeek is 53 for 2026-12-31
         and 1 for 2027-01-04; adding(days:) across a month and a year end; today(in:now:) for a
         fixed Date in two time zones that disagree on the day; startDate(in:)).
         CalendarMathTests, parameterized: header(for: 2026-10-01) gives "1 THURSDAY", "CW 40",
         "OCTOBER", "2026", [28,29,30,1,2,3,4]; nextFourWeeks(from: 2026-10-01) gives CW 40–43 with
         the Python output's day numbers (28…4, 5…11, 12…18, 19…25); a year boundary
         (2026-12-30 → CW 53, 1, 2, 3). ScheduleSlot.index: (8,0)→0, (8,29)→0, (8,30)→1, (18,59)→21,
         (7,59)→nil, (19,0)→nil. AgendaContentTests: Cadence labels; sortedForPage keeps input
         order inside each (marked, cadence) group.
      5. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "CalendarDayTests|CalendarMathTests|AgendaContentTests" passes (or the core job of a tests.yml run dispatched on the phase branch)
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p2-text-fitting
    title: Fonts, theme colors and the text fitter in AppCore
    depends_on: []
    complexity: M
    touches:
      - AppCore/Sources/Layout/Fonts.swift
      - AppCore/Sources/Layout/ThemeColors.swift
      - AppCore/Sources/Layout/TextMeasuring.swift
      - AppCore/Sources/Layout/TextFitter.swift
      - AppCore/Tests/Layout/FontsTests.swift
      - AppCore/Tests/Layout/ThemeColorsTests.swift
      - AppCore/Tests/Layout/TextFitterTests.swift
      - AppCore/Tests/Support/FakeTextMeasurer.swift
    brief: |
      Read the plan's Design sections "Ownership rules every phase follows" and "Fonts, theme and
      text fitting". The Python original is src/magenda/text_fit.py; its known defects are listed
      under "Measured problems" and must not be copied.
      1. AppCore/Sources/Layout/Fonts.swift: FontPack, FontWeight, FontSpec (with nominal(_:_:_:)).
      2. AppCore/Sources/Layout/ThemeColors.swift: RGBColor (with init?(hex:), hex, black, white),
         TextRole, ThemeColors (Codable as hex strings, tolerant decoding), Theme.
      3. AppCore/Sources/Layout/TextMeasuring.swift: FontMetrics and the TextMeasuring protocol.
      4. AppCore/Sources/Layout/TextFitter.swift: TextFitter and FittedText with normalized,
         ellipsized, singleLine, wrap and downsizeOrWrap exactly as specified. Iterate over
         Characters, never unicode scalars or UTF-16 units.
      5. AppCore/Tests/Support/FakeTextMeasurer.swift (internal to the test target, not public):
         `struct FakeTextMeasurer: TextMeasuring` with width = Double(text.count) * font.size * 0.5
         (Character count) and metrics ascent 0.8 * size, descent 0.2 * size. Later phases reuse it
         unchanged.
      6. Tests with FakeTextMeasurer: normalized (newlines, tabs, repeated spaces, leading and
         trailing); ellipsized never splits "👩‍👩‍👧‍👦" (a prefix ends before or after the whole
         family), returns "" when maxWidth is below the width of "…", strips trailing spaces before
         the "…"; singleLine returns short text unchanged and long text ending in "…" whose width
         ≤ maxWidth; wrap breaks a 200-character word into lines that each fit, wraps CJK text with
         no spaces, caps at maxLines with an ellipsized last line, returns [] for blank text;
         downsizeOrWrap picks the largest fitting size between max and min and wraps at min when
         nothing fits; FontPack.fontFileName for all 15 pairs ("JetBrainsMono-ExtraLight" etc.),
         sizeScale 0.9 for jetbrainsMono, raw value "jetbrains_mono"; RGBColor(hex:) accepts
         "215e99", "#215E99", " 215E99 " and rejects "215E9", "215E99F", "GGGGGG", "##215E99";
         ThemeColors default values, color(for: .body) is 000000, JSON round trip, and decoding
         {"weekend":"nope"} keeps the default weekend color.
      7. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "FontsTests|ThemeColorsTests|TextFitterTests" passes
      - the core job's coverage floor step passes at 100%
      - the lint job passes
      - grep -rn "unicodeScalars\|utf16" AppCore/Sources/Layout/TextFitter.swift prints nothing
  - id: p3-template-manifest-and-plan
    title: Vendor slots.json; manifest decoding, render-plan types and text placement
    depends_on: [p1-calendar-and-content, p2-text-fitting]
    complexity: M
    touches:
      - AppCore/Package.swift
      - AppCore/Sources/Resources/slots.json
      - AppCore/Sources/Layout/TemplateManifest.swift
      - AppCore/Sources/Layout/RenderPlan.swift
      - AppCore/Sources/Layout/TextPlacer.swift
      - AppCore/Tests/Layout/TemplateManifestTests.swift
      - AppCore/Tests/Layout/RenderPlanTests.swift
      - AppCore/Tests/Layout/TextPlacerTests.swift
    brief: |
      Read the plan's "Current state" (the Python template files) and the Design section
      "Template manifest and render plan".
      1. git clone https://github.com/andras-tkcs/magenda /tmp/magenda && git -C /tmp/magenda
         checkout 3c15fc11fcbcf47bb9907e3a761e6c57d04cd2bd. Copy assets/compiled/slots.json to
         AppCore/Sources/Resources/slots.json unchanged. Check `sha256sum` prints
         ff9ed22ec6aece4d2f0daf764f0a8bd2a1507c813aa0fa5363afee8a9aa902bb; if not, stop blocked.
      2. AppCore/Package.swift: add `resources: [.copy("Resources/slots.json")]` to the AppCore
         target. Change nothing else in the file except the comment above `let package` if it
         needs to mention resources.
      3. AppCore/Sources/Layout/TemplateManifest.swift: TemplateSlot, TemplateManifest (with
         init(data:), init(contentsOf:), bundled(), slot(_:)), TemplateError. JSON keys are
         snake_case (`page_width`, `size_half_points`, `header_slots`, `page_slots`, `delegated`,
         `table_top_left`, `row_overhead_twips`); keys the Swift type does not need are ignored.
      4. AppCore/Sources/Layout/RenderPlan.swift: PlanPoint, PlanRect (width, height,
         intersects(_:tolerance:), contains(_:tolerance:)), ChromePage, TextRun (bounds),
         DrawOperation, PagePlan, RenderPlan. PlanRect decodes from a 4-number JSON array and
         PlanPoint from a 2-number array (custom init(from:) with an unkeyed container); any other
         length throws a DecodingError. RenderPlan.omittedTodoItems uses p1's TodoItem.
      5. AppCore/Sources/Layout/TextPlacer.swift: TextAlignment and TextPlacer.place exactly as
         specified.
      6. Tests: TemplateManifestTests — bundled() decodes; page 595.304×841.890 within 0.001;
         20 header slots; page slot counts overview 101, delegated_shell 4, meeting_unit 2,
         further_notes 1; slot("todo.label")?.text == "TO-DO LIST"; delegatedRowOverhead ≈ 49.8;
         init(data:) with "{}" and with a slot whose role is "purple" throws .malformed;
         init(contentsOf: nil) throws .missing; init(contentsOf: a file URL that does not exist)
         throws .missing. RenderPlanTests — intersects and contains at the tolerance edges, bounds.
         TextPlacerTests with FakeTextMeasurer — one line centered vertically; three lines with
         baselines one lineHeight apart; center alignment; indents; empty strings skipped.
      7. Do not touch CHANGELOG.md or docs.
    acceptance:
      - sha256sum AppCore/Sources/Resources/slots.json prints ff9ed22ec6aece4d2f0daf764f0a8bd2a1507c813aa0fa5363afee8a9aa902bb
      - swift test --package-path AppCore --filter "TemplateManifestTests|RenderPlanTests|TextPlacerTests" passes on the core job (Linux), proving Bundle.module works there
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p4-layout-pages
    title: AgendaLayout for the header, overview, meeting and further-notes pages
    depends_on: [p1-calendar-and-content, p3-template-manifest-and-plan]
    complexity: M
    touches:
      - AppCore/Sources/Layout/TemplateGeometry.swift
      - AppCore/Sources/Layout/AgendaLayout.swift
      - AppCore/Sources/Layout/AgendaLayout+Overview.swift
      - AppCore/Tests/Layout/AgendaLayoutTests.swift
      - AppCore/Tests/Layout/AgendaLayoutOverviewTests.swift
    brief: |
      Read the plan's "Measured template geometry" table and the Design section "Layout rules
      (AgendaLayout)" up to, not including, "Delegated pages" and "Links". The Python original is
      src/magenda/pdf_assembler.py; follow the plan where they differ.
      1. AppCore/Sources/Layout/TemplateGeometry.swift: the `TemplateGeometry` enum with every
         non-delegated constant named in the Design section (p5 adds the delegated ones). Colors
         as RGBColor(red:green:blue:) literals.
      2. AppCore/Sources/Layout/AgendaLayout.swift: AgendaLayout(manifest:measurer:theme:) and
         plan(for:). Build pages in order overview, meeting pages (one blank page when
         content.meetings is empty), further notes. Write the page list so p5 can insert the
         delegated pages after the overview with one added line; do not add a stub function. Header on every page, static slots, meeting and further-notes
         pages as specified.
      3. AppCore/Sources/Layout/AgendaLayout+Overview.swift: the overview page steps 1–5 in the
         specified order, including omittedTodoItems.
      4. Tests with FakeTextMeasurer and TemplateManifest.bundled(): page order and chrome values
         for 0 and 3 meetings; every page's header carries "30 WEDNESDAY", "CW 40", "SEPTEMBER",
         "2026" for 2026-09-30; the overview's first operation is fill(todoErase, white); a to-do
         item that fits at 12 pt keeps 12 pt and one row of 28.35; a long item shrinks then wraps
         and its rows grow by the formula; separators are drawn at every row top except the
         first; blank rows fill the grid to todoBottom; 30 items of longStrings-length text fill
         the grid and the rest land in omittedTodoItems in order, while every drawn row ends at or
         above 655.75; a schedule entry longer than 201.8 ends with "…" and fits; a meeting title
         longer than its box ends with "…"; theme colors reach the runs (heading role uses the
         heading color; body text is black); jetbrainsMono runs use 0.9 × nominal size.
      5. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "AgendaLayoutTests|AgendaLayoutOverviewTests" passes
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p5-layout-delegated-and-links
    title: Delegated-task pages with pagination, and the PDF's navigation links
    depends_on: [p4-layout-pages]
    complexity: M
    touches:
      - AppCore/Sources/Layout/AgendaLayout+Delegated.swift
      - AppCore/Sources/Layout/AgendaLayout+Links.swift
      - AppCore/Sources/Layout/AgendaLayout.swift
      - AppCore/Sources/Layout/TemplateGeometry.swift
      - AppCore/Tests/Layout/AgendaLayoutDelegatedTests.swift
      - AppCore/Tests/Layout/AgendaLayoutLinksTests.swift
    brief: |
      Read the Design section "Layout rules (AgendaLayout)", parts "Delegated pages" and "Links".
      The Python originals are _draw_delegated_page, _plan_delegated_pages and
      _delegated_row_height in src/magenda/pdf_assembler.py and src/magenda/pdf_links.py.
      1. AppCore/Sources/Layout/TemplateGeometry.swift: add the delegated constants listed in the
         Design. AppCore/Sources/Layout/AgendaLayout+Delegated.swift: a private
         delegatedPages(for:) -> [PagePlan] implementing the delegated pages exactly as specified (fitting, row height, pagination, erase, header labels, footer
         label, marked fill, borders, running numbers, status bullets with indents and the
         10-line budget, closing line on every page but the last).
      2. AppCore/Sources/Layout/AgendaLayout+Links.swift: append the three kinds of link
         operations last on each page, after all pages exist (targets depend on the final page
         count).
      3. AppCore/Sources/Layout/AgendaLayout.swift: insert delegatedPages(for:) after the
         overview in the page list, and run the links pass once all pages exist. No other change.
      4. Tests with FakeTextMeasurer: no delegated items → no delegated page; items are drawn in
         sortedForPage() order with numbers continuing across pages; a marked row gets a
         D6FCEC fill before its border; first row border 3.0, others 0.5; 40 items with long
         statuses paginate so no row ends below 628.2 and every item appears exactly once; a
         status longer than 10 lines ends with "…"; continuation status lines are indented by the
         bullet width; the cadence label is the task cell's first line; links: none to page 0 on
         page 0, none to the last page on the last page, schedule links target
         1 + delegated page count + meetingIndex, a schedule entry without meetingIndex gets no
         link.
      5. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "AgendaLayoutDelegatedTests|AgendaLayoutLinksTests|AgendaLayoutTests" passes
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p6-layout-audit
    title: Layout audit and the long-text content fixtures, proven on every font pack
    depends_on: [p5-layout-delegated-and-links]
    complexity: S
    touches:
      - AppCore/Sources/Layout/LayoutAudit.swift
      - AppCore/Sources/Layout/AgendaContentFixtures.swift
      - AppCore/Tests/Layout/LayoutAuditTests.swift
      - AppCore/Tests/Layout/AgendaLayoutFixtureTests.swift
    brief: |
      Read the Design section "Layout audit". This is the guard the user asked for: long event
      titles and long task names must not break the layout.
      1. AppCore/Sources/Layout/LayoutAudit.swift: LayoutAudit.violations(in:) and
         LayoutViolation exactly as specified.
      2. AppCore/Sources/Layout/AgendaContentFixtures.swift: typical, longText, overflow, empty
         and longStrings exactly as specified (copy the strings character for character).
      3. LayoutAuditTests: hand-built plans that trigger each violation kind once, and a clean
         plan with none.
      4. AgendaLayoutFixtureTests: @Test(arguments:) over every fixture × every FontPack, with
         FakeTextMeasurer: LayoutAudit.violations(in: plan) is empty; overflow puts at least one
         item in omittedTodoItems; every TextRun's text is non-empty and contains no "\n" or "\t".
      5. If a violation appears that this phase cannot fix inside LayoutAudit or the fixtures
         (it would need a change to AgendaLayout), stop blocked and list the violations.
      6. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "LayoutAuditTests|AgendaLayoutFixtureTests" passes with 4 fixtures × 3 packs
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p7-oauth-flow
    title: HTTP types, Google OAuth configuration, PKCE, callback parsing and token endpoint
    depends_on: []
    complexity: M
    worker_model: opus
    worker_model_reason: Security-sensitive parsing of OAuth callbacks and token responses; every failure must fail closed and be proven by a negative test.
    touches:
      - AppCore/Sources/Google/HTTP.swift
      - AppCore/Sources/Google/GoogleAPIError.swift
      - AppCore/Sources/Google/GoogleOAuth.swift
      - AppCore/Tests/Google/GoogleOAuthTests.swift
      - AppCore/Tests/Google/GoogleAPIErrorTests.swift
      - AppCore/Tests/Support/FakeHTTPClient.swift
      - AppCore/Tests/Support/FakeHasher.swift
    brief: |
      Read the Design section "Google sign-in" up to, not including, `TokenStore`.
      1. AppCore/Sources/Google/HTTP.swift: HTTPMethod, HTTPRequest, HTTPResponse, HTTPClient,
         SHA256Hashing.
      2. AppCore/Sources/Google/GoogleAPIError.swift: GoogleAPIError with userMessage strings
         copied exactly from the table.
      3. AppCore/Sources/Google/GoogleOAuth.swift: GoogleOAuthConfiguration, AuthorizationRequest,
         OAuthTokens, GoogleOAuth with every function as specified. Form bodies are encoded by one
         private function that leaves only A–Z a–z 0–9 - . _ ~ unescaped.
      4. AppCore/Tests/Support/FakeHTTPClient.swift: a final class guarded by an NSLock recording
         every HTTPRequest and returning queued responses or errors in order.
         AppCore/Tests/Support/FakeHasher.swift: returns canned digests per input and fails the
         test on an unknown input.
      5. Tests, positive and negative: configuration accepts "123-abc.apps.googleusercontent.com"
         and rejects uppercase, a missing prefix, a trailing path, an empty string; redirect scheme
         and URI; the RFC 7636 test vector through FakeHasher; verifier length 64 and state length
         32 from the allowed set (seeded generator); authorization URL query items and their
         order; callback: wrong scheme, wrong state, missing state, missing code,
         error=access_denied, error=server_error, valid; token and refresh request bodies decode
         back to the exact fields (including a code containing "/" and "+"); tokens(from:):
         success, missing refresh token with and without a previous one, token_type "mac", empty
         access_token, missing scope when required, a present scope missing tasks.readonly,
         400 invalid_grant, 400 other, 500, invalid JSON; every userMessage.
      6. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "GoogleOAuthTests|GoogleAPIErrorTests" passes
      - the RFC 7636 appendix B vector test is present and passes
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p8a-google-session
    title: GoogleSession — token storage, single-flight refresh, authorized requests, sign-in and sign-out
    depends_on: [p7-oauth-flow]
    complexity: M
    worker_model: opus
    worker_model_reason: Single-flight token refresh across concurrent callers in an actor, and the 401-refresh-retry rule, are subtle concurrency and credential-handling code.
    touches:
      - AppCore/Sources/Google/GoogleSession.swift
      - AppCore/Tests/Google/GoogleSessionTests.swift
      - AppCore/Tests/Support/FakeTokenStore.swift
    brief: |
      Read the Design section "Google sign-in" from `TokenStore` on.
      1. AppCore/Sources/Google/GoogleSession.swift: TokenStore, AuthorizedHTTPSending,
         GoogleAccount, GoogleSession, UnconfiguredGoogleAccount (public init()), behaving exactly
         as listed. The in-flight refresh is a `Task<OAuthTokens, Error>?` stored on the actor and
         cleared when it finishes.
      2. AppCore/Tests/Support/FakeTokenStore.swift: a final class guarded by an NSLock that
         holds optional tokens, counts saves and deletes, and can be told to throw on load or save.
      3. Tests (FakeHTTPClient and FakeHasher from p7, a fixed clock): not signed in → .signedOut;
         bearer header added; a token within 60 s of expiry refreshes first; two concurrent sends
         (async let) trigger exactly one refresh request; 401 → refresh → retry succeeds; 401
         twice → tokens deleted and .signedOut; refresh returning invalid_grant → tokens deleted
         and .signedOut; 403, 429, 500 and a transport error map as specified; isSignedIn is
         false when load throws; signIn passes (authorization URL, redirect scheme) to the
         closure, exchanges the code and saves tokens; a closure GoogleAPIError passes through,
         any other closure error becomes .authorizationFailed, a save error becomes
         .authorizationFailed; signOut sends the revoke request and deletes tokens even when the
         revoke fails or delete throws; UnconfiguredGoogleAccount throws .notConfigured and is
         never signed in.
      4. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter GoogleSessionTests passes on the core job (Linux)
      - a test whose name mentions the concurrent refresh asserts exactly one refresh request
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p8b-google-clients
    title: Google models, the Calendar and Tasks clients, and recorded response fixtures
    depends_on: [p1-calendar-and-content, p3-template-manifest-and-plan, p8a-google-session]
    complexity: M
    touches:
      - AppCore/Sources/Google/GoogleModels.swift
      - AppCore/Sources/Google/GoogleCalendarClient.swift
      - AppCore/Sources/Google/GoogleTasksClient.swift
      - AppCore/Package.swift
      - AppCore/Tests/Google/GoogleCalendarClientTests.swift
      - AppCore/Tests/Google/GoogleTasksClientTests.swift
      - AppCore/Tests/Google/Fixtures/*.json
      - AppCore/Tests/Support/FakeSender.swift
    brief: |
      Read the Design section "Google Calendar and Tasks clients".
      1. AppCore/Sources/Google/GoogleModels.swift: GoogleCalendar, EventStart, GoogleEvent,
         GoogleTaskList, GoogleTask, GoogleDataSource, LiveGoogleDataSource (all public, explicit
         public inits).
      2. AppCore/Sources/Google/GoogleCalendarClient.swift and GoogleTasksClient.swift: requests,
         decoding (private Decodable DTOs) and paging as specified. Calendar and task-list IDs go
         through URL.appending(path:), never string interpolation into a URL string. timeMin and
         timeMax are UTC with a Z suffix.
      3. AppCore/Package.swift: add `resources: [.copy("Google/Fixtures")]` to the AppCoreTests
         target only (keep p3's AppCore target resources). Tests read a fixture with
         Bundle.module.url(forResource: <name>, withExtension: "json", subdirectory: "Fixtures").
      4. AppCore/Tests/Google/Fixtures/: calendar-list.json, events-page1.json (with
         nextPageToken), events-page2.json, events-all-day.json, task-lists.json, tasks.json,
         tasks-malformed.json, in Google's documented response shapes (fields as named in the
         Design). Only made-up names and addresses. No "#" followed by digits in any string
         (scripts/tests/test_no_project_history.py scans .json files).
      5. AppCore/Tests/Support/FakeSender.swift: an AuthorizedHTTPSending fake (final class with
         an NSLock) recording requests and returning queued responses or errors.
      6. Tests: exact request URLs, including a calendar ID "a#b@group.calendar.google.com"
         percent-encoded in the path and, for time zone Europe/Budapest and day 2026-09-30,
         timeMin=2026-09-29T22:00:00Z and timeMax=2026-09-30T22:00:00Z with no "+" anywhere in
         the URL; two-page paging; the 10-page cap; all-day vs timed starts with and without
         fractional seconds; an event with neither start form is skipped; selfResponse; title
         fallbacks for calendars; due parsing for tasks; malformed body → .unexpectedResponse;
         a sender error passes through; LiveGoogleDataSource forwards each call.
      7. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "GoogleCalendarClientTests|GoogleTasksClientTests" passes on the core job (Linux)
      - the core job's coverage floor step passes at 100%
      - the lint job passes
      - python3 -m unittest discover -s scripts/tests passes
  - id: p9-settings-and-delegated-notes
    title: Agenda settings, the settings store protocol and the delegated-notes parser
    depends_on: [p1-calendar-and-content, p2-text-fitting]
    complexity: S
    touches:
      - AppCore/Sources/Settings/AgendaSettings.swift
      - AppCore/Sources/Settings/DelegatedNotes.swift
      - AppCore/Tests/Settings/AgendaSettingsTests.swift
      - AppCore/Tests/Settings/DelegatedNotesTests.swift
    brief: |
      Read the Design section "From Google data to a draft" up to, not including, DraftEvent.
      1. AppCore/Sources/Settings/AgendaSettings.swift: AgendaSettings (with theme), SettingsStore,
         InMemorySettingsStore (NSLock, as the Design says).
      2. AppCore/Sources/Settings/DelegatedNotes.swift: DelegatedNotes and parse(_:) with the
         exact rules and warning text.
      3. Tests: settings defaults; JSON round trip; unknown fontPack decodes to .outfit; a JSON
         object with only {"todoListID":"x"} decodes with every other default; theme mirrors
         fontPack and colors; InMemorySettingsStore save then load. DelegatedNotes, parameterized:
         nil and empty notes; the full example from the Design; fields in another order and case
         ("CADENCE: Monthly"); blank lines among fields; a status line that looks like a field
         after a status line stays a status line; unknown cadence gives daily and the exact
         warning; every accepted marked value and "no".
      4. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "AgendaSettingsTests|DelegatedNotesTests" passes
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p10-draft-and-builder
    title: AgendaDraft with edits and toggles, and AgendaBuilder from Google data
    depends_on: [p8b-google-clients, p9-settings-and-delegated-notes]
    complexity: M
    touches:
      - AppCore/Sources/Draft/AgendaDraft.swift
      - AppCore/Sources/Draft/AgendaBuilder.swift
      - AppCore/Tests/Draft/AgendaDraftTests.swift
      - AppCore/Tests/Draft/AgendaBuilderTests.swift
    brief: |
      Read the Design section "From Google data to a draft" from DraftEvent on.
      1. AppCore/Sources/Draft/AgendaDraft.swift: DraftEvent, DraftTask, DraftDelegated,
         AgendaDraft with every mutating function and content().
      2. AppCore/Sources/Draft/AgendaBuilder.swift: AgendaBuilder(timeZone:) and
         draft(for:events:tasks:delegated:) with the exact rules. timeText uses a Calendar in the
         builder's time zone, formatted with String(format: "%02d:%02d", hour, minute).
      3. Tests (build GoogleEvent/GoogleTask values directly, time zone Europe/Budapest, day
         2026-09-30): each event filter rule; dedupe by iCalUID across two calendars; sort by
         start then title; "(No title)"; an event at 07:30 and one at 19:00 have nil
         scheduleSlot but still a meeting page; to-do filter and order (overdue, today, undated
         by position) and dueText "Today" / "28 Sep" / ""; delegated parsing reaches the draft;
         content(): two events in one slot join with " / " and get no meetingIndex; unticking a
         meeting page keeps the event on the schedule and removes its meetingIndex; unticked
         tasks and delegated items are left out; setTitle with "  " restores the original;
         setText normalizes newlines.
      4. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "AgendaDraftTests|AgendaBuilderTests" passes
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p11-agenda-controller
    title: AgendaController and the Google fixtures for UI tests and previews
    depends_on: [p6-layout-audit, p10-draft-and-builder]
    complexity: M
    touches:
      - AppCore/Sources/Controller/AgendaController.swift
      - AppCore/Sources/Controller/GoogleFixtures.swift
      - AppCore/Tests/Controller/AgendaControllerTests.swift
      - AppCore/Tests/Controller/GoogleFixturesTests.swift
      - AppCore/Tests/Support/FakeRenderer.swift
    brief: |
      Read the Design section "Controller".
      1. AppCore/Sources/Controller/AgendaController.swift: RenderedAgenda, AgendaRendering and
         AgendaController (`import Observation`, `@MainActor @Observable`) exactly as specified.
      2. AppCore/Sources/Controller/GoogleFixtures.swift: GoogleFixture (with
         init?(launchArguments:)), FixtureGoogleDataSource and FixtureGoogleAccount with the
         specified data.
      3. AppCore/Tests/Support/FakeRenderer.swift: records the plan and file name, returns a
         fixed URL or throws.
      4. Tests (@MainActor, FixtureGoogleDataSource/FixtureGoogleAccount, InMemorySettingsStore,
         FakeTextMeasurer, TemplateManifest.bundled(), FakeRenderer): start() signed out and
         signed in; signIn success, cancellation (no message) and failure (message); load()
         picks primary when calendarIDs is empty or stale, the first list as to-do list, no
         delegated list when it equals the to-do list; a data source throwing .signedOut moves to
         .signedOut with its message, .network to .failed; setDay reloads; updateSettings saves
         and reloads only when a source changed (changing fontPack does not reload);
         updateDraft and updateSettings clear rendered; render() passes the file name
         "Agenda 2026-09-30.pdf", fills RenderedAgenda (overflow fixture reports omitted tasks),
         and a renderer error leaves .ready with "Couldn't create the PDF. Try again.";
         signOut clears state. GoogleFixturesTests: launch-argument parsing; each fixture's
         counts; longText uses AgendaContentFixtures.longStrings.
      5. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "AgendaControllerTests|GoogleFixturesTests" passes on the core job (Linux)
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p12-app-pdf-renderer
    title: Bundle the template and fonts; CoreText measurer and PDF renderer, audited with real fonts on simulators
    depends_on: [p6-layout-audit, p11-agenda-controller]
    complexity: M
    touches:
      - App/Resources/Template/chrome.pdf
      - App/Resources/Fonts/*.ttf
      - App/Resources/Fonts/OFL-Outfit.txt
      - App/Resources/Fonts/OFL-Roboto.txt
      - App/Resources/Fonts/OFL-JetBrainsMono.txt
      - App/Rendering/FontLibrary.swift
      - App/Rendering/CoreTextMeasurer.swift
      - App/Rendering/PDFAgendaRenderer.swift
      - AppTests/RenderingTests.swift
    brief: |
      Read the Design sections "Template and fonts" and "Rendering" under "App", and
      .claude/skills/steward/SKILL.md (app tests only run on tests.yml's app jobs).
      1. From the Python repo at the pinned commit (see p3's clone command) copy
         assets/compiled/chrome.pdf to App/Resources/Template/chrome.pdf and the 15
         assets/fonts/*.ttf to App/Resources/Fonts/. Check chrome.pdf's SHA-256 is
         b2e7eb2aafeed0c17db5f33fe1b8f900d5866194989d890035e458770edabfe3; if not, stop blocked.
         Download the three OFL.txt files from the URLs in the Design to the OFL-*.txt names.
      2. App/Rendering/FontLibrary.swift, CoreTextMeasurer.swift, PDFAgendaRenderer.swift as
         specified. PDFAgendaRenderer conforms to AgendaRendering (p11).
      3. AppTests/RenderingTests.swift (Swift Testing, hosted): every FontPack × FontWeight loads
         from the bundle; CoreTextMeasurer gives a positive width for "TO-DO LIST" and for each
         of AgendaContentFixtures.longStrings, and wider text measures wider; for every
         AgendaContentFixtures fixture × every FontPack, AgendaLayout with CoreTextMeasurer and
         TemplateManifest.bundled() gives LayoutAudit.violations(in:) == [] (report the
         violations in the failure message); FontLibrary(bundle: .main) succeeds and
         FontLibrary(bundle: Bundle(for: an NSObject subclass declared in the test file)), the
         test bundle, which holds no fonts, throws missingFont; rendering the typical and overflow plans writes a
         file that PDFDocument opens with pageCount == plan.pages.count, page 0's string contains
         "TO-DO LIST" and "30 WEDNESDAY", page 1 of the typical plan has a PDFAnnotation whose
         destination page index is 0, and the first `findString("TO-DO LIST")` selection's
         `bounds(for: page 0)` has its vertical center within 12 pt of
         841.890 − (that TextRun's baseline − ascent/2 + descent/2) (PDF space is bottom-up),
         which proves text is neither mirrored nor upside down.
      4. Push the branch and dispatch tests.yml against it; read the three app jobs. A static
         label overlap with real fonts, or link annotations missing from PDFKit, is a stop
         condition (see the plan's Risks): stop blocked with the job log excerpt.
      5. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - sha256sum App/Resources/Template/chrome.pdf prints b2e7eb2aafeed0c17db5f33fe1b8f900d5866194989d890035e458770edabfe3
      - ls App/Resources/Fonts/*.ttf | wc -l prints 15
      - tests.yml app (iphone, newest), app (iphone, oldest) and app (ipad, newest) pass on the phase branch, including RenderingTests
      - the lint and scripts jobs pass
  - id: p13-app-platform
    title: URLSession, Keychain, CryptoKit and UserDefaults adapters, privacy manifest and client ID loading
    depends_on: [p8a-google-session, p8b-google-clients, p9-settings-and-delegated-notes]
    complexity: S
    touches:
      - App/Platform/URLSessionHTTPClient.swift
      - App/Platform/KeychainTokenStore.swift
      - App/Platform/CryptoKitHasher.swift
      - App/Platform/UserDefaultsSettingsStore.swift
      - App/Platform/BundledGoogleClient.swift
      - App/PrivacyInfo.xcprivacy
      - AppTests/PlatformTests.swift
      - scripts/tests/test_google_oauth_client_id.py
    brief: |
      Read the Design section "Platform" under "App". Do not edit App/GoogleOAuthClientID.txt;
      the user fills it in (manual step mb3).
      1. Create the five App/Platform files as specified. KeychainTokenStore uses SecItemAdd /
         SecItemUpdate / SecItemCopyMatching / SecItemDelete; errSecItemNotFound on load returns
         nil; other statuses throw a private error. URLSessionHTTPClient maps URLError to a
         thrown error without the URL or headers in its description.
      2. App/PrivacyInfo.xcprivacy with exactly the keys in the Design.
      3. scripts/tests/test_google_oauth_client_id.py (unittest, stdlib only): the file
         App/GoogleOAuthClientID.txt exists, has exactly one non-empty line, and that line
         matches ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$. Its failure message says to
         follow the manual step "Create an iOS OAuth client" and paste the client ID there.
      4. AppTests/PlatformTests.swift (hosted): KeychainTokenStore save/load/overwrite/delete
         round trip under service "name.felhasznalo.magenda.tests" (deleted in the test's
         cleanup); UserDefaultsSettingsStore round trip in a UserDefaults(suiteName:) removed
         afterwards, and garbage data loads as defaults; CryptoKitHasher on the RFC 7636 verifier
         gives the expected challenge digest; BundledGoogleClient.configuration(bundle: .main)
         is non-nil.
      5. Push and dispatch tests.yml; read the scripts and app jobs. If the Keychain test fails
         with OSStatus -34018 (errSecMissingEntitlement) on the simulator, stop blocked and quote
         the status; do not add entitlements or skip the test.
      6. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - python3 -m unittest discover -s scripts/tests passes (it fails while the client ID placeholder is still there; if it does, stop blocked and say mb3 is not done)
      - tests.yml's three app jobs pass on the phase branch, including PlatformTests
      - the lint job passes
      - plutil -lint App/PrivacyInfo.xcprivacy succeeds on the app job, or python3 -c "import plistlib;plistlib.load(open('App/PrivacyInfo.xcprivacy','rb'))" succeeds locally
  - id: p14a-app-shell-and-sign-in
    title: App wiring, root and sign-in screens, removal of the template placeholder
    depends_on: [p12-app-pdf-renderer, p13-app-platform]
    complexity: M
    touches:
      - App/MagendaApp.swift
      - App/AppEnvironment.swift
      - App/ContentView.swift
      - App/Screens/RootView.swift
      - App/Screens/SignInView.swift
      - App/Screens/AgendaView.swift
      - AppCore/Sources/Greeting.swift
      - AppCore/Tests/GreetingTests.swift
      - AppUITests/MainScreenUITests.swift
      - AppUITests/SignInUITests.swift
    brief: |
      Read the Design sections "Wiring" and "Screens" (rows RootView and SignInView) and
      docs/coding-and-testing-guidelines.md "Views".
      1. App/AppEnvironment.swift: makeController(arguments:bundle:) exactly as the Design's
         "Wiring" paragraph says, live and fixture branches included.
      2. App/MagendaApp.swift: as the "Wiring" paragraph says, including the templateError text
         when makeController throws, and RootView(appInfo:).
      3. App/Screens/RootView.swift and SignInView.swift with the exact strings, identifiers and
         #Previews. SignInView passes @Environment(\.webAuthenticationSession)'s
         authenticate(using: url, callback: .customScheme(scheme), preferredBrowserSession:
         .shared, additionalHeaderFields: [:]) to controller.signIn, mapping
         ASWebAuthenticationSessionError.canceledLogin to GoogleAPIError.authorizationCancelled.
      4. App/Screens/AgendaView.swift: a stub `AgendaView(appInfo:)` showing
         `List { Text(controller.day.isoString) }` with identifier `agendaScreen` on the List and
         a #Preview; p14b replaces its body.
      5. Delete App/ContentView.swift, AppCore/Sources/Greeting.swift,
         AppCore/Tests/GreetingTests.swift and AppUITests/MainScreenUITests.swift.
      6. AppUITests/SignInUITests.swift (XCTest, identifiers only, waitForExistence, no sleeps):
         -MagendaFixture standard -MagendaSignedOut shows signInButton, and tapping it reaches
         agendaScreen within 10 s; -MagendaFixture standard alone reaches agendaScreen without
         showing signInButton.
      7. Push and dispatch tests.yml; all three app jobs must pass.
      8. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - test ! -e App/ContentView.swift && test ! -e AppCore/Sources/Greeting.swift && test ! -e AppUITests/MainScreenUITests.swift
      - tests.yml's three app jobs pass on the phase branch with SignInUITests
      - the core (coverage floor 100%), lint and scripts jobs pass
  - id: p14b-app-agenda-screen
    title: The agenda review screen with rows, toggles and editing, and UI tests for long text and Dynamic Type
    depends_on: [p14a-app-shell-and-sign-in]
    complexity: M
    touches:
      - App/Screens/AgendaView.swift
      - App/Screens/AgendaRows.swift
      - App/Screens/EditTextSheet.swift
      - AppUITests/AgendaScreenUITests.swift
      - AppUITests/LongTextUITests.swift
    brief: |
      Read the Design section "Screens" (rows AgendaView and EditTextSheet, and the "Rows"
      paragraph) and docs/coding-and-testing-guidelines.md "Views".
      1. App/Screens/AgendaView.swift: replace p14a's stub body with the full screen; keep the
         identifier `agendaScreen` on its List. The settingsButton exists but its destination is
         `Text("Settings")` until p15. The Render button awaits controller.render() and then
         pushes a placeholder destination `Text(rendered.url.lastPathComponent)` with identifier
         `pdfPreview`, which p15 replaces with PreviewView.
      2. App/Screens/AgendaRows.swift (the three row views) and EditTextSheet.swift with the exact
         strings, identifiers, accessibility labels and #Previews (fixture data).
      3. UI tests (XCTest, identifiers only, waitForExistence, no sleeps), launched with
         -MagendaFixture. AgendaScreenUITests — standard: eventRow.0…3 and taskRow.0…2 and
         delegatedRow.0…1 exist; toggling eventToggle.0 changes its value; eventScheduleNote.3
         exists (the 19:00 event) and eventScheduleNote.0 does not; editing taskRow.0 through
         editField and editDone changes taskRow.0's label; editCancel leaves it unchanged;
         Render shows pdfPreview within 30 s. LongTextUITests — longText, once at the default size
         and once with launch arguments -UIPreferredContentSizeCategoryName
         UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge: for every eventRow.n,
         taskRow.n and delegatedRow.n, after scrolling it into view, its frame's minX ≥ the
         window's minX and maxX ≤ the window's maxX, and its toggle isHittable; renderButton is
         hittable and Render reaches pdfPreview.
      4. Push and dispatch tests.yml; all three app jobs must pass.
      5. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - tests.yml's three app jobs pass on the phase branch with AgendaScreenUITests and LongTextUITests
      - the core (coverage floor 100%), lint and scripts jobs pass
      - grep -rn "sleep(" AppUITests prints nothing
  - id: p15-app-preview-and-settings
    title: PDF preview with the share button, the settings screen, and their UI tests
    depends_on: [p14b-app-agenda-screen]
    complexity: M
    touches:
      - App/Screens/PreviewView.swift
      - App/Screens/PDFKitView.swift
      - App/Screens/SettingsView.swift
      - App/Screens/AgendaView.swift
      - AppUITests/PreviewUITests.swift
      - AppUITests/SettingsUITests.swift
    brief: |
      Read the Design section "Screens" (rows PreviewView and SettingsView).
      1. App/Screens/PDFKitView.swift: UIViewRepresentable around PDFView (autoScales true,
         displayMode .singlePageContinuous, document from the URL), identifier pdfPreview.
      2. App/Screens/PreviewView.swift: the PDF, the toolbar ShareLink(item: url) with label
         "Share PDF" and identifier shareButton, and the omittedTasksBanner exactly as specified.
      3. App/Screens/SettingsView.swift with every section, string and identifier in the Design.
         Hex fields validate with RGBColor(hex:) and save through controller.updateSettings.
      4. App/Screens/AgendaView.swift: replace p14b's placeholder destinations: the render
         destination becomes PreviewView and settingsButton opens SettingsView(appInfo:). No
         other change.
      5. UI tests with -MagendaFixture: PreviewUITests — standard: Render, pdfPreview exists,
         shareButton exists and isHittable, no omittedTasksBanner; overflow: the banner exists and
         its label starts with a number followed by " task"; longText at the largest accessibility
         size: shareButton isHittable. SettingsUITests — open settings; typing "XYZ" into
         colorField.heading and submitting shows colorError; typing "7C3AED" removes it;
         resetColorsButton restores 215E99; tapping fontOption.jetbrains_mono and rendering
         reaches pdfPreview; the version row exists; signOutButton returns to signInButton.
      6. Push and dispatch tests.yml; all three app jobs must pass.
      7. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - tests.yml's three app jobs pass on the phase branch with PreviewUITests and SettingsUITests
      - the core (coverage floor 100%), lint and scripts jobs pass
      - grep -n "ShareLink" App/Screens/PreviewView.swift prints a line
  - id: p16-retire-plan
    title: ADRs 0011–0015, standing docs, coverage floors, changelog, and plan removal
    depends_on: [p15-app-preview-and-settings]
    complexity: S
    touches:
      - docs/adr/0011-the-agenda-pdf-is-drawn-on-device-from-the-vendored-magenda-template.md
      - docs/adr/0012-text-layout-is-computed-in-appcore-and-audited.md
      - docs/adr/0013-google-sign-in-uses-pkce-with-aswebauthenticationsession.md
      - docs/adr/0014-agenda-inputs-come-from-google-calendar-and-google-tasks.md
      - docs/adr/0015-appcore-may-import-observation.md
      - docs/adr/README.md
      - AppCore/Package.swift
      - README.md
      - docs/testing-policy.md
      - docs/release-testing.md
      - docs/coding-and-testing-guidelines.md
      - CHANGELOG.md
      - scripts/check_coverage_floor.py
      - docs/google-agenda-pdf-plan.md
      - docs/google-agenda-pdf-plan-manual-steps.html
    brief: |
      Read CONTRIBUTING.md "Decisions, plans and ADRs", docs/adr/README.md (template and rules),
      and this plan's "ADRs" and "Rejected alternatives".
      1. Write ADRs 0011–0015 with the file names in `touches`, Status "Accepted — <today's
         date>.", using the plan's Design and Rejected alternatives for Context, Decision and
         Alternatives considered. They link to source files and commits, never to this plan.
         Add them to the index in docs/adr/README.md.
      2. README.md: replace "An iOS app." with what Magenda does (Google sign-in, review, render,
         preview, share, settings), a "Delegated tasks" section with the notes format from the
         Design, a "Google Cloud setup" pointer saying the client ID lives in
         App/GoogleOAuthClientID.txt (ADR 0013), and the new folders in the Layout table
         (App/Rendering, App/Platform, App/Screens, App/Resources).
      3. docs/testing-policy.md: Layer 4 says the Google decoding tests replay
         AppCore/Tests/Google/Fixtures and that no live contract check runs; the layout audit
         runs in AppCore (fake font) and in AppTests (real fonts).
         docs/release-testing.md "What stays manual": real Google sign-in and real account data.
         docs/coding-and-testing-guidelines.md: "Where code goes" gets a row for the vendored
         template resources (ADR 0011) and says AppCore may import Observation (ADR 0015); the
         examples that name the deleted placeholder change — "`ContentView` is the placeholder"
         goes, `Sources/Greeting.swift` / `Tests/GreetingTests.swift` become
         `Sources/Agenda/CalendarDay.swift` / `Tests/Agenda/CalendarDayTests.swift`, and
         `--filter GreetingTests` becomes `--filter CalendarDayTests`. AppCore/Package.swift: the
         comment "It depends on Foundation at most" also allows Observation (ADR 0015); change
         nothing else in that file.
      4. scripts/check_coverage_floor.py MODULE_FLOORS: add at 100.0, each with a one-line why
         comment, AppCore/Sources/Layout/TextFitter.swift, AgendaLayout.swift,
         AgendaLayout+Overview.swift, AgendaLayout+Delegated.swift, LayoutAudit.swift,
         AppCore/Sources/Google/GoogleOAuth.swift, GoogleSession.swift,
         AppCore/Sources/Settings/DelegatedNotes.swift. Remove nothing.
      5. CHANGELOG.md under [Unreleased] → Added: replace the placeholder first-screen line with
         user-facing lines: sign in with Google; agenda from Google Calendar events and Google
         Tasks; untick or edit items before rendering; delegated tasks from a Google Tasks list;
         PDF preview and sharing; font and color settings; long titles are shortened with "…"
         and to-dos that don't fit are listed.
      6. Delete docs/google-agenda-pdf-plan.md and docs/google-agenda-pdf-plan-manual-steps.html;
         grep the repo for "google-agenda-pdf-plan" and remove any remaining link.
      7. Run python3 -m unittest discover -s scripts/tests (the no-project-history guard covers
         the new docs) and /dod.
    acceptance:
      - test ! -e docs/google-agenda-pdf-plan.md && test ! -e docs/google-agenda-pdf-plan-manual-steps.html
      - grep -rn "google-agenda-pdf-plan" --exclude-dir=.git . prints nothing
      - ls docs/adr/001[1-5]-*.md lists five files, each containing "Accepted"
      - grep -c "^| \[001[1-5]\]" docs/adr/README.md prints 5
      - grep -rn "Greeting\|ContentView" docs README.md CONTRIBUTING.md prints nothing
      - python3 -m unittest discover -s scripts/tests passes
      - grep -n "^## \[[0-9]" CHANGELOG.md prints nothing
```
