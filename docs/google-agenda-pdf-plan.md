# Plan: Magenda for iPad, fed by Google Calendar and Google Tasks

## Goal

Port [Magenda](https://github.com/andras-tkcs/magenda) and the user's "magenda-daily-binder" Claude
skill to this app, with no AI anywhere. Today a Claude session runs the skill: it reads Google
Calendar and two Google Tasks lists through an MCP gateway, applies the skill's selection rules,
makes a few judgement calls (shortening long meeting titles, spotting personal blocks, merging
duplicates), hands the result to the Magenda MCP server, which renders a daily agenda PDF laid out
exactly like its Word template, and uploads it. The app does the same deterministically: the user
signs in with Google, picks a date, reviews what the app selected from **Google Calendar**
(schedule and meeting pages) and **Google Tasks** (the "Claude" list for the to-do list, the
"Claude Delegations" list for the delegated-tasks page), sees every item's reason ("Declined",
"Personal block", "No other attendees", "Overdue", "Check-in due"…), optionally unticks or edits
items, taps **Render**, sees the PDF in an in-app **preview**, and sends it with the iOS **share**
button (the user imports it into Noteshelf 3 from the share sheet). Data always comes live from
Google's REST APIs; iOS's own calendar (EventKit) is not used, because it syncs late.

Every judgement call Claude makes today becomes a fixed, editable rule (Design, "Binder rules"):
an exclude list for personal blocks, a strip list for title prefixes, a short name saved per
recurring meeting, same-title duplicates merged, "to be discussed" tasks kept only when that person
is in a meeting that day, and a manual edit as the last resort. The app is designed for iPad first
(split view with the preview beside the list, any window size, keyboard shortcuts) and still runs
on iPhone.

Long event titles and long task names must never break the layout, in the PDF or in the app's
screens: the PDF fits text with fixed rules (shrink, wrap, cut with "…", cap lines, move what does
not fit to a warning), and every rendered plan is checked by an automated layout audit, on Linux
with a deterministic fake font and on simulators with the real fonts.

There is no tracking issue. The skill text the rules come from was pasted by the user into the
planning session on 2026-10-14; the rules it contains are restated in full under "Binder rules", so
no phase needs the skill itself.

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

**The daily-binder skill** (Claude skill "magenda-daily-binder", pasted by the user; not in any
repository) is the workflow the app replaces. Its rules, which the Design turns into code:

1. Resolve the date. Only when the date was inferred from relative wording ("tomorrow"): if it is a
   Saturday or Sunday, or has an all-day event titled like "OOO", "Out of Office", "Vacation" or
   "PTO" (not a location marker like "Home"), stop and ask.
2. Read the primary calendar for the day. Ignore all-day events. Leave out personal/break blocks
   ("Lunch", "Start the day"), recognised "by their nature" — **an AI judgement**.
3. Drop events the user declined (their own attendee entry is `declined`). A meeting page only when
   at least one attendee is neither the user nor a room (`…@resource.calendar.google.com`); go by
   attendees, never by title.
4. Schedule: every surviving event at its start time, 08:00–18:59, full title (Magenda cuts it).
5. Personal tasks from the Google Tasks list titled "Claude" (looked up by title each run; never
   another list; stop if missing): overdue first, then due on the day, then due within the next 5
   days "if there's room", skipping look-ahead titles like "… - to be discussed" / "TBD". Each task
   is `{text: "<title>: <notes>", due: "MM/DD"}` (no ": <notes>" when notes are empty).
6. Delegated tasks from the list titled "Claude Delegations" (stop if missing): title `Owner: Task`;
   description's first line `#daily` / `#weekly` / `#monthly`; status = the **last two** lines of
   the oldest-first log below it (one line if only one); a task that does not parse is flagged.
   Marked when its `due` (the next check-in date) is on or before the day. All are included.
7. Meeting-page titles over ~35 characters wrap in Magenda (a bug), so Claude shortens them by hand,
   dropping prefixes ("REMINDER // ") and filler — **an AI judgement**.
8. Render, upload to a Drive folder, and write a summary of what was left out and why.

The user's own review of four recent runs (Sep 22, Sep 28, Oct 1, Oct 8) listed what Claude changed
beyond those rules: meeting titles shortened (3 of 4 runs, e.g. a long recurring title starting with
"CONDITIONAL" rewritten to about 30 characters, "(temp) weekly …" losing both prefixes); task notes cut because the to-do
list ran past 18 rows; personal blocks spotted by nature; a duplicate "Quarterly Summit" at 08:00 and
08:30 merged; "Peter – to be discussed" kept because a 1:1 with Peter was that day; a 07:00
event given a meeting page but no schedule slot; the closing summary. The user chose: no AI at all
(no on-device model either), output through the iOS share sheet only (no Drive upload), the date
picked in the app (no scheduled runs), iPad first while keeping iPhone.

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
  `AgendaLayout`'s extensions. Where the Design gives a type's initializers (for example
  `GoogleOAuthConfiguration.init?(clientID:)`, `CalendarDay.init?`, `TemplateManifest`,
  `AgendaController`, `InMemorySettingsStore`, `TextFitter`, `GoogleSession`), those are its only
  public initializers; never add a memberwise one that skips their validation. Test files use `@testable import AppCore` only when they need one
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
    public func nextWeekday() -> CalendarDay                // the first Monday–Friday after self
    public func startDate(in timeZone: TimeZone) -> Date    // local midnight
}
```

All arithmetic uses `Calendar(identifier: .gregorian)` with `TimeZone(identifier: "UTC")` internally,
and `Calendar(identifier: .iso8601)` for `isoWeek` (if the `core` job on Linux gives a wrong ISO
week with it, stop blocked with the test output).

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
public struct TodoItem: Equatable, Sendable { public var text: String; public var notes: String; public var due: String }
// text = the task title; notes = its notes ("" when none); due = "MM/DD" or ""
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
  does not fit. Always appends the ellipsis (U+2026). The prefix length is found by binary search
  over the `Character` count (width grows with length), never by trying every length, because
  CoreText measuring a 2,000-character string once per length is quadratic.
- `func singleLine(_ text: String, font: FontSpec, maxWidth: Double) -> String`: `normalized(text)`;
  returned unchanged if it fits, else `ellipsized`.
- `func wrap(_ text: String, font: FontSpec, maxWidth: Double, maxLines: Int) -> [String]`:
  `normalized(text)`; empty gives `[]`. Greedy by words split on `" "`. A word wider than
  `maxWidth` on its own is broken at `Character` boundaries: take the longest prefix that fits (at
  least one `Character`; found by the same binary search), emit it as a line, continue with the rest (this also handles CJK text
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
   - The cell shows the skill's `"<title>: <notes>"`, but notes can never take more than one
     line (they are what overflowed the 18 rows in the Sep 28 run). With `n =
     TextFitter.normalized(notes)`: if `n` is empty, `fitted = downsizeOrWrap(text, pack, .thin,
     maxPoints: 12, minPoints: 9, maxWidth: 119.0, maxLines: 3)` and `lines = fitted.lines`.
     Otherwise `fitted = downsizeOrWrap(text + ":", …same arguments…)` and `lines = fitted.lines
     + [singleLine(n, fitted.font, maxWidth: 119.0)]`. `lh = metrics(fitted.font).lineHeight`;
     `baseLines = max(1, floor(28.35 / lh))`; `rowHeight = 28.35 + max(0, lines.count − baseLines)
     × lh`. Below, "task lines" means `lines`.
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
| `typical` | 3 to-dos ("Call the bank", notes "", due "09/30"; "Send the slides", notes "Ask Ben for the Q3 numbers first", due "09/28"; "Book flights", notes "", due "10/02"), schedule slot 2 "Team sync" (meetingIndex 0) and slot 5 "1:1 with Anna" (meetingIndex 1), meetings ["Team sync", "1:1 with Anna"], delegated ("Hire a designer", owner "Anna", weekly, marked, status ["Interviews scheduled", "Two candidates left"]) and ("Renew the office lease", owner "Ben", monthly, not marked, status ["Waiting for the landlord"]) |
| `longText` | for i in 0…5 with s = `longStrings[i]`: to-do (text s, notes `longStrings[(i + 1) % 7]`, due s); schedule entry slot `i * 4`, text s, meetingIndex i; meeting s; delegated (text s, owner s, cadence `Cadence.allCases[i % 3]`, marked `i % 2 == 0`, status [s, `longStrings[(i + 1) % 7]`, `longStrings[(i + 2) % 7]`]) |
| `overflow` | 30 to-dos (text `longStrings[0]`, notes `longStrings[6]`, due "09/30"); 22 schedule entries, slot i, text `longStrings[1]`, meetingIndex i; 25 meetings `"Meeting <i>: " + longStrings[0]`; 40 delegated (text `"Delegated task <i>: " + longStrings[0]`, owner "Alexandra Montgomery-Smith", cadence `Cadence.allCases[i % 3]`, marked `i % 4 == 0`, status five copies of `longStrings[0]`) |
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

OAuth 2.0 authorization code with PKCE (RFC 7636, S256), presented by
`ASWebAuthenticationSession` in `App/`. The repository is public and ships **no** Google client:
each user creates their own OAuth client in their own Google Cloud project and enters its client
ID (and, only if the client type has one, its client secret) in the app on first launch; both are
kept in the device's Keychain. The recommended client type is "iOS" (no secret, redirect scheme =
the reversed client ID, which `ASWebAuthenticationSession` handles without any Info.plist URL
type, so a client ID entered at runtime works). Scopes, exactly:
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
    public init?(clientID: String, clientSecret: String? = nil)
        // clientID trimmed, must match ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$;
        // clientSecret trimmed, empty → nil, otherwise must be 1…200 characters with no whitespace or control characters, else nil
    public let clientID: String
    public let clientSecret: String?
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
  `client_id, refresh_token, grant_type=refresh_token`; when `clientSecret` is non-nil,
  `client_secret` is appended to both, right after `client_id`. Revoke: `POST
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
| `notConfigured` | Enter your Google client ID first. |
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
public struct GoogleClientCredentials: Codable, Equatable, Sendable {
    public let clientID: String; public let clientSecret: String?
    public init(clientID: String, clientSecret: String?)
    public var configuration: GoogleOAuthConfiguration? { get }   // GoogleOAuthConfiguration(clientID:clientSecret:)
}
public protocol ClientCredentialsStore: Sendable {
    func load() throws -> GoogleClientCredentials?; func save(_ credentials: GoogleClientCredentials) throws; func delete() throws
}
public final class InMemoryClientCredentialsStore: ClientCredentialsStore, @unchecked Sendable {   // NSLock, as InMemorySettingsStore
    public init(_ credentials: GoogleClientCredentials? = nil)
}
public protocol GoogleAccount: Sendable {
    func configure(_ configuration: GoogleOAuthConfiguration?) async   // nil = no client entered yet
    func isConfigured() async -> Bool
    func isSignedIn() async -> Bool
    func signIn(authenticate: @escaping @Sendable (URL, String) async throws -> URL) async throws   // (authorization URL, callback scheme) → callback URL
    func signOut() async
}
public actor GoogleSession: GoogleAccount, AuthorizedHTTPSending {
    public init(configuration: GoogleOAuthConfiguration?, http: any HTTPClient, tokens: any TokenStore,
                hasher: any SHA256Hashing, now: @escaping @Sendable () -> Date)
}
```

`GoogleSession` behaviour:

- `configure(_:)`: stores the configuration. When the new value's `clientID` differs from the
  current one (including to or from nil), the tokens belong to the old client: delete them (ignoring
  a delete error) without a revoke request. The same client ID with a new secret keeps the tokens.
- `isConfigured()`: configuration is non-nil.
- `isSignedIn()`: false when not configured; otherwise `tokens.load()` returns a value; a thrown
  load counts as signed out.
- With no configuration, `signIn` and `send` throw `.notConfigured` before doing anything else.
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
public struct GoogleAttendee: Equatable, Sendable {
    public let email: String; public let displayName: String?
    public let isSelf: Bool; public let isResource: Bool; public let responseStatus: String?
}
public struct GoogleEvent: Equatable, Sendable {
    public let calendarID: String; public let id: String; public let iCalUID: String?
    public let recurringEventID: String?
    public let title: String?; public let status: String?; public let start: EventStart
    public let eventType: String?; public let selfResponse: String?
    public let attendees: [GoogleAttendee]     // every attendee, self and rooms included
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
  `attendees` maps each `attendees[]` entry: `email` (an entry without one is skipped),
  `displayName`, `isSelf = self == true`, `isResource = resource == true || email` (lowercased)
  `hasSuffix("@resource.calendar.google.com")`, `responseStatus`; missing `attendees` → `[]`.
  `recurringEventID` = `recurringEventId`. The query adds no `maxAttendees`, so Google returns
  every attendee.
- Task lists: `https://tasks.googleapis.com/tasks/v1/users/@me/lists?maxResults=100`.
- Tasks: `https://tasks.googleapis.com/tasks/v1/lists/<listId>/tasks?showCompleted=false&showHidden=false&maxResults=100`.
  `due` → `CalendarDay(isoString:)` of its first 10 characters.
- Every list follows `nextPageToken` (`pageToken=` query item) for at most 10 pages.
- A body that does not decode throws `.unexpectedResponse`; errors from the sender pass through.
- Recorded responses for tests: `AppCore/Tests/Google/Fixtures/*.json`, read with
  `Bundle.module.url(forResource:withExtension:subdirectory: "Fixtures")` from the test target
  (`resources: [.copy("Google/Fixtures")]` on the test target in `Package.swift`).

### Settings and binder rules (`AppCore/Sources/Settings/`)

```swift
public struct AgendaSettings: Equatable, Codable, Sendable {
    public var fontPack: FontPack = .outfit
    public var colors: ThemeColors = .default
    public var calendarIDs: [String] = []                    // empty means the primary calendar
    public var todoListTitle: String = "Claude"              // the skill's personal-task list
    public var delegatedListTitle: String = "Claude Delegations"   // "" means no delegated page
    public var rules: BinderRules = .default
    public var theme: Theme { get }
}
public struct BinderRules: Equatable, Codable, Sendable {
    public var personalBlocks: [String]          // default ["Lunch", "Start the day"]
    public var titlePrefixes: [String]           // default ["REMINDER //", "REMINDER:", "(temp)", "FW:", "Fwd:", "CONDITIONAL", "weekly"]
    public var outOfOfficeWords: [String]        // default ["OOO", "Out of Office", "Vacation", "PTO"]
    public var shortNames: [String: String]      // MeetingTitle key → short meeting-page title; default [:]
    public var personAliases: [String: String]   // BinderText.fold(name used in tasks) → lowercased attendee email; default [:]
    public var lookAheadDays: Int                // default 5, clamped to 0…14 when read by the builder
    public static let `default`: BinderRules
}
public protocol SettingsStore: Sendable { func load() -> AgendaSettings; func save(_ settings: AgendaSettings) }
public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {   // state guarded by an NSLock; a comment says so
    public init(_ settings: AgendaSettings = AgendaSettings())
}
```

Task lists are chosen **by title**, as the skill does ("don't hardcode its ID, since it can
change"). Decoding is tolerant: an unknown `fontPack` becomes `.outfit`; any missing field
(including any missing `BinderRules` field) takes its default, so a settings blob written by an
older build still loads.

`BinderText` (enum), the only place the rules compare text:

- `static func fold(_ text: String) -> String`: `TextFitter.normalized(text)`, then
  `.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)`, then
  `.lowercased()`. `fold("Zoltán") == fold("ZOLTAN") == "zoltan"`.
- `static func startsWithPhrase(_ text: String, _ phrase: String) -> Bool`: with `t = fold(text)`
  and `p = fold(phrase)`: false when `p` is empty; true when `t == p`; true when `t.hasPrefix(p)`
  and either `p`'s last `Character` is not a letter or digit, or the `Character` of `t` right after
  the prefix is not a letter or digit. So "Lunch" matches "Lunch", "lunch with Sam" and "Lunch:
  team", not "Lunchtime"; "FW:" matches "FW:Budget".
- `static func containsPhrase(_ text: String, _ phrase: String) -> Bool`: false for an empty
  folded phrase; true when `p` occurs in `t` at a position where the `Character` before it (if
  any) and the `Character` after it (if any) are not letters or digits. So "OOO" matches "OOO -
  Budapest" and "Vacation" matches "Summer vacation", while "PTO" does not match "Photography".

`MeetingTitle` (enum), the meeting-page title rules that replace Claude's shortening:

- `static func key(originalTitle: String, recurringEventID: String?) -> String`:
  `"r:" + recurringEventID` when it is non-nil and non-empty, else `"t:" + fold(originalTitle)`.
  Every instance of a recurring meeting shares one key, so a short name is entered once.
- `static func stripped(_ title: String, prefixes: [String]) -> String`: `t =
  TextFitter.normalized(title)`; repeat until no prefix matches: for the first prefix in list order
  with `startsWithPhrase(t, prefix)`, drop the prefix's length in `Character`s (the folded and
  original strings have the same number of `Character`s for these inputs; take the count from
  `TextFitter.normalized(prefix)`), then drop leading characters from the set `" -–—:/|·"`. If the
  result is empty, return `TextFitter.normalized(title)`. Otherwise uppercase its first
  `Character` if that is a lowercase letter. Examples (with the default prefixes, all in the
  tests): "REMINDER // Decision about the office move" → "Decision about the office move";
  "(temp) weekly budget / invoice review" → "Budget / invoice review"; "FW: Fwd: Contract
  deadline" → "Contract deadline"; "Weekly" → "Weekly" (nothing left, so unchanged); "Weekly sync" →
  "Sync"; "CONDITIONAL Product - Cross Team Roadmap Planning Alignment & Tracking" →
  "Product - Cross Team Roadmap Planning Alignment & Tracking" (the layout then cuts it
  with "…" unless a short name is saved).
- `static func pageTitle(originalTitle: String, recurringEventID: String?, rules: BinderRules) ->
  String`: the normalized `rules.shortNames[key(…)]` when it is non-empty, else `stripped(…)`.

The meeting-page title is only the default. The user can edit it per agenda, and the edit sheet
can save it as the meeting's short name (`AgendaController.saveShortName`). A title that is still
too long is cut with "…" by the layout, never wrapped (`singleLine` in "Layout rules"), which is
the Magenda bug the skill was working around.

`TaskTitle` (enum):

- `static func isDiscussion(_ title: String) -> Bool`: with `t = fold(title)`, true when `t` ends
  with `"to be discussed"` or `containsPhrase(title, "tbd")`.
- `static func discussionName(_ title: String) -> String?`: the regex
  `^(.+?)\s*[-–—:]\s*(?:to be discussed|tbd)\s*$` (case-insensitive) on
  `TextFitter.normalized(title)`; capture group 1 trimmed, or nil. "Peter – to be discussed" →
  "Peter"; "Zoltán - TBD" → "Zoltán"; "TBD" → nil. Use `NSRegularExpression` (Linux-safe).

`DelegatedTask.parse(title: String?, notes: String?) -> DelegatedTask` with `owner`, `text`,
`cadence`, `status: [String]`, `warning: String?`, the delegated-tasks format the skill reads:

```
Title:  Sam: Countersign the supplier agreement
Notes:  #weekly
        2026-08-13 Delegated to Sam.
        2026-08-20 Followed up — waiting on their lawyer.
        2026-08-27 Countersigned copy received, filing pending.
```

- Title: `TextFitter.normalized(title ?? "")`, split at the **first** `":"`; `owner` = the
  trimmed part before it, `text` = the trimmed part after it. With no colon, or an empty part on
  either side: `owner = ""`, `text` = the whole normalized title, and the warning
  `No “Owner: Task” title — shown without an owner.`
- Notes: split on `"\n"`, each line trimmed, empty lines dropped. If the first line, folded, is
  exactly `#daily`, `#weekly` or `#monthly`, that is the cadence and the line is consumed; otherwise
  cadence is `.daily`, nothing is consumed, and the warning
  `No #daily, #weekly or #monthly on the first line — shown as Daily.`
- `status` = the last two remaining lines in their original order (one if only one, none if
  none). Lines are kept as written, dates included.
- Both warnings → joined with one space in the order above.

### From Google data to a draft (`AppCore/Sources/Draft/`)

```swift
public enum EventExclusion: String, Equatable, Sendable {
    case declined, personalBlock, duplicate
    public var label: String     // "Declined", "Personal block", "Duplicate of an earlier event"
}
public struct DraftEvent: Equatable, Identifiable, Sendable {
    public let id: String                      // "<calendarID>|<event id>"
    public let originalTitle: String           // normalized; "(No title)" when empty
    public var title: String                   // meeting-page title, MeetingTitle.pageTitle by default
    public var defaultTitle: String            // what a blank edit restores; starts equal to title
    public let shortNameKey: String            // MeetingTitle.key(originalTitle:recurringEventID:)
    public let start: Date; public let timeText: String   // "HH:mm", 24-hour, local
    public let scheduleSlot: Int?              // nil when the event starts before 8:00 or after 18:59
    public let exclusion: EventExclusion?
    public let hasOtherAttendees: Bool
    public let attendeeEmails: [String]        // lowercased, other non-resource attendees
    public let attendeeFirstNames: [String]    // BinderText.fold of each one's first name
    public var isIncluded: Bool                // exclusion == nil by default
    public var includesMeetingPage: Bool       // isIncluded && hasOtherAttendees by default
    public var reasons: [String] { get }
}
public enum TaskBucket: String, Equatable, Sendable { case overdue, today, upcoming
    public var label: String                   // "Overdue", "Due today", "Upcoming"
}
public struct DraftTask: Equatable, Identifiable, Sendable {
    public let id: String                      // GoogleTask.id
    public let originalText: String; public var text: String
    public let notes: String                   // normalized; "" when none
    public let dueText: String                 // "MM/DD"
    public let bucket: TaskBucket
    public let reason: String?                 // why a discussion task was kept or left out
    public var isIncluded: Bool
}
public struct DraftDelegated: Equatable, Identifiable, Sendable {
    public let id: String                      // GoogleTask.id
    public let originalText: String            // the parsed DelegatedTask.text
    public var text: String
    public let owner: String; public let cadence: Cadence; public let marked: Bool
    public let status: [String]; public let warning: String?; public var isIncluded: Bool  // true by default
}
public struct AgendaDraft: Equatable, Sendable {
    public let date: CalendarDay
    public var notices: [String]               // shown above the lists; never in the PDF
    public let titlePrefixes: [String]         // the builder's rules.titlePrefixes
    public var events: [DraftEvent]; public var tasks: [DraftTask]; public var delegated: [DraftDelegated]
    public mutating func setTitle(_ text: String, forEvent id: String)       // normalized; blank → defaultTitle
    public mutating func applyShortName(_ title: String, key: String)        // see below
    public mutating func setText(_ text: String, forTask id: String)         // normalized; blank → originalText
    public mutating func setText(_ text: String, forDelegated id: String)    // normalized; blank → originalText
    public mutating func setIncluded(_ on: Bool, forEvent id: String)        // off also clears includesMeetingPage; on restores it to hasOtherAttendees
    public mutating func setMeetingPage(_ on: Bool, forEvent id: String)     // ignored while the event is not included
    public mutating func setIncluded(_ on: Bool, forTask id: String)
    public mutating func setIncluded(_ on: Bool, forDelegated id: String)
    public func content() -> AgendaContent
}
public struct AgendaBuilder: Sendable {
    public init(timeZone: TimeZone, rules: BinderRules)
    public func draft(for day: CalendarDay, events: [GoogleEvent], tasks: [GoogleTask], delegated: [GoogleTask]) -> AgendaDraft
}
```

`applyShortName(title, key:)`: for every event whose `shortNameKey == key`, sets both `title`
and `defaultTitle` to `TextFitter.normalized(title)`, or, when that is empty, to
`MeetingTitle.stripped(originalTitle, prefixes: titlePrefixes)` (the short name was removed).

**Event rules** (in `AppCore/Sources/Draft/EventSelection.swift`, `enum EventSelection` with
`static func draftEvents(for day:, events:, timeZone:, rules:) -> [DraftEvent]` and
`static func notices(for day:, events:, timeZone:, rules:) -> [String]`):

1. Not listed at all: `status == "cancelled"`; `eventType` in `workingLocation`, `outOfOffice`,
   `birthday`; `.allDay` starts (they only feed the notices); a timed start whose local day is not
   `day`.
2. Sort the rest by start, then `originalTitle`, then input order (input order is calendar order).
3. Walk them in that order. The first matching rule sets `exclusion`:
   `selfResponse == "declined"` → `.declined`; `startsWithPhrase(originalTitle, p)` for any `p` in
   `rules.personalBlocks` → `.personalBlock`; the same `iCalUID ?? id` as an earlier event in this
   walk that has no exclusion, or the same `fold(originalTitle)` as such an event that started
   less than 120 minutes earlier → `.duplicate` (so the earliest one stays: the "Quarterly Summit"
   08:00 / 08:30 case, while a "Team sync" at 09:00 and another at 15:00 are both kept).
4. `hasOtherAttendees` = some attendee has `!isSelf && !isResource && responseStatus !=
   "declined"`. `attendeeEmails` and `attendeeFirstNames` come from those same attendees; the
   first name is the first space-separated word of `displayName` when it is non-empty, else the
   email's local part up to the first `.`, `_`, `-` or `+`; folded.
5. `title` = `MeetingTitle.pageTitle(originalTitle:recurringEventID:rules:)`; `scheduleSlot` =
   `ScheduleSlot.index(hour:minute:)` of the local start; `timeText` from a `Calendar` in the
   builder's time zone with `String(format: "%02d:%02d", hour, minute)`.
6. `reasons`, in this order, exact strings: `exclusion?.label`; `"No meeting page: no other
   attendees"` when `exclusion == nil && !hasOtherAttendees`; `"Not on the schedule: outside
   8:00–18:59"` when `scheduleSlot == nil`; `"Page title: <title>"` when `includesMeetingPage &&
   title != originalTitle`.

**Notices** (in the same file), in this order:

- `day.weekdayIndex >= 5` → `"<Weekday>, <d> <Month> is a weekend."` with the weekday and month
  names from `CalendarMath` passed through `.capitalized` ("Saturday, 3 October is a weekend.").
- For the first all-day event (any calendar read, not cancelled, start day ≤ `day`: a multi-day
  "Vacation" that began earlier is returned by Google for every day it covers, and the query only
  returns events overlapping `day`), or timed event with `eventType == "outOfOffice"` whose local
  start day (in `timeZone`) is `day`, whose title `containsPhrase` any of
  `rules.outOfOfficeWords`, or whose `eventType == "outOfOffice"`: `"You're out of office on this
  day (“<title>”)."` with the normalized title, or `(No title)` when it is empty. An all-day "Home" or "Office" matches nothing and gives no notice.

The skill stops and asks in these cases; the app shows the notice, keeps the date, and offers a
"Go to next working day" button (Screens). Nothing is blocked: the user picked the date.

**Task rules** (in `AppCore/Sources/Draft/TaskSelection.swift`, `enum TaskSelection` with
`static func draftTasks(for day:, tasks:, events: [DraftEvent], rules:) -> [DraftTask]` and
`static func draftDelegated(for day:, tasks:) -> [DraftDelegated]`):

- Personal tasks: `status == "needsAction"`, normalized title non-empty, and `due` non-nil (the
  skill only takes dated tasks). Bucket: `due < day` → `.overdue`; `due == day` → `.today`;
  `day < due ≤ day + lookAheadDays` → `.upcoming`; later → not listed.
- An `.upcoming` task with `TaskTitle.isDiscussion(title)` is kept only when
  `discussionName(title)` is non-nil and some event with `isIncluded && hasOtherAttendees` has
  `fold(name)` in its `attendeeFirstNames`, or `rules.personAliases[fold(name)]` in its
  `attendeeEmails`. Kept: `reason = "Kept: <name> is in “<that event's originalTitle>” on this
  day"`, `isIncluded = true`. Not kept: it is still listed with `isIncluded = false` and
  `reason = "To be discussed: no meeting with <name> on this day"` (or `"To be discussed"` when
  the name is nil). Overdue and today discussion tasks are ordinary tasks, as in the skill.
- Order: overdue, then today, then upcoming; inside each, by `due` ascending, then `position`
  (nil last), then input order.
- `text` = normalized title, `notes` = normalized notes or `""`, `dueText` =
  `String(format: "%02d/%02d", due.month, due.day)` (the skill's "MM/DD"; overdue tasks keep their
  real date).
- Delegated: `status == "needsAction"` and a non-empty normalized title; parsed with
  `DelegatedTask.parse(title:notes:)`; `marked = due != nil && due! <= day` written without a
  force unwrap (`due.map { $0 <= day } ?? false`); input order (the layout sorts). Every one is
  included, marked or not.

**`content()`**: `schedule` groups every event with `isIncluded` and a `scheduleSlot` by slot, in
start order; text = their **`originalTitle`s** (the skill keeps the full title on the schedule;
the layout cuts it with "…") joined with `" / "`; `meetingIndex` only when the slot holds exactly
one event and that event has a meeting page, and then it is that event's position within
`meetings`. `meetings` = `title` of events with `includesMeetingPage`, in order. `todoItems` =
included tasks `(text, notes, dueText)`. `delegated` = included items with their `marked`. A to-do
list longer than the grid is cut by the layout from the end, which drops look-ahead tasks first
("if there's room") and lists them under the preview.

### Controller (`AppCore/Sources/Controller/`)

```swift
public struct RenderedAgenda: Equatable, Sendable { public let url: URL; public let pageCount: Int; public let omittedTasks: [String] }
public protocol AgendaRendering: Sendable { func render(_ plan: RenderPlan, fileName: String) async throws -> URL }

@MainActor @Observable
public final class AgendaController {
    public enum Status: Equatable { case starting, needsSetup, signedOut, signingIn, loading, ready, rendering, failed(String) }
    public private(set) var status: Status = .starting
    public private(set) var day: CalendarDay           // starts at today.nextWeekday()
    public private(set) var draft: AgendaDraft?
    public private(set) var settings: AgendaSettings
    public private(set) var calendars: [GoogleCalendar] = []
    public private(set) var taskLists: [GoogleTaskList] = []
    public private(set) var rendered: RenderedAgenda?
    public private(set) var message: String?          // last error or notice shown on the current screen
    public private(set) var clientID: String?         // the entered client ID, for Settings; nil before setup
    public var showsNextWorkingDay: Bool { get }      // draft has a weekend or out-of-office notice
    public init(account: any GoogleAccount, data: any GoogleDataSource, settingsStore: any SettingsStore,
                credentials: any ClientCredentialsStore,
                measurer: any TextMeasuring, renderer: any AgendaRendering, manifest: TemplateManifest,
                timeZone: TimeZone, today: CalendarDay)
    public func start() async            // see below
    public func saveClientCredentials(clientID: String, clientSecret: String) async -> Bool
    public func forgetClientCredentials() async
    public func signIn(authenticate: @escaping @Sendable (URL, String) async throws -> URL) async
    public func signOut() async          // → .signedOut; clears draft, calendars, taskLists, rendered
    public func load() async
    public func setDay(_ day: CalendarDay) async      // then load()
    public func goToNextWorkingDay() async            // setDay(day.nextWeekday())
    public func updateSettings(_ change: (inout AgendaSettings) -> Void) async   // save; load() if calendarIDs, list titles or rules changed
    public func updateDraft(_ change: (inout AgendaDraft) -> Void)
    public func saveShortName(_ title: String, forEvent id: String)   // see below
    public func render() async
}
```

- `load()`: increments a private `loadGeneration: Int` and keeps its value; after every `await`
  it returns without touching any state if `loadGeneration` has changed, so a newer load (a second
  ⌘] press) always wins. Then: `.loading`, `message = nil`, `rendered = nil`. Fetch calendars and task lists.
  Calendars to read = `settings.calendarIDs` that still exist in the list, or `["primary"]` when
  that is empty (the skill reads the primary calendar). To-do list = the first task list whose
  `BinderText.fold(title)` equals `fold(settings.todoListTitle)`; delegated list = the first task list
  other than the to-do list whose folded title equals `fold(delegatedListTitle)`, when that title is
  non-empty. Never fall back
  to another list. Fetch events for each calendar in that order, then the open tasks of each
  matched list, build the draft with `AgendaBuilder(timeZone:rules: settings.rules)`, and append
  to `draft.notices`, after the builder's: `No Google Tasks list named “<todoListTitle>”. Create it
  in Google Tasks or pick another list in Settings.` when the to-do list is missing, and `No Google
  Tasks list named “<delegatedListTitle>”, so there is no delegated page.` when the delegated title
  is non-empty and no such list exists (also when the only match is the to-do list itself). Then `.ready`. `GoogleAPIError.signedOut` → `.signedOut` with
  `message` = its `userMessage`; any other `GoogleAPIError` → `.failed(userMessage)`; any other
  error → `.failed(unexpectedResponse's message)`.
- `showsNextWorkingDay`: true when some notice of the current draft ends with `"is a weekend."`
  or starts with `"You're out of office"`.
- `start()`: loads the stored client credentials (a thrown load counts as none) and calls
  `account.configure(credentials?.configuration)`; sets `clientID`. No usable credentials →
  `.needsSetup`; otherwise signed in → `load()`, else `.signedOut`.
- `saveClientCredentials(clientID:clientSecret:)`: builds `GoogleOAuthConfiguration(clientID:
  clientSecret:)`. Nil → `message = "That isn't a Google client ID. It looks like
  123456789012-abc….apps.googleusercontent.com."` (when the client ID part is the problem, i.e.
  `GoogleOAuthConfiguration(clientID: clientID)` is also nil) or `"The client secret can't contain
  spaces."` (otherwise), returns false, state unchanged. Valid → saves
  `GoogleClientCredentials(clientID: configuration.clientID, clientSecret:
  configuration.clientSecret)` (a save error → `message = "Couldn't save the client in the
  Keychain. Try again."`, false), calls `account.configure(configuration)`, sets `clientID`,
  clears draft, calendars, taskLists and rendered, `message = nil`, and then: signed in (same
  client ID as before, so the session kept its tokens) → `load()`, else `.signedOut`; returns
  true.
- `forgetClientCredentials()`: `signOut()`, deletes the stored credentials (ignoring a delete
  error), `account.configure(nil)`, `clientID = nil`, `.needsSetup`.
- `signIn`: `.signingIn`; success → `load()`; `authorizationCancelled` → `.signedOut`, `message`
  nil; other errors → `.signedOut` with the error's `userMessage`.
- `updateDraft` and `updateSettings` clear `rendered`.
- `saveShortName(title, forEvent:)`: a no-op when there is no draft or no event with that id
  (written with optional chaining, so no unreachable branch); otherwise looks up the event's
  `shortNameKey`; with `n =
  TextFitter.normalized(title)`, sets `settings.rules.shortNames[key] = n` (removes the key when
  `n` is empty), saves the settings, calls `draft.applyShortName(n, key:)`, clears `rendered`. No
  reload.
- `render()`: needs a draft. `.rendering`; plan = `AgendaLayout(manifest:, measurer:, theme:
  settings.theme).plan(for: draft.content())`, computed off the main actor with `await Task.detached
  { layout.plan(for: content) }.value` (both are `Sendable`); url = `renderer.render(plan, fileName:
  "<day.isoString>.pdf")` (the skill's file name, e.g. `2026-09-30.pdf`); `rendered =
  RenderedAgenda(url: url, pageCount: plan.pages.count, omittedTasks:
  plan.omittedTodoItems.map(\.text))`; `.ready`. A renderer
  error → `.ready` with `message = "Couldn't create the PDF. Try again."`.

Fixtures for UI tests and SwiftUI previews (AppCore, public, `GoogleFixtures.swift`):

- `GoogleFixture: String, CaseIterable` — `standard`, `outOfOffice`, `longText`, `overflow`,
  `empty`; `init?(launchArguments: [String])` reads the value after `-MagendaFixture`.
- `FixtureGoogleDataSource` with `public init(_ fixture: GoogleFixture)`: calendars `GoogleCalendar(id: "primary", title: "Work",
  isPrimary: true)` and `GoogleCalendar(id: "family", title: "Family", isPrimary: false)`; task
  lists `GoogleTaskList(id: "todo", title: "Claude")`, `GoogleTaskList(id: "delegated", title:
  "Claude Delegations")` and `GoogleTaskList(id: "other", title: "ToDos")`. Events exist only on
  calendar `primary`, built on the requested day `D` in the requested time zone, status
  `confirmed`, ids `e0`, `e1`, … in the order listed; tasks have ids `t0`, `t1`, … and status
  `needsAction`; `openTasks(listID:)` returns the to-dos for `"todo"`, the delegated tasks for
  `"delegated"`, and one task titled "Wrong list" (due `D`) for `"other"`, which must never appear.
  "Self" below is `GoogleAttendee(email: "me@example.com", displayName: "Me", isSelf: true,
  isResource: false, responseStatus: "accepted")`; another person *x* is
  `GoogleAttendee(email: "<x>@example.com", displayName: nil, isSelf: false, isResource: false,
  responseStatus: "accepted")`; the room is `"room-1@resource.calendar.google.com"` with
  `isResource: true`. Unless stated, an event's `selfResponse` is self's `responseStatus` (nil when
  self is not an attendee), `iCalUID`, `recurringEventID` and `eventType` are nil, and a task's
  `notes` and `position` are nil.
  - `standard` events: an all-day "Home"; 08:00 "Start the day" (no attendees); 09:00 "Team sync"
    (self, anna, room); 10:30 "1:1 with Peter" (self, `peter.brown`); 12:00 "Lunch" (no
    attendees); 13:00 "REMINDER // Decision about the office move" (self, ben;
    `recurringEventID: "rec-office"`); 14:00 "Server upgrade" (self with `responseStatus:
    "declined"`, ops; `selfResponse: "declined"`); 15:00 "Week preparation" (self only); 16:00
    "Quarterly Summit" (self, anna); 16:30 "Quarterly Summit" (self, anna); 19:00 "Dinner with
    partners" (self, partner). To-dos: "Send the slides" with notes "Ask Ben for the Q3 numbers
    first" due `D − 2`; "Call the bank" due `D`; "Nora - to be discussed" due `D + 1`; "Peter –
    to be discussed" due `D + 2`; "Book flights" due `D + 3`; "Renew passport" due `D + 9`;
    "Someday" with no due. Delegated: "Anna: Hire a designer", notes `"#weekly\n2026-09-16
    Delegated to Anna.\n2026-09-23 Interviews scheduled.\n2026-09-29 Two candidates left."`, due
    `D`; "Ben: Renew the office lease", notes `"#monthly\n2026-09-01 Waiting for the landlord."`,
    due `D + 10`; "Fix the printer", no notes, no due.
  - `outOfOffice`: an all-day "Vacation" and a timed 10:00 "Team sync" (self, anna); no tasks.
  - `longText`: events at 08:00, 09:30, 11:00, 13:30, 15:00, 17:30 titled `longStrings[0]` …
    `longStrings[5]`, each with self and anna; to-dos titled `longStrings[0]` … `longStrings[5]`,
    notes `longStrings[6]`, due `D`; three delegated tasks titled `longStrings[1] + ": " +
    longStrings[0]`, `longStrings[1] + ": " + longStrings[3]` and `"Owner: " + longStrings[2]`,
    each with notes `"#weekly\n" + longStrings[0] + "\n" + longStrings[2] + "\n" +
    longStrings[3]`, due `D`.
  - `overflow`: 22 events, event *i* at hour `8 + i / 2`, minute `(i % 2) * 30`, titled
    `"Meeting " + String(i) + ": " + longStrings[1]` (distinct titles, so none is a duplicate),
    each with self and anna; 30 to-dos titled `longStrings[0]`, notes `longStrings[6]`, due `D`;
    40 delegated tasks titled `"Alexandra Montgomery-Smith: Delegated task " + String(i) + " " +
    longStrings[0]` with notes `"#" + ["daily", "weekly", "monthly"][i % 3]` + five lines of
    `longStrings[0]`, each preceded by `"\n"`, due `D` when `i % 4 == 0`, else `D + 7`.
  - `empty`: the calendars and lists above, no events, no tasks.
- `FixtureGoogleAccount: GoogleAccount` (actor) — `init(signedIn: Bool)`; `signIn` succeeds without
  calling `authenticate`.

For `standard` on `D = 2026-09-30` with default settings the draft is exactly this (the builder,
controller and UI tests assert it). Events, in start order (n = row index): 0 "Start the day"
(Personal block), 1 "Team sync" (page), 2 "1:1 with Peter" (page), 3 "Lunch" (Personal block), 4
"REMINDER // Decision about the office move" (page titled "Decision about the office move"), 5
"Server upgrade" (Declined), 6 "Week preparation" (included, no page), 7 "Quarterly Summit" 16:00
(page), 8 "Quarterly Summit" 16:30 (Duplicate), 9 "Dinner with partners" (page, not on the
schedule); "Home" is not listed. Tasks: 0 "Send the slides" (Overdue, 09/28), 1 "Call the bank"
(Due today, 09/30), 2 "Nora - to be discussed" (left out), 3 "Peter – to be discussed" (kept,
Peter is in "1:1 with Peter"), 4 "Book flights" (Upcoming, 10/03). Delegated: 0 "Hire a
designer" (Anna, Weekly, marked, status ["2026-09-23 Interviews scheduled.", "2026-09-29 Two
candidates left."]), 1 "Renew the office lease" (Ben, Monthly, not marked), 2 "Fix the printer"
(no owner, Daily, both warnings). No notices. `content().meetings` is ["Team sync", "1:1 with
Peter", "Decision about the office move", "Quarterly Summit", "Dinner with partners"];
`content().todoItems` has 4 items (Nora is left out); the schedule has entries in slots 2, 5, 10, 14 and 16
("Team sync", "1:1 with Peter", "REMINDER // Decision about the office move", "Week
preparation", "Quarterly Summit").

### App (`App/`)

**Template and fonts** (`App/Resources/Template/chrome.pdf`, `App/Resources/Fonts/*.ttf`,
`App/Resources/Fonts/OFL-Outfit.txt`, `OFL-Roboto.txt`, `OFL-JetBrainsMono.txt`): byte copies of
the Python repo's files at the pinned commit; the OFL texts are
`https://raw.githubusercontent.com/google/fonts/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/{outfit,roboto,jetbrainsmono}/OFL.txt`.

**Rendering** (`App/Rendering/`):

- `FontLibrary` (final class): `init(bundle: Bundle) throws` loads all 15 TTFs once with
  `CTFontManagerCreateFontDescriptorFromData`; a missing file or a nil descriptor throws
  `FontLibraryError.missingFont(String)` (the enum also has `case missingTemplate`). `func font(_ spec: FontSpec) -> CTFont`. Fonts are never
  registered system-wide. It and `CoreTextMeasurer` hold only immutable CoreText objects; if the
  compiler rejects their `Sendable` conformance, mark them `@unchecked Sendable` with a comment
  saying why (immutable, and CoreText fonts are thread-safe).
- `CoreTextMeasurer: TextMeasuring`, `init(library: FontLibrary)`: width = `CTLineGetTypographicBounds` of a `CTLine` made from
  the string with that `CTFont` (CoreText's font fallback covers emoji, CJK and Arabic); metrics
  = `CTFontGetAscent` / `CTFontGetDescent`.
- `PDFAgendaRenderer: AgendaRendering`, `init(library: FontLibrary, bundle: Bundle) throws`: loads
  `chrome.pdf` from the bundle as a `CGPDFDocument` once and throws
  `FontLibraryError.missingTemplate` when it is absent or unreadable. `UIGraphicsPDFRenderer` with bounds 595.304 × 841.890.
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
- `KeychainClientCredentialsStore: ClientCredentialsStore`: generic password, service
  `name.felhasznalo.magenda.google-client` (an init parameter), account `client`, JSON-encoded
  `GoogleClientCredentials`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Shares a private
  Keychain helper with `KeychainTokenStore` (`App/Platform/KeychainItem.swift`).
- `App/PrivacyInfo.xcprivacy`: `NSPrivacyTracking` false, no tracking domains, no collected data
  types, accessed API type `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`.
- No client ID, client secret, project number or account name is ever committed, and nothing reads
  a client from the bundle.

**Wiring** (`App/AppEnvironment.swift`):
`static func makeController(arguments: [String], bundle: Bundle) throws -> AgendaController`. It
loads `TemplateManifest.bundled()` and `FontLibrary(bundle:)` first (their errors propagate).
With `GoogleFixture(launchArguments: arguments)` non-nil: `FixtureGoogleAccount(signedIn:
!arguments.contains("-MagendaSignedOut"))`, `FixtureGoogleDataSource(fixture)`,
`InMemoryClientCredentialsStore(arguments.contains("-MagendaNeedsSetup") ? nil :
GoogleClientCredentials(clientID: "123456789012-fixture.apps.googleusercontent.com",
clientSecret: nil))`,
`InMemorySettingsStore(AgendaSettings())` (the defaults name the fixture's "Claude" and "Claude
Delegations" lists; `AgendaSettings` has a public init with every field defaulted),
`TimeZone.current`, today 2026-09-29, so the first day shown is 2026-09-30. Otherwise:
`GoogleSession(configuration:http:tokens:hasher:now:)` with `URLSessionHTTPClient`,
`KeychainTokenStore`, `CryptoKitHasher` and `{ Date() }`, created with `configuration: nil`
(`start()` configures it from the Keychain), as both the account and the sender of a
`LiveGoogleDataSource`. Live branch only: `KeychainClientCredentialsStore()`,
`UserDefaultsSettingsStore(defaults: .standard)` and `CalendarDay.today(in:
.current, now: Date())`. Shared by both: `CoreTextMeasurer(library:)`, `PDFAgendaRenderer(library:
bundle:)` (its error propagates too) and `TimeZone.current`.
`MagendaApp` holds the controller in `@State`, injects it with `.environment`, adds
`.commands { AgendaCommands(controller: controller) }` (`AgendaCommands` takes an optional
controller and disables every item when it is nil), calls `start()` in `.task`, and shows `RootView(appInfo:)` with the `AppInfo` it already builds today; `RootView`
passes it to `AgendaView(appInfo:)`, which passes it to `SettingsView(appInfo:)` for the version
row. If `makeController` throws, it shows only
`Text("Couldn't load the agenda template. Reinstall Magenda.")` with identifier `templateError`.

**Screens** (`App/Screens/`, one per file, each with an `ID` enum and a `#Preview` using the
fixtures). The app is designed for iPad first and also runs on iPhone (`TARGETED_DEVICE_FAMILY`
stays `"1,2"`); layouts go by size class and available width, never by device model.

| File | Shows | Identifiers |
|---|---|---|
| `RootView.swift` | `.starting` → `ProgressView`; `.needsSetup` → SetupView; `.signedOut`/`.signingIn` → SignInView; otherwise AgendaView | — |
| `SetupView.swift` | Used full screen for `.needsSetup` and as a sheet from Settings. Centered, maximum width 480 pt. Title "Connect Google"; text "Magenda reads your calendar and tasks through your own Google Cloud OAuth client. Create an iOS client for the bundle ID name.felhasznalo.magenda, then enter it here."; `Link("How to create a client", destination: URL(string: "https://github.com/andras-tkcs/magenda-ios#google-cloud-setup"))`; `TextField` "Client ID" (no autocorrection, no autocapitalization, `.keyboardType(.asciiCapable)`); `SecureField` "Client secret (optional)"; footnote "Leave the secret empty for an iOS client. Both stay in this device's Keychain and are never sent anywhere but Google."; button "Save" (disabled while the client ID field is blank; Return in either field submits) calling `controller.saveClientCredentials`; `message` below in red when the save fails. As a sheet, prefilled with the current client ID (secret left empty, so it must be re-entered when one is used) and dismissed on success, with a "Cancel" button. | `clientIDField`, `clientSecretField`, `saveClientButton`, `setupMessage`, `setupHelpLink`, `setupCancel` |
| `SignInView.swift` | Title "Magenda"; text "Make a printable agenda from your Google Calendar and Google Tasks."; button "Sign in with Google" (disabled while signing in); `message` below in secondary style | `signInButton`, `signInMessage` |
| `AgendaView.swift` | A `NavigationSplitView(columnVisibility:preferredCompactColumn:)` with `columnVisibility` starting at `.all` and `.navigationSplitViewStyle(.balanced)`, so an iPad in portrait shows the list and the preview side by side instead of hiding the list. **Sidebar** (`.navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 560)`): the review `List`. Toolbar placements: "Render" button in `.primaryAction` (disabled unless `.ready` with a draft); Settings gear (label "Settings", `.keyboardShortcut(",", modifiers: .command)`, opens SettingsView as a `.sheet`) in `.topBarLeading`; a `ToolbarItemGroup(placement: .bottomBar)` with "Previous day" (`chevron.left`), a `DatePicker` "Date" (date only, `.datePickerStyle(.compact)`) and "Next day" (`chevron.right`). List sections, in order: "Notices" (only when `draft.notices` is non-empty: one `Text` per notice, then a "Go to next working day" button when `showsNextWorkingDay`), "Schedule and meetings", "To-do list", "Delegated" (only when the draft has delegated items). `.loading` shows `ProgressView`; `.failed(message)` shows the message and a "Try again" button; `.rendering` shows `ProgressView("Rendering…")`; `message`, when set while `.ready`, shows under the toolbar. Pull to refresh calls `load()`. **Detail**: PreviewView when `rendered` is set, else `ContentUnavailableView("No PDF yet", systemImage: "doc.richtext", description: Text("Tap Render to see the agenda."))`. After a successful render `preferredCompactColumn` becomes `.detail`, so in compact width (iPhone, narrow iPad window) the preview is pushed and Back returns to the list; in regular width the preview simply appears beside the list. | `agendaScreen` (the List), `previousDayButton`, `datePicker`, `nextDayButton`, `settingsButton`, `renderButton`, `notice.<n>`, `nextWorkingDayButton`, `loadingIndicator`, `errorMessage`, `retryButton`, `previewPlaceholder`, row identifiers below (n = 0-based position) |
| `AgendaCommands.swift` | `struct AgendaCommands: Commands` added with `.commands` in `MagendaApp`: a `CommandMenu("Agenda")` with "Render" (⌘R; enabled when status is `.ready` and `draft != nil`), "Previous Day" (⌘[), "Next Day" (⌘]) and "Reload" (⌘⇧R) (each enabled when status is `.ready` or `.failed`), and "Next Working Day" (⌘⌥]; enabled under the same condition and `showsNextWorkingDay`), each calling the controller. This puts them in the iPad menu bar and the ⌘-hold shortcut list. | — |
| `EditTextSheet.swift` | Title "Edit text"; multi-line `TextField` (1…5 lines); for an event, under it the original title as a caption ("Calendar title: <originalTitle>") and a `Toggle` "Use this name for this meeting every time" (off by default); "Done" saves (with the toggle on, through `controller.saveShortName`, otherwise `setTitle`), "Cancel" discards; footer "Changes only affect this agenda. Nothing is changed in Google." (with the toggle on: "Saved in Settings → Short meeting names. Nothing is changed in Google."). The field is `TextField(axis: .vertical)`, so Return types a line break, which normalizing turns into a space; "Done" has `.keyboardShortcut(.defaultAction)` (⌘Return) and "Cancel" `.keyboardShortcut(.cancelAction)` (Esc). | `editField`, `editRemember`, `editDone`, `editCancel` |
| `PreviewView.swift` | `PDFKitView` (a `UIViewRepresentable` around `PDFView`, `autoScales`, single page continuous); toolbar `ShareLink(item: url)` labelled "Share PDF" (the system share sheet: Noteshelf, Files, AirDrop, Print…); when `omittedTasks` is non-empty a banner, one accessibility element (`.accessibilityElement(children: .combine)`), reading "1 task didn't fit on the to-do list and was left out:" or "<n> tasks didn't fit on the to-do list and were left out:", followed by their texts, `lineLimit(3)` each | `pdfPreview`, `shareButton`, `omittedTasksBanner` |
| `SettingsView.swift` | A `NavigationStack` `Form` with a "Done" button. Sections "Calendars" (multi-select checkmarks; footnote "None selected uses your primary calendar."), "Task lists" (Picker "To-do list" over the task list titles, storing the title; Picker "Delegated tasks" with "None" (stores `""`) first and the to-do list excluded; footnote "Lists are found by name, so renaming one in Google Tasks means picking it again here."), "Look" (three rows "Outfit", "Roboto", "JetBrains Mono", each a button showing a checkmark when selected; five rows "Weekend", "Date heading", "Section labels", "Accent", "Notes heading", each a color swatch and a hex `TextField` that saves on submit when `RGBColor(hex:)` accepts it and otherwise shows "Use six hex digits, like 215E99."; button "Reset colors"), a `NavigationLink` "Binder rules" to RulesView, "Google client" (the client ID with `.truncationMode(.middle)` and `.textSelection(.enabled)`; button "Change client…" opening SetupView as a sheet; button "Forget client" with role `.destructive` and a `confirmationDialog` "Forget this Google client? You'll need to enter a client ID again." calling `forgetClientCredentials`), "Account" (button "Sign out"), "About" (version row as today, footnote "Fonts: Outfit, Roboto and JetBrains Mono, under the SIL Open Font License 1.1.") | `calendarRow.<n>`, `todoListPicker`, `delegatedListPicker`, `fontOption.<rawValue>`, `colorField.<role>` (weekend, heading, label, accent, notes), `colorError`, `resetColorsButton`, `rulesLink`, `clientIDLabel`, `changeClientButton`, `forgetClientButton`, `signOutButton`, `version`, `settingsDone` |
| `RulesView.swift` | A `Form`. Sections, each with a footnote: "Personal blocks" (footnote "Events whose title starts with one of these are left off the agenda."), "Title prefixes" ("Removed from the start of meeting-page titles."), "Out-of-office words" ("An all-day event with one of these in its title shows a notice."), each an editable list of strings: rows with swipe-to-delete, and a `TextField` "Add…" that appends on submit (trimmed; blank or a duplicate after `BinderText.fold` is ignored); "Short meeting names" (one row per entry, showing the short name and, as a caption, "Recurring meeting" for an `r:` key or the folded calendar title for a `t:` key; swipe to delete; footnote "Set from a meeting's Edit sheet."); "People" (rows "<key> → <email>", swipe to delete, two fields "Name in tasks" and "Email" and an "Add" button that stores `personAliases[BinderText.fold(name)] = email` trimmed and lowercased, ignored when either field is blank; footnote "Matches “Name – to be discussed” tasks to meeting attendees whose first name differs."); "Look-ahead" (`Stepper` "Upcoming tasks: <n> days", 0…14). Every change goes through `controller.updateSettings`. "Reset rules" restores `BinderRules.default` except `shortNames` and `personAliases`. | `rulesRow.<section>.<n>` (section = personalBlocks, titlePrefixes, outOfOfficeWords, shortNames or people; n = 0-based row), `rulesAdd.<section>` (the "Add…" field; for people, `peopleName`), `peopleName`, `peopleEmail`, `peopleAdd`, `lookAheadStepper`, `resetRulesButton` |

Rows, in `AgendaRows.swift`. Each row is an `HStack`: the leading part is a `Button` (identifier
`eventRow.<n>` / `taskRow.<n>` / `delegatedRow.<n>`) holding the title `Text` with
`.lineLimit(2)` and `.truncationMode(.tail)` and secondary lines; tapping it opens `EditTextSheet`
(for events it edits the meeting-page title). That button's `accessibilityLabel` is the full,
untruncated title. The trailing part is a `Toggle` "Include" (identifier `eventToggle.<n>` /
`taskToggle.<n>` / `delegatedToggle.<n>`, accessibility label "Include <title>"). The row is not
combined into one accessibility element; it has `.hoverEffect()` on the button and a
`.contextMenu` with "Edit…" and "Include"/"Leave out".

- Event: title = `originalTitle`; secondary: `timeText`; then `reasons.joined(separator: " · ")`
  when non-empty (identifier `eventReason.<n>`); then, only while included, a `Toggle` "Notes
  page" (identifier `eventPageToggle.<n>`, accessibility label "Notes page for <title>"). A
  left-out event's title is in `.secondary` style.
- Task: title = `text`, then `notes` in one secondary line (`lineLimit(1)`); secondary:
  `"<bucket.label> · <dueText>"`, then `reason` when set (identifier `taskReason.<n>`).
- Delegated: title = `text`; secondary: `"<owner> · <cadence.label>"` (owner omitted when
  empty), a "Check-in due" capsule when `marked` (identifier `delegatedMarked.<n>`), the status
  lines in `.secondary` style, and `warning` in orange when set.

Multiple windows: the one `AgendaController` lives in `MagendaApp`'s `@State`, so every iPad
window shows the same agenda; there is no per-window state, and all mutation is on the main actor.
No Pencil or drag-and-drop support: the app edits text and hands the PDF to the share sheet,
where Noteshelf takes over.

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
- **Delegated tasks stored in the app, or a new notes format.** The user already keeps them in
  the "Claude Delegations" list in the `Owner: Task` / `#cadence` / dated-log format the skill
  reads; the app reads that format unchanged.
- **A client ID committed to the repository** (a bundled text file, `project.yml` or an Info.plist
  key). The repository is public and the owner does not want any organization's Google project in
  it; every user brings their own client. Rejected for entry in the app, stored in the Keychain.
- **A client ID injected at build time** (an `.xcconfig` filled from a CI secret). Builds from the
  same source would then differ per person, and release archives would carry one person's client.
  Rejected for the same runtime entry.
- **An on-device language model (Apple Foundation Models) to shorten one-off titles or spot
  personal blocks.** The user asked for no AI at all; it would also make the output depend on a
  model version and on iOS 26 hardware. Rejected for the strip list, saved short names, the "…" cut
  and a manual edit.
- **Personal blocks found by calendar color or a tag.** Colors are per-user display settings that
  other tools change, and a tag means editing every recurring event. Rejected for an editable
  title-prefix list, defaulting to the skill's two examples.
- **Wrapping or shrinking long meeting titles.** Wrapping is the Magenda bug that broke the page;
  shrinking a 20 pt title makes pages inconsistent. Rejected for one line cut with "…".
- **Undated tasks on the to-do list.** The skill takes only overdue, due-today and next-5-days
  tasks; an undated task has no place in that order. Left out, as in the skill.
- **Task lists chosen by ID.** The skill looks them up by title on every run because IDs can
  change; settings store the title.
- **Blocking a weekend or out-of-office date** (the skill stops and asks). In the app the user
  picks the date, so the app shows a notice and a "Go to next working day" button instead.
- **Uploading to Google Drive.** The user imports into Noteshelf from the share sheet; Drive
  upload would add a write scope for nothing.
- **Duplicates by title across the whole day.** Two separate "Team sync" events at 09:00 and 15:00
  are real; the observed duplicate started 30 minutes after the first. Rejected for "same title,
  starting less than 120 minutes after an earlier kept one", with the same iCalUID always a
  duplicate.
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
  are read-only `calendar.readonly` and `tasks.readonly`; no Google client ships with the app: the
  user enters their own client ID (and optional secret) on first launch and it is kept in the
  Keychain, so the public repository holds no project-specific value.
- **0014** — The agenda's inputs are read live from the Google Calendar and Google Tasks REST APIs,
  not EventKit (which syncs late); task lists are found by title ("Claude", "Claude Delegations");
  delegated tasks use the existing `Owner: Task` title, `#cadence` first line and dated log.
- **0015** — AppCore may import the toolchain's `Observation` module (it ships with Swift on Linux)
  so the `@Observable` controller is tested on Linux; this amends ADR 0007's "Foundation at most".
  Rejected: keeping the controller in `App/` (untested on Linux) or a hand-written observer.
- **0016** — What goes on the agenda is decided by fixed, user-editable rules in AppCore
  (`BinderRules`: personal-block prefixes, title prefixes, out-of-office words, saved short names,
  person aliases, look-ahead days) and never by a language model, on or off the device; every
  left-out item is shown with its reason instead of a summary.

## Manual steps

Step-by-step page: https://claude.ai/artifact/DZxBnKphSDuV8PDN5XCo6t (source
`docs/google-agenda-pdf-plan-manual-steps.html`).

- **Before** (`manual_before`): nothing. No phase talks to Google: every test runs against fakes
  and fixtures, and the app ships without a client.
- **After** (`manual_after`): create your own Google Cloud project with the Calendar and Tasks APIs
  enabled, an OAuth consent screen with the two read-only scopes ("Internal" if the project belongs
  to your Google Workspace organization, otherwise "External" in Testing mode) and an iOS OAuth
  client for `name.felhasznalo.magenda`; on a real iPad, enter the client ID in the app, sign in,
  render, preview and share into Noteshelf 3; compare the app's agenda with a binder the Claude
  workflow built for the same date; check long titles and the largest text size in a narrow and a
  full-screen window; check the delegated page; set the App Store Connect privacy answers. The
  client ID is typed into the app only; it never goes into the repository, the PR or the
  checklist.

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
- **Google Workspace policy.** If the account is on a Google Workspace whose admin restricts
  third-party apps, sign-in fails with an "access blocked" page until the admin trusts the client
  ID (Admin console → Security → API controls). That shows up in ma1, not in CI; the fix is an
  admin setting, not code.
- **`String.folding(options:locale:)` on Linux.** `BinderText.fold` relies on it. If the `core`
  job shows "Zoltán" not folding to "zoltan", stop blocked with the test output; do not hand-roll a
  diacritic table.
- **Fixture expectations.** The `standard` fixture's expected draft is spelled out under
  "Controller". If the builder produces something else and the rules as written agree with the
  builder, the expectation paragraph is wrong: stop blocked and quote both, rather than bending the
  rules to the fixture.
- **Google consent in Testing mode** (an "External" consent screen) expires refresh tokens after 7 days; the app then shows
  "Your Google sign-in expired. Sign in again." An "Internal" consent screen does not have this
  limit; publishing and verifying an external app is outside this plan.
- **No client in CI.** UI tests run with `-MagendaFixture`, which supplies a fixture client ID in
  memory; `-MagendaNeedsSetup` exercises the setup screen. Live sign-in is only checked by hand in
  manual_after. A phase that finds itself needing a real client ID stops blocked; it never commits
  one.
- **Coverage at 100%.** A phase that cannot reach a line from a test restructures the code so the
  failing input can be injected; it never lowers a floor.

## Implementation manifest

```yaml
plan_slug: google-agenda-pdf
feature_branch: feature/google-agenda-pdf
max_parallel: 2
manual_steps_artifact: https://claude.ai/artifact/DZxBnKphSDuV8PDN5XCo6t
manual_steps_source: docs/google-agenda-pdf-plan-manual-steps.html
manual_before: []
manual_after:
  - id: ma1-google-cloud-client
    title: In your own Google Cloud project, enable the Calendar and Tasks APIs, configure the OAuth consent screen with the two read-only scopes, and create an iOS OAuth client for name.felhasznalo.magenda
    why: The app ships without a Google client; live sign-in (ma2 onwards) needs one. Its client ID is typed into the app on the iPad and is never committed.
  - id: ma2-ipad-setup-sign-in-render-share
    title: On a real iPad, enter the client ID on the "Connect Google" screen, sign in, render tomorrow's agenda, check the preview beside the list and share the PDF into Noteshelf 3
    why: The setup screen with a real client, ASWebAuthenticationSession against real Google (and any Workspace policy), the Keychain on a device and the share sheet into Noteshelf cannot run in CI.
  - id: ma3-parity-with-claude-binder
    title: Pick a date the Claude binder workflow already built and compare the app's agenda with that PDF item by item (schedule, meeting pages, to-dos, delegated rows and marks)
    why: Confirms the deterministic rules reproduce the workflow on real data; every difference is either an intended rule (named in the PR) or a bug.
  - id: ma4-long-text-windows
    title: With real data containing long titles, check the app at the largest Dynamic Type size in a narrow Stage Manager window and full screen, and check the rendered PDF
    why: Confirms the audited layout and the split view with real accounts and real fonts as a person sees them.
  - id: ma5-delegated-list
    title: Check the delegated page against the "Claude Delegations" list (owners, cadence, last two log lines, marks for check-ins due)
    why: Confirms the parser against the real list.
  - id: ma6-app-store-privacy
    title: Set App Store Connect's App Privacy answers to "Data Not Collected"
    why: The app reads Google data only on the device and sends nothing to the developer; App Store Connect needs the answer before review.
verify_after_merge:
  - swift test --package-path AppCore --enable-code-coverage && python3 scripts/check_coverage_floor.py "$(swift test --package-path AppCore --show-codecov-path)"
  - dispatch tests.yml on feature/google-agenda-pdf
final_checks:
  - docs/google-agenda-pdf-plan.md and docs/google-agenda-pdf-plan-manual-steps.html are deleted and nothing links to them
  - ADRs 0011, 0012, 0013, 0014, 0015 and 0016 exist, are Accepted, and are in docs/adr/README.md's index
  - CHANGELOG.md has [Unreleased] entries and no version heading
  - AppCore/Sources/Greeting.swift, App/ContentView.swift and AppUITests/MainScreenUITests.swift are gone
  - no real Google client ID, client secret or organization name is in the repository (the only client IDs are the made-up ones in tests and fixtures)
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
         and 1 for 2027-01-04; adding(days:) across a month and a year end; nextWeekday() from
         Thursday 2026-10-01 is 2026-10-02, from Friday 2026-10-02 and from Saturday 2026-10-03
         is Monday 2026-10-05; today(in:now:) for a
         fixed Date in two time zones that disagree on the day; startDate(in:)).
         CalendarMathTests, parameterized: header(for: 2026-10-01) gives "1 THURSDAY", "CW 40",
         "OCTOBER", "2026", [28,29,30,1,2,3,4]; nextFourWeeks(from: 2026-10-01) gives CW 40–43 with
         the Python output's day numbers (28…4, 5…11, 12…18, 19…25); a year boundary
         (2026-12-30 → CW 53, 1, 2, 3). ScheduleSlot.index: (8,0)→0, (8,29)→0, (8,30)→1, (18,59)→21,
         (7,59)→nil, (19,0)→nil. AgendaContentTests: Cadence labels; TodoItem keeps text, notes
         and due; sortedForPage keeps input
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
         target. Change nothing else in the file.
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
      - build.yml dispatched on the phase branch is green (AppCore/Package.swift now ships a resource bundle in the archive; link the run in the phase's report)
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
         and its rows grow by the formula; a title with notes draws "<title>:" lines followed by
         exactly one notes line that ends with "…" when the notes are long (longStrings[6]), and
         a title with empty notes draws no colon and no notes line; separators are drawn at every row top except the
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
         and rejects uppercase, a missing prefix, a trailing path, an empty string; a client
         secret "  test-secret-abc  " is trimmed, "" and "   " become nil, "a b" and a 201-character
         secret make the init nil; token and refresh bodies contain client_secret right after
         client_id when a secret is set and no client_secret field when it is nil; redirect scheme
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
         GoogleClientCredentials, ClientCredentialsStore, InMemoryClientCredentialsStore,
         GoogleAccount and GoogleSession (configuration optional, configure(_:), isConfigured()),
         behaving exactly as listed. The in-flight refresh is a `Task<OAuthTokens, Error>?` stored on the actor and
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
         revoke fails or delete throws; with configuration nil, isConfigured and isSignedIn are
         false and signIn and send throw .notConfigured without any request; configure with a
         different client ID deletes stored tokens without a revoke request, the same client ID
         with a new secret keeps them; GoogleClientCredentials.configuration is nil for an invalid
         ID; InMemoryClientCredentialsStore save, load and delete. All client IDs in tests are
         made up.
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
      1. AppCore/Sources/Google/GoogleModels.swift: GoogleCalendar, EventStart, GoogleAttendee, GoogleEvent,
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
         nextPageToken, and events carrying attendees and recurringEventId), events-page2.json, events-all-day.json, task-lists.json, tasks.json,
         tasks-malformed.json, in Google's documented response shapes (fields as named in the
         Design). Only made-up names and addresses. No "#" followed by digits in any string
         (scripts/tests/test_no_project_history.py scans .json files).
      5. AppCore/Tests/Support/FakeSender.swift: an AuthorizedHTTPSending fake (final class with
         an NSLock) recording requests and returning queued responses or errors.
      6. Tests: exact request URLs, including a calendar ID "a#b@group.calendar.google.com"
         percent-encoded in the path and, for time zone Europe/Budapest and day 2026-09-30,
         timeMin=2026-09-29T22:00:00Z and timeMax=2026-09-30T22:00:00Z with no "+" anywhere in
         the URL; two-page paging; the 10-page cap; all-day vs timed starts with and without
         fractional seconds; an event with neither start form is skipped; selfResponse; attendees
         (self, a person, a room flagged by `resource: true`, a room recognised only by its
         "@resource.calendar.google.com" address, an entry with no email skipped, no attendees
         key → []); recurringEventID; title
         fallbacks for calendars; due parsing for tasks; malformed body → .unexpectedResponse;
         a sender error passes through; LiveGoogleDataSource forwards each call. If the core job
         (Linux) encodes the "#" in the calendar ID differently from the test's expected URL,
         stop blocked with the actual URL; do not loosen the assertion.
      7. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "GoogleCalendarClientTests|GoogleTasksClientTests" passes on the core job (Linux)
      - the core job's coverage floor step passes at 100%
      - the lint job passes
      - python3 -m unittest discover -s scripts/tests passes
  - id: p9a-settings-and-title-rules
    title: Agenda settings with binder rules, text folding, and meeting-page title rules
    depends_on: [p1-calendar-and-content, p2-text-fitting]
    complexity: M
    touches:
      - AppCore/Sources/Settings/AgendaSettings.swift
      - AppCore/Sources/Settings/BinderRules.swift
      - AppCore/Sources/Settings/BinderText.swift
      - AppCore/Sources/Settings/MeetingTitle.swift
      - AppCore/Tests/Settings/AgendaSettingsTests.swift
      - AppCore/Tests/Settings/BinderTextTests.swift
      - AppCore/Tests/Settings/MeetingTitleTests.swift
    brief: |
      Read the plan's "Current state" part "The daily-binder skill" and the Design section
      "Settings and binder rules" up to, not including, `TaskTitle`.
      1. AppCore/Sources/Settings/BinderRules.swift: BinderRules with the exact defaults, tolerant
         decoding (a custom init(from:) using decodeIfPresent for every field).
      2. AppCore/Sources/Settings/AgendaSettings.swift: AgendaSettings (with theme), SettingsStore,
         InMemorySettingsStore (NSLock, as the Design says), tolerant decoding as specified.
      3. AppCore/Sources/Settings/BinderText.swift: fold, startsWithPhrase, containsPhrase exactly
         as specified. "Letter or digit" is Character.isLetter || Character.isNumber.
      4. AppCore/Sources/Settings/MeetingTitle.swift: key, stripped, pageTitle exactly as
         specified.
      5. Tests (Swift Testing, parameterized where a table fits): AgendaSettingsTests — defaults
         ("Claude", "Claude Delegations", BinderRules.default values); JSON round trip; unknown
         fontPack decodes to .outfit; {"todoListTitle":"x"} decodes with every other default; a
         "rules" object holding only {"lookAheadDays":3} keeps the other rule defaults; theme
         mirrors fontPack and colors; InMemorySettingsStore save then load. BinderTextTests —
         fold("Zoltán") == fold("ZOLTAN") == "zoltan", fold("  Árvíztűrő\ttükörfúrógép ") ==
         "arvizturo tukorfurogep"; startsWithPhrase: "Lunch" vs "Lunch", "lunch with Sam",
         "Lunch: team" (true) and "Lunchtime", "Team lunch" (false); "FW:" vs "FW:Budget" (true);
         empty phrase (false); containsPhrase: "OOO" in "OOO - Budapest", "Vacation" in "Summer
         vacation", "Out of Office" in "Out of office (Nora)" (true), "PTO" in "Photography",
         "Home" with every default out-of-office word (false). MeetingTitleTests — every example
         listed under MeetingTitle in the Design, verbatim; key for a recurring and a one-off
         event; pageTitle prefers a non-empty short name and ignores a blank one.
      6. If fold("Zoltán") is not "zoltan" on the core job (Linux), stop blocked with the output
         (see the plan's Risks).
      7. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "AgendaSettingsTests|BinderTextTests|MeetingTitleTests" passes on the core job (Linux)
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p9b-task-and-delegated-parsing
    title: Discussion-task detection and the delegated-task parser
    depends_on: [p9a-settings-and-title-rules]
    complexity: S
    touches:
      - AppCore/Sources/Settings/TaskTitle.swift
      - AppCore/Sources/Settings/DelegatedTask.swift
      - AppCore/Tests/Settings/TaskTitleTests.swift
      - AppCore/Tests/Settings/DelegatedTaskTests.swift
    brief: |
      Read the Design section "Settings and binder rules" from `TaskTitle` to the end of that
      section, and the skill's rule 6 under "Current state".
      1. AppCore/Sources/Settings/TaskTitle.swift: isDiscussion and discussionName exactly as
         specified, with NSRegularExpression.
      2. AppCore/Sources/Settings/DelegatedTask.swift: DelegatedTask (owner, text, cadence,
         status, warning) and parse(title:notes:) with the exact rules and warning strings.
      3. Tests, parameterized: TaskTitleTests — "Peter – to be discussed" (name "Peter"),
         "Zoltán - TBD" ("Zoltán"), "Nora: to be discussed" ("Nora"), "TBD" (discussion, nil
         name), "Prepare TBD list" (discussion, nil name), "Call the bank" (not a discussion),
         "Todo: be discussed later" (not a discussion). DelegatedTaskTests — the Design's
         Sam example (status = the last two log lines); one log line; no log lines; "#Weekly"
         in another case; no cadence line (Daily, warning, the first line counts as log); no
         colon in the title; ": Task" and "Owner:" (empty part); title with two colons
         ("Anna: Fix: the printer" → owner "Anna", text "Fix: the printer"); both warnings joined
         with one space; nil title and notes.
      4. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "TaskTitleTests|DelegatedTaskTests" passes
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p10a-event-selection
    title: Event selection rules, reasons and the weekend / out-of-office notices
    depends_on: [p8b-google-clients, p9a-settings-and-title-rules]
    complexity: M
    touches:
      - AppCore/Sources/Draft/DraftEvent.swift
      - AppCore/Sources/Draft/EventSelection.swift
      - AppCore/Tests/Draft/EventSelectionTests.swift
    brief: |
      Read the Design section "From Google data to a draft": the code block's EventExclusion and
      DraftEvent, "Event rules" and "Notices". The skill's rules 1–4 and the review findings under
      "Current state" explain why each rule exists.
      1. AppCore/Sources/Draft/DraftEvent.swift: EventExclusion (with label) and DraftEvent (with
         defaultTitle and the computed reasons) exactly as specified.
      2. AppCore/Sources/Draft/EventSelection.swift: EventSelection.draftEvents(for:events:
         timeZone:rules:) and EventSelection.notices(for:events:timeZone:rules:) with the exact
         rules, order and strings.
      3. EventSelectionTests (build GoogleEvent values directly, time zone Europe/Budapest, day
         2026-09-30 unless stated): each "not listed" rule; sorting by start, then title, then
         input order; declined wins over personal block; personal blocks by prefix ("Lunch with
         Sam" excluded, "Lunchtime talk" kept); duplicate by iCalUID across two calendars and by
         folded title ("Quarterly Summit" 08:00 and "quarterly summit" 08:30 → the 08:30 one is
         .duplicate); "Team sync" at 09:00 and 15:00 are both kept, at 09:00 and 10:59 the second is
         .duplicate; an excluded event does not make a later same-title event a duplicate;
         hasOtherAttendees false for self only, self + room, self + a declined person; true for
         self + an accepted or needsAction person; attendeeFirstNames from displayName
         "Zoltán Kovács" → "zoltan" and from email "peter.brown@example.com" → "peter";
         title "REMINDER // Decision about the office move" gets page title "Decision about
         the office move" and a short name in rules wins; 07:00 and 19:00 events have nil
         scheduleSlot; every reasons string; notices: Saturday 2026-10-03 gives "Saturday, 3
         October is a weekend.", an all-day "Vacation" gives "You're out of office on this day
         (“Vacation”).", an all-day "Home" gives none, an all-day "Vacation" starting 2026-09-28
         gives the notice on 2026-09-30, a nil-titled all-day outOfOffice event gives
         "(No title)", an eventType outOfOffice event gives the out-of-office notice, a weekend day with an OOO event gives both in that order.
      4. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter EventSelectionTests passes
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p10c-google-fixtures
    title: Google data fixtures for tests, UI tests and previews
    depends_on: [p6-layout-audit, p8b-google-clients]
    complexity: M
    touches:
      - AppCore/Sources/Controller/GoogleFixtures.swift
      - AppCore/Tests/Controller/GoogleFixturesTests.swift
    brief: |
      Read the Design section "Controller" from "Fixtures for UI tests and SwiftUI previews" to
      the end of that section.
      1. AppCore/Sources/Controller/GoogleFixtures.swift: GoogleFixture (with
         init?(launchArguments:)), FixtureGoogleDataSource (public init(_ fixture:)) and
         FixtureGoogleAccount (actor, init(signedIn:); configure stores the value and
         isConfigured reports it; signIn throws .notConfigured while unconfigured) with all five
         fixtures' data exactly as specified, including the defaults for unstated fields.
      2. GoogleFixturesTests: launch-argument parsing ("-MagendaFixture standard", a missing
         value, an unknown value); each fixture's counts of calendars, task lists, events and
         tasks per list; `openTasks(listID: "other")` returns only "Wrong list"; an unknown list
         ID returns []; events are built on the requested day in the requested time zone (09:00
         Europe/Budapest on 2026-09-30 is 07:00Z); longText uses AgendaContentFixtures.longStrings;
         FixtureGoogleAccount signs in without calling the closure and signs out.
      3. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter GoogleFixturesTests passes
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p10b-tasks-and-draft
    title: Task and delegated selection, AgendaDraft with edits and toggles, and AgendaBuilder
    depends_on: [p10a-event-selection, p9b-task-and-delegated-parsing, p10c-google-fixtures]
    complexity: M
    touches:
      - AppCore/Sources/Draft/DraftTask.swift
      - AppCore/Sources/Draft/TaskSelection.swift
      - AppCore/Sources/Draft/AgendaDraft.swift
      - AppCore/Sources/Draft/AgendaBuilder.swift
      - AppCore/Tests/Draft/TaskSelectionTests.swift
      - AppCore/Tests/Draft/AgendaDraftTests.swift
      - AppCore/Tests/Draft/AgendaBuilderTests.swift
    brief: |
      Read the Design section "From Google data to a draft": TaskBucket, DraftTask,
      DraftDelegated, AgendaDraft, AgendaBuilder, "Task rules" and "content()". The skill's rules
      5–6 under "Current state" explain them.
      1. AppCore/Sources/Draft/DraftTask.swift: TaskBucket, DraftTask, DraftDelegated.
      2. AppCore/Sources/Draft/TaskSelection.swift: TaskSelection.draftTasks(for:tasks:events:
         rules:) and draftDelegated(for:tasks:) with the exact rules and reason strings.
      3. AppCore/Sources/Draft/AgendaDraft.swift: AgendaDraft with every mutating function
         (including applyShortName) and content().
      4. AppCore/Sources/Draft/AgendaBuilder.swift: AgendaBuilder(timeZone:rules:) and
         draft(for:events:tasks:delegated:) = EventSelection + TaskSelection + notices.
      5. Tests (Europe/Budapest, day 2026-09-30): TaskSelectionTests — buckets and the
         look-ahead edge (due day+5 listed, day+6 not, lookAheadDays 0 lists none upcoming);
         undated and completed tasks not listed; order inside buckets by due, position, input;
         dueText "09/28"; notes normalized; a discussion task kept by first name with accents
         ("Zoltán - TBD" with attendee "Zoltan Kovacs"), kept by a person alias, left out with
         the exact reason, and an overdue discussion task included as ordinary; delegated marked
         on day and before, unmarked after and when due is nil, warnings carried. AgendaDraftTests
         — setIncluded off clears the meeting page and on restores it; setMeetingPage ignored on
         a left-out event; setTitle blank restores defaultTitle; applyShortName on two events
         sharing a key and with a blank name; content(): the schedule keeps originalTitle while
         meetings use title; two events in one slot join with " / " and get no meetingIndex; a
         left-out event is neither on the schedule nor a meeting; meetingIndex counts within
         meetings; todoItems carry notes; delegated keep marked. AgendaBuilderTests — fetch the
         `standard` fixture's events and tasks from FixtureGoogleDataSource(.standard) (calendar
         "primary", lists "todo" and "delegated") in an async test and assert the exact draft described at the end of
         the Design's "Controller" section (rows, reasons, buckets, content meetings, todoItems
         count, schedule slots).
      6. If the `standard` expectation in the Design disagrees with the rules as written, stop
         blocked and quote both (see the plan's Risks).
      7. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter "TaskSelectionTests|AgendaDraftTests|AgendaBuilderTests" passes
      - the core job's coverage floor step passes at 100%
      - the lint job passes
  - id: p11-agenda-controller
    title: AgendaController — loading, list lookup by title, notices, short names, rendering
    depends_on: [p6-layout-audit, p10b-tasks-and-draft]
    complexity: M
    touches:
      - AppCore/Sources/Controller/AgendaController.swift
      - AppCore/Tests/Controller/AgendaControllerTests.swift
      - AppCore/Tests/Support/FakeRenderer.swift
      - AppCore/Tests/Support/GatedDataSource.swift
    brief: |
      Read the Design section "Controller" up to "Fixtures for UI tests and SwiftUI previews".
      `import Observation` in AppCore departs from ADR 0007 until p16 writes ADR 0015; that is
      expected on this branch.
      1. AppCore/Sources/Controller/AgendaController.swift: RenderedAgenda, AgendaRendering and
         AgendaController (`import Observation`, `@MainActor @Observable`) exactly as specified,
         including loadGeneration, list lookup by folded title, the missing-list notices,
         showsNextWorkingDay, goToNextWorkingDay, saveShortName and the detached layout in
         render().
      2. AppCore/Tests/Support/FakeRenderer.swift: records the plan and file name, returns a
         fixed URL or throws. AppCore/Tests/Support/GatedDataSource.swift: wraps a
         GoogleDataSource; its first `events` call waits on a continuation the test resumes.
      3. Tests (@MainActor, FixtureGoogleDataSource/FixtureGoogleAccount from p10c,
         InMemoryClientCredentialsStore from p8a, a `FailingCredentialsStore` declared in the
         test file whose save throws, InMemorySettingsStore, FakeTextMeasurer, TemplateManifest.bundled(), FakeRenderer; today
         2026-09-29): the initial day is 2026-09-30, and today 2026-10-02 (Friday) gives
         2026-10-05; start() with an empty credentials store gives .needsSetup and configures the
         account with nil; saveClientCredentials with "not-an-id" returns false with the client-ID
         message, with a valid ID and secret "a b" returns false with the secret message, with a
         valid ID saves it, configures the account, sets clientID and moves to .signedOut, and a
         store whose save throws gives the Keychain message; forgetClientCredentials signs out,
         empties the store and returns to .needsSetup; start() signed out and signed in; signIn success, cancellation (no message)
         and failure (message); load() reads "primary" when calendarIDs is empty or stale; the
         to-do list is found by title ignoring case and accents and "Wrong list" never appears;
         todoListTitle "Nope" gives no tasks and the exact missing-list notice;
         delegatedListTitle "" gives no delegated items and no notice; delegatedListTitle
         "Claude" (the to-do list) gives no delegated items and the delegated missing-list
         notice; the standard fixture's draft matches the Design's expectation paragraph;
         outOfOffice gives the out-of-office notice and showsNextWorkingDay; setDay(2026-10-03)
         gives the weekend notice and goToNextWorkingDay moves to 2026-10-05; with
         GatedDataSource, setDay(2026-10-01) then setDay(2026-10-02) before resuming the gate
         leaves day and draft at 2026-10-02; a data source throwing .signedOut moves to
         .signedOut with its message, .network to .failed; updateSettings saves and reloads only
         when calendarIDs, a list title or rules changed (changing fontPack does not reload);
         saveShortName stores the key, retitles both events sharing it without reloading, a
         blank name removes it, and an unknown id changes nothing; updateDraft and updateSettings
         clear rendered; render() passes the file name "2026-09-30.pdf", fills RenderedAgenda
         (overflow fixture reports omitted tasks), and a renderer error leaves .ready with
         "Couldn't create the PDF. Try again."; signOut clears state.
      4. If `import Observation` or `@Observable` fails to compile on the core job, or the
         coverage report shows uncovered lines that come only from the macro's expansion, stop
         blocked with the output (see the plan's Risks).
      5. Do not touch CHANGELOG.md or docs.
    acceptance:
      - swift test --package-path AppCore --filter AgendaControllerTests passes on the core job (Linux)
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
         specified, with the initializers the Design gives (CoreTextMeasurer(library:),
         PDFAgendaRenderer(library:bundle:) throws FontLibraryError.missingTemplate). PDFAgendaRenderer conforms to AgendaRendering (p11).
      3. AppTests/RenderingTests.swift (Swift Testing, hosted): every FontPack × FontWeight loads
         from the bundle; CoreTextMeasurer gives a positive width for "TO-DO LIST" and for each
         of AgendaContentFixtures.longStrings, and wider text measures wider; for every
         AgendaContentFixtures fixture × every FontPack, AgendaLayout with CoreTextMeasurer and
         TemplateManifest.bundled() gives LayoutAudit.violations(in:) == [] (report the
         violations in the failure message); FontLibrary(bundle: .main) succeeds and
         FontLibrary(bundle: Bundle(for: an NSObject subclass declared in the test file)), the
         test bundle, which holds no fonts, throws missingFont, and
         PDFAgendaRenderer(library:bundle:) with that test bundle throws missingTemplate; rendering the typical and overflow plans writes a
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
    title: URLSession, Keychain (tokens and client credentials), CryptoKit and UserDefaults adapters, privacy manifest
    depends_on: [p8a-google-session, p8b-google-clients, p9a-settings-and-title-rules]
    complexity: M
    touches:
      - App/Platform/URLSessionHTTPClient.swift
      - App/Platform/KeychainItem.swift
      - App/Platform/KeychainTokenStore.swift
      - App/Platform/KeychainClientCredentialsStore.swift
      - App/Platform/CryptoKitHasher.swift
      - App/Platform/UserDefaultsSettingsStore.swift
      - App/PrivacyInfo.xcprivacy
      - AppTests/PlatformTests.swift
    brief: |
      Read the Design section "Platform" under "App" and the client paragraph at the top of
      "Google sign-in".
      1. Do not create any file holding a client ID; the app takes the client from the user at
         runtime.
      2. App/Platform/KeychainItem.swift: a struct (service, account) with
         `read() throws -> Data?`, `write(_ data: Data) throws`, `delete() throws` over
         SecItemAdd / SecItemUpdate / SecItemCopyMatching / SecItemDelete with
         kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; errSecItemNotFound on read returns nil
         and on delete succeeds; other statuses throw a private error carrying only the OSStatus.
      3. KeychainTokenStore and KeychainClientCredentialsStore on top of KeychainItem, JSON
         encoded, as specified; URLSessionHTTPClient (maps URLError to a thrown error without the
         URL or headers in its description); CryptoKitHasher; UserDefaultsSettingsStore.
      4. App/PrivacyInfo.xcprivacy with exactly the keys in the Design.
      5. AppTests/PlatformTests.swift (hosted): KeychainTokenStore and
         KeychainClientCredentialsStore save/load/overwrite/delete round trips under services
         "name.felhasznalo.magenda.tests" and "name.felhasznalo.magenda.tests-client" (deleted in
         the test's cleanup), the client store also with a nil secret; UserDefaultsSettingsStore
         round trip in a UserDefaults(suiteName:) removed afterwards, and garbage data loads as
         defaults; CryptoKitHasher on the RFC 7636 verifier gives the expected challenge digest.
         Test client IDs are made up ("123456789012-test.apps.googleusercontent.com").
      6. Push and dispatch tests.yml; read the app jobs. If a Keychain test fails with OSStatus
         -34018 (errSecMissingEntitlement) on the simulator, stop blocked and quote the status;
         do not add entitlements or skip the test.
      7. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - test ! -e App/GoogleOAuthClientID.txt
      - tests.yml's three app jobs pass on the phase branch, including PlatformTests
      - the lint and scripts jobs pass
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
      - App/Screens/SetupView.swift
      - App/Screens/AgendaView.swift
      - AppCore/Sources/Greeting.swift
      - AppCore/Tests/GreetingTests.swift
      - AppUITests/MainScreenUITests.swift
      - AppUITests/SignInUITests.swift
      - AppUITests/SetupUITests.swift
    brief: |
      Read the Design sections "Wiring" and "Screens" (rows RootView, SetupView and SignInView) and
      docs/coding-and-testing-guidelines.md "Views".
      1. App/AppEnvironment.swift: makeController(arguments:bundle:) exactly as the Design's
         "Wiring" paragraph says, live and fixture branches included (fixture today 2026-09-29).
      2. App/MagendaApp.swift: as the "Wiring" paragraph says, including the templateError text
         when makeController throws, and RootView(appInfo:). Leave out `.commands`; p14c adds it.
      3. App/Screens/RootView.swift and SignInView.swift with the exact strings, identifiers and
         #Previews. SignInView passes @Environment(\.webAuthenticationSession)'s
         authenticate(using: url, callback: .customScheme(scheme), preferredBrowserSession:
         .shared, additionalHeaderFields: [:]) to controller.signIn as
         `{ @MainActor url, scheme in try await session.authenticate(…) }`, mapping
         ASWebAuthenticationSessionError.canceledLogin to GoogleAPIError.authorizationCancelled.
         If Swift 6 strict concurrency still rejects the closure, stop blocked with the
         diagnostic.
         The sign-in content is centered with a maximum width of 480 pt so it reads well in a
         full-screen iPad window.
      3b. App/Screens/SetupView.swift with the exact strings, identifiers, field settings and
         #Preview, usable full screen and as a sheet (an `isSheet: Bool` parameter adds Cancel,
         prefills the client ID and dismisses on success).
      4. App/Screens/AgendaView.swift: a stub `AgendaView(appInfo:)` showing
         `List { Text(controller.day.isoString) }` with identifier `agendaScreen` on the List and
         a #Preview; p14b replaces its body.
      5. Delete App/ContentView.swift, AppCore/Sources/Greeting.swift,
         AppCore/Tests/GreetingTests.swift and AppUITests/MainScreenUITests.swift.
      6. AppUITests/SignInUITests.swift (XCTest, identifiers only, waitForExistence, no sleeps):
         -MagendaFixture standard -MagendaSignedOut shows signInButton, and tapping it reaches
         agendaScreen within 10 s; -MagendaFixture standard alone reaches agendaScreen without
         showing signInButton. AppUITests/SetupUITests.swift: -MagendaFixture standard
         -MagendaNeedsSetup -MagendaSignedOut shows clientIDField and saveClientButton disabled;
         typing "not-an-id" and tapping save shows setupMessage; typing
         "123456789012-test.apps.googleusercontent.com" and saving reaches signInButton.
      7. Push and dispatch tests.yml; all three app jobs (iPhone newest, iPhone oldest, iPad
         newest) must pass.
      8. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - test ! -e App/ContentView.swift && test ! -e AppCore/Sources/Greeting.swift && test ! -e AppUITests/MainScreenUITests.swift
      - tests.yml's three app jobs pass on the phase branch with SignInUITests
      - the core (coverage floor 100%), lint and scripts jobs pass
  - id: p14b-app-agenda-screen
    title: The iPad-first agenda screen — split view, toolbar, rows with reasons and toggles — and its UI tests
    depends_on: [p14a-app-shell-and-sign-in]
    complexity: M
    touches:
      - App/Screens/AgendaView.swift
      - App/Screens/AgendaRows.swift
      - AppUITests/AgendaScreenUITests.swift
      - AppUITests/LongTextUITests.swift
    brief: |
      Read the Design section "Screens" (row AgendaView, the "Rows" list and the "Multiple
      windows" paragraph), the `standard` expectation paragraph at the end of "Controller", and
      docs/coding-and-testing-guidelines.md "Views".
      1. App/Screens/AgendaView.swift: replace p14a's stub body with the NavigationSplitView
         screen (columnVisibility .all, .balanced style, the toolbar placements as specified);
         keep the identifier `agendaScreen` on the sidebar's List. The settingsButton opens
         `.sheet { Text("Settings") }` until p15b. The detail column shows the
         ContentUnavailableView placeholder (identifier `previewPlaceholder`) and, once
         `rendered` is set, a placeholder `Text(rendered.url.lastPathComponent)` with identifier
         `pdfPreview`, which p15a replaces with PreviewView.
      2. App/Screens/AgendaRows.swift: the three row views with the exact strings, identifiers,
         accessibility labels, hover effects and #Previews (fixture data). The leading button and
         the context menu's "Edit…" call an `onEdit` closure the row takes; in this phase
         AgendaView passes `{}`; p14c presents EditTextSheet from it.
      3. UI tests (XCTest, identifiers only, waitForExistence, no sleeps), launched with
         -MagendaFixture. AgendaScreenUITests — standard: eventRow.0…9, taskRow.0…4 and
         delegatedRow.0…2 exist; eventReason.0 contains "Personal block", eventReason.5
         contains "Declined", eventReason.8 contains "Duplicate", eventReason.9 contains "Not
         on the schedule"; eventPageToggle.1 exists and eventPageToggle.0 does not; toggling
         eventToggle.1 off removes eventPageToggle.1; taskReason.2 contains "no meeting with
         Nora"; delegatedMarked.0 exists and delegatedMarked.1 does not; nextDayButton changes
         datePicker's value; with -MagendaFixture outOfOffice, notice.0 and nextWorkingDayButton
         exist; Render shows pdfPreview within 30 s, and then `agendaScreen.isHittable` is true
         when `UIDevice.current.userInterfaceIdiom == .pad` and false otherwise.
         LongTextUITests — longText, once at the default size and once with launch arguments
         -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge:
         for every eventRow.n, taskRow.n and delegatedRow.n, after scrolling it into view, its
         frame's minX ≥ the window's minX and maxX ≤ the window's maxX, and its toggle
         isHittable; renderButton is hittable and Render reaches pdfPreview.
      4. Push and dispatch tests.yml; all three app jobs must pass.
      5. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - tests.yml's three app jobs pass on the phase branch with AgendaScreenUITests and LongTextUITests
      - the core (coverage floor 100%), lint and scripts jobs pass
      - grep -rn "sleep(" AppUITests prints nothing
      - grep -n "NavigationSplitView" App/Screens/AgendaView.swift prints a line
  - id: p14c-app-editing-and-commands
    title: The edit sheet with saved short names, and the Agenda menu with keyboard shortcuts
    depends_on: [p14b-app-agenda-screen]
    complexity: S
    touches:
      - App/MagendaApp.swift
      - App/Screens/AgendaView.swift
      - App/Screens/EditTextSheet.swift
      - App/Screens/AgendaCommands.swift
      - AppUITests/AgendaEditUITests.swift
    brief: |
      Read the Design section "Screens" (rows EditTextSheet and AgendaCommands) and "Wiring"
      (the `.commands` line).
      1. App/Screens/EditTextSheet.swift with the exact strings, identifiers, keyboard shortcuts
         and the "Use this name for this meeting every time" toggle (events only); Done calls
         controller.saveShortName when the toggle is on, otherwise the matching
         updateDraft { $0.setTitle / setText }.
      2. App/Screens/AgendaView.swift: the rows' onEdit presents EditTextSheet for that item as
         a `.sheet(item:)`. No other change.
      3. App/Screens/AgendaCommands.swift and the `.commands` line in App/MagendaApp.swift, with
         the exact titles, shortcuts and enabled conditions.
      4. AgendaEditUITests (XCTest, identifiers only, no sleeps), -MagendaFixture standard:
         editing taskRow.0 through editField and editDone changes taskRow.0's label; editCancel
         leaves it unchanged; editing eventRow.4 shows editRemember and editing taskRow.0 does
         not; saving "Office move" with editRemember on makes eventReason.4 contain "Page
         title: Office move"; on the iPad job (`UIDevice.current.userInterfaceIdiom ==
         .pad`) `app.typeKey("r", modifierFlags: .command)` shows pdfPreview. If typeKey does not
         trigger Render on the iPad job, stop blocked with the log; do not drop the assertion.
      5. Push and dispatch tests.yml; all three app jobs must pass.
      6. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - tests.yml's three app jobs pass on the phase branch with AgendaEditUITests
      - the core (coverage floor 100%), lint and scripts jobs pass
      - grep -n "CommandMenu" App/Screens/AgendaCommands.swift prints a line
  - id: p15a-app-preview
    title: PDF preview beside the list with the share button, and its UI tests
    depends_on: [p14c-app-editing-and-commands]
    complexity: S
    touches:
      - App/Screens/PreviewView.swift
      - App/Screens/PDFKitView.swift
      - App/Screens/AgendaView.swift
      - AppUITests/PreviewUITests.swift
    brief: |
      Read the Design section "Screens" (rows PreviewView and AgendaView's Detail part).
      1. App/Screens/PDFKitView.swift: UIViewRepresentable around PDFView (autoScales true,
         displayMode .singlePageContinuous, document from the URL, reloaded when the URL
         changes), identifier pdfPreview.
      2. App/Screens/PreviewView.swift: the PDF, the toolbar ShareLink(item: url) with label
         "Share PDF" and identifier shareButton, and the omittedTasksBanner exactly as specified.
      3. App/Screens/AgendaView.swift: the detail column shows PreviewView when rendered is set,
         replacing p14b's placeholder Text. No other change.
      4. PreviewUITests with -MagendaFixture: standard: Render, pdfPreview exists, shareButton
         exists and isHittable, no omittedTasksBanner; tapping nextDayButton after rendering
         brings back previewPlaceholder on the iPad job (rendered is cleared by the reload);
         overflow: the banner exists and its label starts with a number followed by " task";
         longText at the largest accessibility size: shareButton isHittable.
      5. Push and dispatch tests.yml; all three app jobs must pass.
      6. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - tests.yml's three app jobs pass on the phase branch with PreviewUITests
      - the core (coverage floor 100%), lint and scripts jobs pass
      - grep -n "ShareLink" App/Screens/PreviewView.swift prints a line
  - id: p15b-app-settings
    title: The settings sheet — calendars, task lists by title, look, account, about — and its UI tests
    depends_on: [p15a-app-preview]
    complexity: M
    touches:
      - App/Screens/SettingsView.swift
      - App/Screens/AgendaView.swift
      - AppUITests/SettingsUITests.swift
    brief: |
      Read the Design section "Screens" (row SettingsView) and "Settings and binder rules" (the
      AgendaSettings block).
      1. App/Screens/SettingsView.swift with every section, string and identifier in the Design.
         Hex fields validate with RGBColor(hex:) and save through controller.updateSettings; the
         task-list pickers store titles. The "Binder rules" NavigationLink (identifier
         rulesLink) leads to `Text("Binder rules")` until p15c.
      2. App/Screens/AgendaView.swift: settingsButton's sheet shows SettingsView(appInfo:)
         instead of p14b's placeholder. No other change. SettingsView's "Google client" section
         presents SetupView(isSheet: true) from p14a.
      3. SettingsUITests with -MagendaFixture standard: open settings; typing "XYZ" into
         colorField.heading and submitting shows colorError; typing "7C3AED" removes it;
         resetColorsButton restores 215E99; tapping fontOption.jetbrains_mono, closing with
         settingsDone and rendering reaches pdfPreview; clientIDLabel shows the fixture client
         ID; changeClientButton opens clientIDField; forgetClientButton and confirming returns to
         clientIDField (the setup screen); choosing "None" in delegatedListPicker
         and closing removes delegatedRow.0; rulesLink exists; the version row exists;
         signOutButton returns to signInButton.
      4. Push and dispatch tests.yml; all three app jobs must pass.
      5. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - tests.yml's three app jobs pass on the phase branch with SettingsUITests
      - the core (coverage floor 100%), lint and scripts jobs pass
  - id: p15c-app-rules-editor
    title: The binder-rules editor and its UI tests
    depends_on: [p15b-app-settings]
    complexity: M
    touches:
      - App/Screens/RulesView.swift
      - App/Screens/SettingsView.swift
      - AppUITests/RulesUITests.swift
    brief: |
      Read the Design section "Screens" (row RulesView) and "Settings and binder rules".
      1. App/Screens/RulesView.swift with every section, string and identifier in the Design,
         including `rulesRow.<section>.<n>` on each row. Adding ignores blanks and duplicates by
         BinderText.fold; People stores as specified.
      2. App/Screens/SettingsView.swift: rulesLink leads to RulesView instead of p15b's
         placeholder. No other change.
      3. RulesUITests with -MagendaFixture standard: through rulesLink, typing "Week
         preparation" into rulesAdd.personalBlocks and submitting adds rulesRow.personalBlocks.2;
         after closing settings eventReason.6 contains "Personal block"; swiping left on
         rulesRow.personalBlocks.0 ("Lunch" in the defaults) and tapping Delete makes
         eventReason.3 no longer contain "Personal block"; adding peopleName "Nora" and
         peopleEmail "nora@example.com" adds rulesRow.people.0; lookAheadStepper's increment
         changes its value to "Upcoming tasks: 6 days"; resetRulesButton restores
         rulesRow.personalBlocks.0 and .1.
      4. Push and dispatch tests.yml; all three app jobs must pass.
      5. Do not touch project.yml, CHANGELOG.md or docs.
    acceptance:
      - tests.yml's three app jobs pass on the phase branch with RulesUITests
      - the core (coverage floor 100%), lint and scripts jobs pass
  - id: p16-retire-plan
    title: ADRs 0011–0016, standing docs, coverage floors, changelog, and plan removal
    depends_on: [p15c-app-rules-editor]
    complexity: M
    touches:
      - docs/adr/0011-the-agenda-pdf-is-drawn-on-device-from-the-vendored-magenda-template.md
      - docs/adr/0012-text-layout-is-computed-in-appcore-and-audited.md
      - docs/adr/0013-google-sign-in-uses-pkce-with-aswebauthenticationsession.md
      - docs/adr/0014-agenda-inputs-come-live-from-google-calendar-and-google-tasks.md
      - docs/adr/0015-appcore-may-import-observation.md
      - docs/adr/0016-agenda-selection-uses-editable-rules-not-a-language-model.md
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
      1. Write ADRs 0011–0016 with the file names in `touches`, Status "Accepted — <today's
         date>.", using the plan's Design and Rejected alternatives for Context, Decision and
         Alternatives considered. They link to source files and commits, never to this plan.
         Add them to the index in docs/adr/README.md.
      2. README.md: replace "An iOS app." with what Magenda does (an iPad-first app that builds
         the daily binder from Google Calendar and Google Tasks: sign in, review with reasons,
         edit, render, preview, share to Noteshelf or anywhere), a "What goes on the agenda"
         section restating the binder rules in user terms (from the Design's "Event rules",
         "Notices" and "Task rules", and where each rule is edited in Settings → Binder rules),
         a "Delegated tasks" section with the `Owner: Task` / `#cadence` / log format from the
         Design, a "Google Cloud setup" section (heading exactly "## Google Cloud
         setup", so SetupView's link anchor #google-cloud-setup resolves) with the steps from the
         plan's manual_after ma1 written for any user: create a project, enable the two APIs,
         configure the consent screen with the two read-only scopes, create an iOS client for the
         bundle ID, enter its client ID in the app (the secret only for a client type that has
         one; it stays in the Keychain, ADR 0013); no organization names or real IDs, a "Keyboard shortcuts" table from
         AgendaCommands, and the new folders in the Layout table (App/Rendering, App/Platform,
         App/Screens, App/Resources).
      3. docs/testing-policy.md: Layer 4 says the Google decoding tests replay
         AppCore/Tests/Google/Fixtures and that no live contract check runs; the layout audit
         runs in AppCore (fake font) and in AppTests (real fonts); the binder rules are tested in
         AppCore against the `standard` fixture.
         docs/release-testing.md "What stays manual": real Google sign-in, real account data, and
         the comparison with a binder built by the old Claude workflow while it still runs.
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
         AppCore/Sources/Settings/BinderText.swift, MeetingTitle.swift, TaskTitle.swift,
         DelegatedTask.swift, AppCore/Sources/Draft/EventSelection.swift, TaskSelection.swift.
         Remove nothing.
      5. CHANGELOG.md under [Unreleased] → Added: replace the placeholder first-screen line with
         user-facing lines: sign in with Google; the daily binder built from Google Calendar and
         the "Claude" and "Claude Delegations" task lists, with the same rules as before and no
         AI; every left-out item shows why; editable binder rules (personal blocks, title
         prefixes, out-of-office words, short meeting names, people, look-ahead days); untick or
         edit items before rendering; your own Google client entered on first launch and kept in
         the Keychain; PDF preview beside the list on iPad and sharing; keyboard
         shortcuts; font and color settings; long titles are shortened with "…" and to-dos that
         don't fit are listed.
      6. Delete docs/google-agenda-pdf-plan.md and docs/google-agenda-pdf-plan-manual-steps.html;
         grep the repo for "google-agenda-pdf-plan" and remove any remaining link.
      7. Run python3 -m unittest discover -s scripts/tests (the no-project-history guard covers
         the new docs) and /dod.
    acceptance:
      - test ! -e docs/google-agenda-pdf-plan.md && test ! -e docs/google-agenda-pdf-plan-manual-steps.html
      - grep -rn "google-agenda-pdf-plan" --exclude-dir=.git . prints nothing
      - ls docs/adr/001[1-6]-*.md lists six files, each containing "Accepted"
      - grep -c "^| \[001[1-6]\]" docs/adr/README.md prints 6
      - grep -rn "Greeting\|ContentView" docs README.md CONTRIBUTING.md prints nothing
      - python3 -m unittest discover -s scripts/tests passes
      - grep -n "^## \[[0-9]" CHANGELOG.md prints nothing
      - grep -n "^## Google Cloud setup" README.md prints one line
      - grep -rn "GOCSPX-" --exclude-dir=.git . prints nothing (no real client secret)
      - grep -rnoE "[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com" --exclude-dir=.git . | grep -vE "123456789012-(fixture|test)|123-abc" prints nothing (only made-up client IDs)
```
