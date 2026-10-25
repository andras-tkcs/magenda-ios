# Plan: send one meeting to Claude before the day ends

## Goal

Sometimes a meeting's notes and summary are needed before the end of the day. On iPad, the binder
gets a **Send Meeting** button on a meeting page. It uploads only that meeting's pages (the meeting
page and the pages added as copies of it) as their own PDF, creates their own Google Doc, and
starts the end-of-day routine for that meeting. The meeting then goes through the same review loop
as a day (notes, Approve notes, summary, Approve, closed) in its own row of the Review list. After
sending, the meeting's pages are locked, so nothing written later is lost. Finish Day at the end of
the day still uploads the whole day, sent meetings included, and the payload marks each sent
page, so the routine processes the overview, delegated, notes and unsent meeting pages and leaves
the meetings sent earlier alone.

Baseline: [andras-tkcs/magenda-ios#14](https://github.com/andras-tkcs/magenda-ios/pull/14)
(Reset Hand-off, ADR 0032). This branch is cut from that PR's head (`423af6b`), so the feature
branch carries it until it merges into `main`.

Decisions the user made when this plan was written:

- A meeting sent early gets its own PDF and its own Doc.
- It goes through the same review steps as a day.
- Its pages are locked after sending.
- At the end of the day the day's PDF keeps those pages, and the payload marks them as processed.

## Current state

- **Finish Day** (`AppCore/Sources/Handoff/HandoffController.swift:82`, `finish(_:)`) renders every
  page of the open binder with its ink into one PDF, hashes it, builds a `DayHandoff`
  (`AppCore/Sources/Handoff/DayHandoff.swift:185`) and runs `runPipeline` (`:232`): folder
  `Magenda`, upload `Magenda <date>.pdf`, create the Doc `Magenda <date> notes`, fire step `notes`.
  `canFinish` (`:63`) refuses once notes were requested.
- **One record per date.** `HandoffStore` (`AppCore/Sources/Handoff/HandoffStore.swift`) keys
  everything by `CalendarDay`: `handoff(_:)`, `pdf(for:)`, `savePDF(_:for:)`, `deletePDF(for:)`,
  and since #14 `deleteHandoff(for:)`, which removes the date's whole folder. `FileHandoffStore`
  keeps `<date>/handoff.json` and `<date>/day.pdf`. The controller looks records up with
  `stored(on:)` (`:206`), and `perform(_:on:)` (`:145`), `docURL(for:)` (`:74`),
  `hasHandoff(on:)` (`:69`) and `resetHandoff(for:)` (`:162`) all take a date.
- **The payload** (`DayHandoff.payload(step:)`, `:249`) is schema `magenda.end-of-day/1` (`:274`).
  Page entries are `HandoffPage`; when the text is too long, `bare` (`:40`) strips everything but
  `page`, `key`, `calendarID` and `eventID`.
- **Phases** (`DayHandoff.phase`, `:231`): a closed record shows "Closed. Handwriting is deleted on
  <date>." because the five-day purge (ADR 0030) runs per date, in `refresh(excluding:)` (`:122`)
  and `purge(_:)` (`:299`).
- **Fixtures** (`AppCore/Sources/Handoff/HandoffFixtures.swift`): `FixtureEndOfDay` keys what was
  fired by date and decodes `date`, `step`, `pages[].summarySkill`; `FixtureDrive` returns
  `file-<date>` and `doc-<date>`.
- **The binder** (`AppCore/Sources/Binder/BinderSession.swift`) has no notion of a read-only page:
  `setInk` (`:61`) writes any page, `canDelete` (`:123`) allows any added page, undo and redo can
  touch any page. `BinderDay` (`AppCore/Sources/Binder/BinderDay.swift`) is `content`, `theme`,
  `extras`, `retained`, format version 1. `BinderLayout.rebased` (`BinderLayout.swift:144`) keeps a
  page that left the content only when it, or an added copy of it, carries ink.
- **Start Over** (`AppCore/Sources/Controller/AgendaController.swift:345`, ADR 0026) deletes every
  ink key of the day and saves a fresh `BinderDay`.
- **Page subsets.** `RenderPlan` (`AppCore/Sources/Layout/RenderPlan.swift`) has no way to render
  some of its pages. Its `.link(rect, targetPage:)` operations hold indices into the full plan, so
  copying pages out without remapping would leave wrong links.
- **UI.** `App/Screens/BinderView.swift` has Finish Day and, since #14, Reset Hand-off in the
  navigation toolbar. `BinderToolbar.swift` holds the page buttons. `BinderPageView.swift` sets up
  the `PKCanvasView`. `ReviewView.swift` lists `handoff.days` by date. `AgendaView.swift:240` has
  Start Over.
- **Coverage floors** (`scripts/check_coverage_floor.py`): `OVERALL_FLOOR` is 100 % for all of
  AppCore, and `BinderLayout.swift` and every file in `AppCore/Sources/Handoff/` have their own
  100 % floors. Every new line in AppCore needs a test.
- **The standard UI-test fixture** (`-MagendaFixture standard`) has meetings ("Team sync",
  "1:1 with Peter"), so its binder has meeting pages after the overview and delegated pages.

## Design

### D1. What a "meeting" is and which pages it sends

A meeting is a page with key `.meeting(id)` where `id` is not empty (the empty id is the blank
meeting page of a day without meetings, which is never sendable). Its pages are, in the binder
plan's order, `.meeting(id)` itself and every `.extra(x)` whose `ExtraPage.source == .meeting(id)`.
The visible page selects the meeting: a `.meeting(id)` page, or an `.extra(x)` page whose source
is a `.meeting(id)` with a non-empty id. Any other page (overview, delegated, notes, an added copy
of one of those) has no meeting, and Send Meeting is disabled there.

New static in `DayHandoff.swift`:

```swift
/// The meeting that page `key` belongs to and that meeting's pages in `plan`'s order: the meeting
/// page and the pages added as copies of it. nil when `key` is not a meeting page with an event,
/// or a copy of one, or the meeting page is not in `plan`.
public static func meetingPages(
    containing key: PageKey, day: BinderDay, plan: RenderPlan
) -> (meeting: PageKey, keys: [PageKey])?
```

### D2. Rendering a subset of the plan

New method in `RenderPlan.swift`:

```swift
/// The pages whose keys are in `keys`, in this plan's order. Each link points at its target's
/// position in the result; a link to a page left out is dropped. `omittedTodoItems` is empty.
public func subset(_ keys: Set<PageKey>) -> RenderPlan
```

### D3. Records: one per day, one per sent meeting

New types in `DayHandoff.swift`:

```swift
/// Which hand-off a record is: a finished day, or a meeting sent before the day ended.
public struct HandoffID: Hashable, Sendable {
    /// The day.
    public let date: CalendarDay
    /// nil for the finished day; the part's number for a meeting sent early.
    public let part: Int?
    /// Creates an ID.
    public init(date: CalendarDay, part: Int?)
    /// The Review list's order: newest date first; on one date the day before its parts, and
    /// parts by number.
    public static func listOrder(_ lhs: HandoffID, _ rhs: HandoffID) -> Bool
}

/// A meeting sent to the routine before the day ended.
public struct HandoffPart: Equatable, Codable, Sendable {
    /// 1, 2, … in the order the day's meetings were sent.
    public let number: Int
    /// `PageKey.storageString` of the meeting page.
    public let meetingKey: String
    /// The meeting-page title, when known.
    public let title: String?
    /// Creates a part.
    public init(number: Int, meetingKey: String, title: String?)
}
```

`DayHandoff` gains:

- `public let part: HandoffPart?`. It is added to `CodingKeys` and decoded with `decodeIfPresent`,
  so records saved before stay readable. `formatVersion` stays 1.
- `public var id: HandoffID { HandoffID(date: date, part: part?.number) }`.
- `public var pageKeys: Set<PageKey>`: `pages.compactMap { PageKey(storageString: $0.key) }`.
- `public var displayTitle: String`: the day is `date.isoString`, and a part is
  `"\(date.isoString) · \(part.title ?? "Meeting")"` (U+00B7 between spaces).
- `public var pdfName: String`: `Magenda <date>.pdf`, or `Magenda <date> part <n>.pdf`.
- `public var docName: String`: `Magenda <date> notes`, or `Magenda <date> part <n> notes`.
  Titles stay out of Drive names. They are the person's content, can repeat, and the Doc's own
  text can carry them.
- The memberwise `init(date:checksum:pages:tasks:delegated:)` gains a trailing
  `part: HandoffPart? = nil`.
- The day initializer becomes
  `init(date:checksum:day:plan:earlierParts: [PageKey: Int] = [:])`. Each page whose key is in
  `earlierParts` gets `earlierPart` set to that number.
- New meeting initializer:
  `init(date: CalendarDay, part number: Int, meeting: PageKey, checksum: String, day: BinderDay, plan: RenderPlan)`.
  Its pages come from `plan` through the existing `handoffPage(number:page:in:)`, `tasks` and
  `delegated` are `[]`, and `part` is
  `HandoffPart(number:, meetingKey: meeting.storageString, title: <the title of the page entry whose key is meeting.storageString>)`.

`HandoffPage` gains `public let earlierPart: Int?`, the part that already sent this page, as a
trailing `earlierPart: Int? = nil` init parameter. `bare` keeps `earlierPart`, because a routine
that loses it would process the page twice.

`HandoffPhase` gains `case meetingClosed`. Its `title` is `"Closed"` and its `action` is nil.
`phase` returns `.meetingClosed` for a part with `closedOn` set and keeps `.closed(...)` for the
day. All other phases are shared.

### D4. Payload schema `magenda.end-of-day/2`

`Payload.schema` becomes `"magenda.end-of-day/2"`. The bump is deliberate: the contract says a
routine that sees another schema stops, so a routine not yet adapted stops instead of processing a
meeting twice. Added keys, all left out when nil:

- `scope`: `"day"` or `"meeting"`, always present.
- `part`: the part number. Meeting runs only.
- `pages[].earlierPart`: day runs only. The page was already sent as part `n` of this date and must
  not be processed again.
- A meeting run has no `tasks` and no `delegated` (both nil, so absent). `pages` and `pageCount`
  describe the meeting's own PDF, numbered from 1.

The truncation rules are unchanged.

Example meeting run:

```json
{"checksum":"sha256:…","date":"2026-10-26","docID":"…","driveFileID":"…","pageCount":2,"pages":[{"calendarID":"work@example.com","eventID":"ev1","key":"meeting:work@example.com|ev1","page":1,"summarySkill":"meeting-summary","title":"Weekly sync"},{"key":"extra:x1","page":2,"source":"meeting:work@example.com|ev1"}],"part":1,"schema":"magenda.end-of-day/2","scope":"meeting","step":"notes"}
```

Day run page entry for that meeting: `{"calendarID":"work@example.com","earlierPart":1,"eventID":"ev1","key":"meeting:work@example.com|ev1","page":3,"title":"Weekly sync"}`.

### D5. Store keyed by `HandoffID`

`HandoffStore` becomes:

```swift
func handoffs() throws -> [DayHandoff]                 // HandoffID.listOrder
func handoff(_ id: HandoffID) throws -> DayHandoff?
func save(_ handoff: DayHandoff) throws                 // replaces what was saved for handoff.id
func pdf(for id: HandoffID) throws -> Data?
func savePDF(_ data: Data, for id: HandoffID) throws
func deletePDF(for id: HandoffID) throws
func deleteHandoff(for date: CalendarDay) throws        // the date's day record, every part and every PDF
```

`FileHandoffStore` keeps the day's `<date>/handoff.json` and `<date>/day.pdf` unchanged. Part `n`
is stored as `<date>/part-<n>.json` and `<date>/part-<n>.pdf`, both named by the app. `handoffs()`
reads each date folder's `handoff.json` and every file whose name is exactly
`"part-\(n).json"` for an `Int` `n` from 1 to 9999. It skips a file that does not decode, or whose
decoded `id` does not match its name. `deleteHandoff(for:)` keeps removing the whole date folder.
`InMemoryHandoffStore` keys its dictionaries by `HandoffID`, and its `deleteHandoff(for:)` removes
every entry with that date.

### D6. Controller

Adapted (the behaviour for the day stays the same):

- `days` holds every record, day and parts, in `HandoffID.listOrder`. `remember` inserts by that
  order. `stored(_ id: HandoffID)` replaces `stored(on:)`.
- `canFinish(_ date:)` looks at `HandoffID(date: date, part: nil)` only.
- `hasHandoff(on:)` is true when any record (day or part) exists on the date.
- `docURL(for id: HandoffID)` and `perform(_:on id: HandoffID)` take an ID.
- `runPipeline` uses `handoff.pdfName`, `handoff.docName` and `store.pdf(for: handoff.id)`.
- `refresh`: uploading queued records and reading statuses covers parts too. The purge runs only
  for a day record (`part == nil`) closed `purgeDelayDays` ago. It deletes the binder day, calls
  `deletePDF(for:)` for every record of that date, and saves every record of that date with
  `purged = true`. Parts never start a purge of their own; their handwriting goes with the day's.
- `resetHandoff(for date: CalendarDay, unlocking binder: BinderSession? = nil)` deletes the
  date's records as before (now including parts), removes every record of the date from `days`,
  and, when `binder` is given and is for that date, calls `binder.unlockAll()`. The messages stay
  as #14 has them.

New:

```swift
/// The pages of `date` already sent in a meeting.
public func sentKeys(on date: CalendarDay) -> Set<PageKey>

/// Whether the meeting that page `key` of `binder` belongs to can be sent now: `key` has a meeting
/// (D1), none of its pages is sent or locked, and the date has no day record.
public func canSendMeeting(containing key: PageKey, of binder: BinderSession) -> Bool

/// Renders the meeting's pages with their ink to a PDF, saves it as the next part, locks the
/// pages, uploads them and starts the routine's `notes` step for them.
public func sendMeeting(containing key: PageKey, of binder: BinderSession) async
```

`sendMeeting` in order:

1. `guard !isBusy`, then set `isBusy` and defer clearing it.
2. If the date has a day record (`HandoffID(date:, part: nil)`): message
   `"This day was already finished, so its meetings go with it."`, return.
3. `guard let found = DayHandoff.meetingPages(containing: key, day: binder.day, plan: binder.plan)` else return without a message.
4. If any of `found.keys` is in `sentKeys(on:)` or `binder.isLocked(_:)`: message
   `"This meeting was already sent to Claude."`, return.
5. `n` = the highest part number on the date plus 1, or 1 when there is none. Then
   `binder.lock(found.keys)` at once, so nothing written during the awaits below is left out of
   the PDF. Every failure below calls `binder.unlock(found.keys)` before it returns.
6. `subset = binder.plan.subset(Set(found.keys))`. Render with
   `renderer.render(subset, ink: subset.pages.map { binder.ink[$0.key] }, fileName: "<date>-part-<n>.pdf")`,
   then read the file and remove it, as `renderedPDF(of:)` does. On failure:
   `"Couldn't create the PDF. Try again."`.
7. Build `DayHandoff(date:, part: n, meeting: found.meeting, checksum: "sha256:" + hex, day: binder.day, plan: subset)`.
   Save the PDF and the record under its `id`. On failure:
   `"Couldn't save the meeting. Free some space on this device and try again."`.
8. `remember`.
9. `runPipeline`. Then message `"Sent to Claude. The notes appear in the meeting's Google Doc."`
   when the part's stage is `.notesRequested`, else its `lastError`.

Messages specific to a part: in `runPipeline`, a missing PDF reads
`"This meeting's PDF is missing. Reset the hand-off and send it again."` for a part (the day's
text stays `"This day's PDF is missing. Finish the day again."`).

`finish(_:)` uses `HandoffID(date: date, part: nil)` for the earlier record it reuses
(`driveFileID`, `docID`), for `canFinish`, and for the result message; it never reuses a part's
Drive IDs. It builds `earlierParts` from every part record of the date (each of its `pageKeys`
maps to its `part.number`) and passes it to the day initializer.

`remember` replaces the record with the same `id` (not the same date), so remembering a part keeps
the day's record. The reset guard is "any record on the date".

**Purge.** Only a day record starts one, `purgeDelayDays` after its `closedOn`. A date whose
meetings were sent but whose day was never finished is not purged; that is accepted, and it is
what ADR 0030 amended in ADR 0033 says. The purge deletes the binder day, then for every record of
the date whose stage is neither `.queued` nor `.uploaded` (a part still waiting to upload keeps its
PDF) deletes the PDF and saves the record with `purged = true`, parts before the day record, so a
failure partway leaves the day unpurged and the next refresh repeats it.

**Reset when the lock is stuck.** `resetHandoff(for:unlocking:)` also proceeds when the date has
no record but the given binder has locked pages: it then only unlocks them. The binder shows Reset
Hand-off when `hasHandoff(on:)` is true or `binder.day.locked` is not empty.

### D7. Locked pages in the binder

`BinderDay` gains `public var locked: [PageKey]` (a `locked: [PageKey] = []` init parameter, a
`CodingKeys` entry, decoded with `decodeIfPresent(...) ?? []`). `formatVersion` stays 1. The lock
lives with the binder, so every new `BinderSession` (relaunch, render, day switch) has it without
asking the hand-off controller.

`BinderSession` gains:

```swift
/// Whether `key` was sent to Claude and can no longer be written on.
public func isLocked(_ key: PageKey) -> Bool
/// Makes `keys` read-only, drops their undo and redo history, and saves the day.
public func lock(_ keys: [PageKey])
/// Makes `keys` writable again and saves the day.
public func unlock(_ keys: [PageKey])
/// Makes every page writable again and saves the day.
public func unlockAll()
/// Whether a page can be added after `key`: not after a locked page.
public func canAddPage(after key: PageKey) -> Bool
```

- `setInk(_:on:)` does nothing for a locked key.
- `canDelete(_:)` is false for a locked key.
- `lock` appends the keys not already in `day.locked`; `unlock` and `unlockAll` remove keys. All
  three set `message` to `"Couldn't save the binder. Free some space on this device."` when
  `saveDay` throws, and leave `message` alone on success (it may hold an unrelated ink-save error).
- `addPage(after:)` keeps its signature. The view only calls it when `canAddPage` is true.

`BinderLayout.rebased` treats a key in `day.locked` as kept, the same as an inked one, and the
returned `BinderDay` carries `locked: day.locked`. A sent page can then never fall out of the
binder on a later Render, even without ink. A locked page whose meeting is still in the content is
laid out from the new content (its title can change on screen). That is accepted: what was sent
is the PDF already in Drive.

`AgendaController` gains `public var canStartOver: Bool { binder?.day.locked.isEmpty ?? true }`.
`startOver()` begins with `guard canStartOver else { message = "A meeting on this day was already sent to Claude, so it can't be started over. Reset its hand-off first."; return }`.
Reset Hand-off (#14) unlocks the pages, which makes Start Over possible again.

Rejected: keeping the lock only in the hand-off records and having views ask the hand-off
controller. `AgendaController` builds `BinderSession`s and does the rebasing without knowing the
hand-off controller, so the lock would have to be pushed into each new session from a view.

### D8. UI (iPad)

- `BinderToolbar` gains `canAddPage: Bool`, `canSendMeeting: Bool` and `sendMeeting: () -> Void`.
  The add-page button uses `isEnabled: canAddPage`. After the delete button come a `Divider().frame(height: 24)`
  and `button("paperplane", "Send this meeting to Claude now", BinderView.ID.sendMeetingButton, isEnabled: canSendMeeting) { sendMeeting() }`.
- `BinderView.ID` gains `sendMeetingButton = "sendMeetingButton"`,
  `confirmSendMeetingButton = "confirmSendMeetingButton"`,
  `cancelSendMeetingButton = "cancelSendMeetingButton"` and `sentBadge = "sentBadge"`.
- `BinderView`: `@State private var confirmsSendMeeting = false` and `@State private var sendMeetingKey: PageKey?` (set to `visibleKey` when the alert opens).
  `canSendMeeting = !handoff.isBusy && (visibleKey.map { handoff.canSendMeeting(containing: $0, of: binder) } ?? false)`.
  `canAddPage = visibleKey.map { binder.canAddPage(after: $0) } ?? true`. The alert is titled
  `"Send this meeting to Claude now?"` with the message
  `"Its pages are uploaded with their own Google Doc and can't be written on afterwards. Finish Day still sends the rest of the day."`,
  a `"Send"` button (`confirmSendMeetingButton`) running
  `Task { await handoff.sendMeeting(containing: key, of: binder) }` for the key visible when the
  alert opened, and `"Cancel"` (`cancelSendMeetingButton`, role `.cancel`). Reset Hand-off's
  confirm button calls `handoff.resetHandoff(for: binder.date, unlocking: binder)`, and its toolbar
  item shows when `handoff.hasHandoff(on: binder.date) || !binder.day.locked.isEmpty`.
- Each page in `pages(_:)`: `.overlay(alignment: .top) { if binder.isLocked(page.key) { badge } }`
  placed right after `.accessibilityValue(...)` and before `.padding(16)`, where `badge` is
  `Label("Sent to Claude", systemImage: "lock.fill")` in `.footnote` on a `.regularMaterial`
  capsule with `accessibilityIdentifier(ID.sentBadge)`. The page itself has
  `.accessibilityElement(children: .ignore)`, so the UI test reads the page's value
  (`"Sent to Claude"`) as well as the badge. The page's `accessibilityValue` is
  `"Sent to Claude"` when locked, otherwise `"Blank"` or `"Handwritten"` as now.
  `BinderPageView` gets `isLocked: binder.isLocked(page.key)`.
- `BinderPageView` gains `let isLocked: Bool`. In `updateUIView`:
  `view.canvas.drawingGestureRecognizer.isEnabled = !isLocked`. Link taps keep working, because
  they use their own tap recognizer.
- `AgendaView`'s Start Over button: `.disabled(!canRender || !controller.canStartOver)`.
- `ReviewView`: `ForEach(..., id: \.element.id)`, the row headline is `Text(day.displayTitle)`,
  `handoff.docURL(for: day.id)`, `handoff.perform(action, on: day.id)`. The spoken labels use
  `day.displayTitle` where they use `day.date.isoString` today ("Open the Google Doc for
  2026-10-26 · Team sync").

### D9. Fixtures

- `FixtureEndOfDay` keys what it records by `key = date` for a day run, or
  `"\(date)-part-\(part)"` for a meeting run. It decodes `date`, `step`, `part: Int?` and
  `pages[].summarySkill` / `pages[].earlierPart`. `hadSummarySkill` counts only pages with a skill
  and no `earlierPart`. `docText(forDate:)` is renamed `docText(forKey:)`.
- `FixtureDrive`: for a name, the key is the text after `"Magenda "` with a trailing `".pdf"` or
  `" notes"` removed and `" part "` replaced by `"-part-"`. `"Magenda 2026-10-26 part 1 notes"`
  gives `2026-10-26-part-1`. `uploadPDF` returns `"file-" + key`, `createDoc` returns
  `"doc-" + key`, and `exportText` answers `docText(forKey: docID.dropFirst("doc-".count))`.

### D10. Routine contract

`docs/end-of-day-handoff.md` documents schema 2 (D4), the part names in Drive (D3), and the meeting
run's steps: `notes` writes that meeting's notes; `approve-notes` writes its summary when it has a
skill, else closes; closing prepares that meeting's memo draft and updates the tasks from its pages
only. For a day run, every page with `earlierPart` is skipped in notes, summaries, memos and task
updates. The overview, delegated, notes and unsent meeting pages are processed as before. The
idempotency rule is unchanged: a part's PDF has its own checksum.

## ADRs

- **ADR 0033**: A meeting can be sent to the routine before the day ends, as its own PDF and Doc with
  the same review loop, and its pages are locked afterwards. Amends ADR 0027 (the Drive names and
  "that single PDF"), ADR 0029 (a Doc per day and per sent meeting) and ADR 0030 (only a finished
  day starts the five-day deletion; a date with only sent meetings is not purged). Consequences
  name ADR 0023 (locking drops the pages' undo history) and ADR 0025 (a locked added page cannot
  be deleted).
- **ADR 0034**: The routine payload moves to `magenda.end-of-day/2`. The day's PDF keeps the
  meetings sent earlier, and the payload marks their pages with `earlierPart` so the routine skips
  them. Amends ADR 0028. Rejected: leaving them out of the day's PDF (the user chose a complete
  day PDF), and adding the key under schema 1 (an old routine would ignore the mark and process
  the meeting twice).
- **ADR 0035**: Start Over is refused while a meeting of the day is sent, and Reset Hand-off
  unlocks the pages. Amends ADR 0026 and ADR 0032.

## Manual steps

No `manual_before`. Two `manual_after` items, with step-by-step instructions in the
[manual-steps page](https://claude.ai/artifact/53rtDnpeTYjbNYR9xxD5qe):

- **ma1** Update the end-of-day routine's skill to schema `magenda.end-of-day/2`. Until then the
  routine stops on every payload, the day's too.
- **ma2** On an iPad, send a meeting early, review it to Closed, then finish the day and check
  that the day's notes cover the overview and delegated pages but not that meeting.

## Risks and open questions

- **#14 changes before it merges.** The plan branch is cut from #14's head, not from `main`, at
  the user's request. If #14's head changes, merge it into `plan/send-meeting-early` before
  `/implement`. The plan assumes `HandoffStore.deleteHandoff(for:)`,
  `HandoffController.resetHandoff(for:)` and `hasHandoff(on:)` as in `423af6b`. If a phase finds
  them missing or different, it stops with `status=blocked`.
- **Records saved with schema 1 payloads.** Payloads are built when they are fired, so a day queued
  before the update is sent as schema 2. That is intended.
- **`PKCanvasView.drawingGestureRecognizer`.** If disabling it also blocks link taps on a locked
  page, p4's first UI test shows it (it taps back to the overview from a locked page). The
  fallback is written out in p4's brief.
- **A UI test cannot find a meeting page.** The standard fixture's page order depends on its
  delegated tasks. The test swipes until `sendMeetingButton` is enabled, at most 6 swipes. If it
  never is, the worker stops with `status=blocked` and reports the page labels it saw, and does
  not change the fixture.
- **No Swift toolchain in a cloud container.** Each phase pushes its branch and reads `tests.yml`'s
  `core` and `lint` jobs, per `.claude/skills/steward/SKILL.md`.

## Implementation manifest

```yaml
plan_slug: send-meeting-early
feature_branch: feature/send-meeting-early
max_parallel: 2
manual_steps_artifact: https://claude.ai/artifact/53rtDnpeTYjbNYR9xxD5qe
manual_steps_source: docs/send-meeting-early-plan-manual-steps.html
manual_before: []
manual_after:
  - id: ma1-update-routine-skill
    title: Update the end-of-day routine's skill to payload schema magenda.end-of-day/2
    why: The schema bump makes an unadapted routine stop on every payload; only the person can edit their own skill outside this repository.
  - id: ma2-ipad-send-meeting-early
    title: On an iPad, send one meeting early, review it to Closed, then finish the day and check the day's notes skip that meeting
    why: CI uses fixture Drive and routine; only a real Drive, routine and Pencil show the whole loop works.
verify_after_merge:
  - swift test --package-path AppCore --filter "Handoff|Binder|RenderPlan|AgendaController" (without a toolchain, the core job of a dispatched tests.yml)
  - python3 -m unittest discover -s scripts/tests
final_checks:
  - docs/send-meeting-early-plan.md and docs/send-meeting-early-plan-manual-steps.html are deleted and nothing links to them
  - docs/adr/0033-*.md, 0034-*.md and 0035-*.md exist, are Accepted, and are in docs/adr/README.md's index
  - ADRs 0023, 0025 are not edited; ADRs 0026, 0027, 0028, 0029, 0030 and 0032 each have one added Status line pointing to the ADR that amends them, and no other change
  - docs/end-of-day-handoff.md says magenda.end-of-day/2 and no longer says magenda.end-of-day/1
  - CHANGELOG.md has [Unreleased] entries and no version heading
  - tests.yml dispatched against feature/send-meeting-early is green, core, lint, scripts, app and ui jobs included
phases:
  - id: p1-binder-lock
    title: Locked pages in BinderDay, BinderSession and the rebase; Start Over refused while locked
    depends_on: []
    complexity: M
    touches:
      - AppCore/Sources/Binder/BinderDay.swift
      - AppCore/Sources/Binder/BinderLayout.swift
      - AppCore/Sources/Binder/BinderSession.swift
      - AppCore/Sources/Controller/AgendaController.swift
      - AppCore/Tests/Binder/BinderDayTests.swift
      - AppCore/Tests/Binder/BinderLayoutTests.swift
      - AppCore/Tests/Binder/BinderSessionTests.swift
      - AppCore/Tests/Controller/AgendaControllerBinderTests.swift
    brief: |
      Implement the plan's Design section D7 exactly (names, signatures, messages). No CHANGELOG
      line here; the last phase writes it. Steps:
      1. BinderDay.swift: add `public var locked: [PageKey]` with a doc comment ("The pages sent to
         Claude, which can no longer be written on."), an init parameter `locked: [PageKey] = []`
         after `retained`, a `locked` CodingKeys case, and decoding with
         `try container.decodeIfPresent([PageKey].self, forKey: .locked) ?? []`. Leave
         `formatVersion` at 1. The synthesized encoder then writes `locked`; keep it synthesized.
      2. BinderLayout.swift `rebased(_:onto:theme:inkedKeys:)`: a key is kept when
         `inkedKeys.contains(key) || day.locked.contains(key) || <the existing extras clause>`.
         Pass `locked: day.locked` to the returned `BinderDay`. Update the doc comment to say that
         locked pages are kept like inked ones.
      3. BinderSession.swift: add `isLocked(_:)`, `lock(_:)`, `unlock(_:)`, `unlockAll()` and
         `canAddPage(after:)` as specified in D7. `lock` also removes `undoStack` and `redoStack`
         entries whose key is being locked. `setInk` returns early for a locked key. `canDelete`
         returns false for a locked key. The three mutators save with `store.saveDay(day)`; on a
         throw they set `message = "Couldn't save the binder. Free some space on this device."`,
         on success they leave `message` as it is.
      4. AgendaController.swift: add `public var canStartOver: Bool` and the guard at the top of
         `startOver()` from D7, with that exact message.
      5. Tests (Swift Testing, following each file's existing patterns):
         BinderDayTests: `locked` round-trips through JSON; a day JSON without `locked` decodes
         with `locked == []`.
         BinderLayoutTests: a locked meeting page without ink stays (as a retained page) after
         rebasing onto content without that meeting; `locked` is carried through `rebased`.
         BinderSessionTests: `setInk` on a locked page changes nothing and saves nothing; `lock`
         drops that page's undo and redo entries and keeps the others'; `canDelete` is false for a
         locked added page; `canAddPage(after:)` is false after a locked page and true otherwise;
         `unlock` and `unlockAll` remove the locks and save; a `saveDay` failure during each of
         `lock`, `unlock` and `unlockAll` sets the message (use
         `AppCore/Tests/Support/FailingBinderStore.swift`).
         AgendaControllerBinderTests: with a locked page, `startOver()` keeps the ink and the
         day, sets the message, and `canStartOver` is false; without one, `canStartOver` is true.
      6. Every new line is covered: `scripts/check_coverage_floor.py` has a 100 % overall floor.
      7. Run `swift format format --in-place` on the touched files if a toolchain is present;
         otherwise push and read the `core` and `lint` jobs of a dispatched `tests.yml`.
      Stop with status=blocked if `BinderDay` turns out not to use a synthesized `encode(to:)`
      (D7 assumes it does), or if `rebased` no longer has the signature shown in D7.
    acceptance:
      - "`swift test --package-path AppCore --filter \"BinderDayTests|BinderLayoutTests|BinderSessionTests|AgendaControllerBinderTests\"` passes (or the core job of tests.yml on the phase branch)"
      - "`grep -n 'public func lock(_ keys: \\[PageKey\\])' AppCore/Sources/Binder/BinderSession.swift` finds one line"
      - "`grep -n 'public var canStartOver' AppCore/Sources/Controller/AgendaController.swift` finds one line"
      - "`grep -n 'formatVersion = 1' AppCore/Sources/Binder/BinderDay.swift` still finds one line"
      - "`python3 scripts/check_coverage_floor.py` passes on the core job's coverage report"
  - id: p2a-handoff-model
    title: RenderPlan.subset, HandoffID, parts, the schema 2 payload and the fixtures
    depends_on: []
    complexity: M
    touches:
      - AppCore/Sources/Layout/RenderPlan.swift
      - AppCore/Sources/Handoff/DayHandoff.swift
      - AppCore/Sources/Handoff/HandoffFixtures.swift
      - AppCore/Tests/Layout/RenderPlanTests.swift
      - AppCore/Tests/Handoff/DayHandoffTests.swift
      - AppCore/Tests/Handoff/HandoffFixturesTests.swift
    brief: |
      Implement Design sections D1, D2, D3, D4 and D9. No CHANGELOG line here. Steps:
      1. RenderPlan.swift: add `subset(_:)` (D2). Remap each kept `.link(rect, targetPage: t)` to
         the index of `pages[t]`'s key in the result; drop it when that page is not kept or `t` is
         out of range.
      2. DayHandoff.swift: add `HandoffID` (with `listOrder`), `HandoffPart`, `HandoffPage.earlierPart`
         (`bare` keeps it), `DayHandoff.part` and the computed `id`, `pageKeys`, `displayTitle`,
         `pdfName` and `docName`, the `earlierParts` parameter on the day initializer, the meeting
         initializer, `meetingPages(containing:day:plan:)`, `HandoffPhase.meetingClosed`, and the
         schema 2 payload with `scope` and `part` (D4). For a part, set `Payload.tasks` and
         `Payload.delegated` to nil. The `HandoffStore` protocol is not touched here; the store
         still keys by date until the next phase.
      3. HandoffFixtures.swift: D9.
      4. Tests. RenderPlanTests: subset keeps order, remaps links, drops links to left-out pages
         and out-of-range targets, and empties omittedTodoItems. DayHandoffTests: change the
         existing assertion at line 231 to `magenda.end-of-day/2`; add payload tests in the style
         of the existing test at `DayHandoffTests.swift:210` (decode with `JSONSerialization` and
         check keys and values): a day payload with `scope` `day` and a page with `earlierPart`; a
         part payload with `scope` `meeting`, `part`, and no `tasks` or `delegated` keys;
         truncation keeps `earlierPart`; `meetingPages` for a meeting page, for an added copy of
         it, for the overview, for `.meeting("")` and for an added copy of the overview;
         `displayTitle`, `pdfName`, `docName`; `listOrder`; `phase` `.meetingClosed` for a closed
         part; decoding a record without `part`. HandoffFixturesTests: part keys for names, docs
         and payloads; `hadSummarySkill` ignores `earlierPart` pages.
      5. Keep `AppCore/Sources/Handoff/DayHandoff.swift` and `HandoffFixtures.swift` at 100 % line
         coverage, and every new line in RenderPlan.swift covered.
      Stop with status=blocked if PR #14's `deleteHandoff(for:)`, `hasHandoff(on:)` or
      `resetHandoff(for:)` are not in the baseline as the plan's Current state describes.
    acceptance:
      - "`swift test --package-path AppCore --filter \"RenderPlanTests|DayHandoffTests|HandoffFixturesTests|HandoffControllerTests\"` passes (or the core job of tests.yml on the phase branch)"
      - "`grep -rn 'end-of-day/1' AppCore` finds nothing; `grep -n 'magenda.end-of-day/2' AppCore/Sources/Handoff/DayHandoff.swift` finds one line"
      - "`python3 scripts/check_coverage_floor.py` passes on the core job's coverage report"
  - id: p2b-handoff-store
    title: The store and the controller keyed by HandoffID; the Review list shows parts
    depends_on: [p2a-handoff-model]
    complexity: M
    touches:
      - AppCore/Sources/Handoff/HandoffStore.swift
      - AppCore/Sources/Handoff/HandoffController.swift
      - App/Screens/ReviewView.swift
      - AppCore/Tests/Handoff/HandoffStoreTests.swift
      - AppCore/Tests/Handoff/HandoffControllerTests.swift
    brief: |
      Implement Design section D5, the "Adapted" half of D6 (not the "New" half; no `sentKeys`,
      `canSendMeeting` or `sendMeeting`; leave `resetHandoff`'s signature as it is), the purge
      paragraph of D6, and the ReviewView bullet of D8. No CHANGELOG line here. Steps:
      1. HandoffStore.swift: change the protocol and both stores to D5. `FileHandoffStore`'s file
         names: `handoff.json` and `day.pdf` for `part == nil`, `part-<n>.json` and `part-<n>.pdf`
         for part n. `handoffs()` and `handoff(_ id:)` skip or reject a file whose decoded `id`
         does not match its name (a `handoff.json` holding a record with a `part` included).
         `handoffs()` sorts with `HandoffID.listOrder`.
      2. HandoffController.swift: `stored(_ id:)`, `remember` removing by `id` (not by date) and
         inserting by `HandoffID.listOrder`, `canFinish` on the day ID, `hasHandoff(on:)` over any
         record of the date, `docURL(for id:)`, `perform(_:on id:)`, `finish(_:)` using the day ID
         for the earlier record, the savePDF and the result message, `runPipeline` with `pdfName`,
         `docName`, `store.pdf(for: handoff.id)` and the part's missing-PDF text, the purge
         exactly as in D6's "Purge" paragraph, and `resetHandoff(for:)` guarding on "any record on
         the date" and removing every record of the date from `days`.
      3. ReviewView.swift: the D8 ReviewView bullet. `spokenTitle(of:on:)` takes the display title
         `String` instead of a `CalendarDay`.
      4. Tests. HandoffStoreTests (both kinds): saving, reading and listing a day with two parts
         in listOrder; `part-<n>.pdf` read and delete; a `part-x.json`, `part-0.json` and a part
         file whose record has another id are skipped; `deleteHandoff(for:)` removes the parts
         too. HandoffControllerTests: update `FailingHandoffStore` and every call to the ID API;
         keep every existing test passing with the same expectations. New purge tests set up part
         records by saving a closed day record and part records straight into the store, calling
         `controller.start()`, then setting the clock past `purgeDelayDays`: the purge deletes a
         finished part's PDF and marks it purged before the day; a part still `.uploaded` keeps its
         PDF; a date with only parts is never purged; remembering a part keeps the day's record in
         `days`; `resetHandoff` removes the parts from `days`.
      5. Keep `AppCore/Sources/Handoff/*` at 100 % line coverage.
      Stop with status=blocked if PR #14's `deleteHandoff(for:)`, `hasHandoff(on:)` or
      `resetHandoff(for:)` are not in the baseline as the plan's Current state describes.
    acceptance:
      - "`swift test --package-path AppCore --filter \"HandoffStoreTests|HandoffControllerTests\"` passes (or the core job of tests.yml on the phase branch)"
      - "`grep -n 'func pdf(for id: HandoffID)' AppCore/Sources/Handoff/HandoffStore.swift` finds the protocol requirement"
      - "`python3 scripts/check_coverage_floor.py` passes on the core job's coverage report"
      - The app builds in tests.yml's app jobs (ReviewView compiles against the ID API)
  - id: p3-send-meeting
    title: HandoffController sends a meeting, marks earlier parts at Finish Day, and Reset Hand-off unlocks
    depends_on: [p1-binder-lock, p2b-handoff-store]
    complexity: M
    touches:
      - AppCore/Sources/Handoff/HandoffController.swift
      - AppCore/Tests/Handoff/HandoffControllerTests.swift
    brief: |
      Implement the "New" half of Design section D6 (the nine steps and messages, which already
      include the early lock and unlocking on failure), and `resetHandoff(for:unlocking:)`
      including the stuck-lock case. No CHANGELOG line here. Steps:
      1. HandoffController.swift: add `sentKeys(on:)` (the union of `pageKeys` of every part record
         of the date), `canSendMeeting(containing:of:)` and `sendMeeting(containing:of:)`.
         Extract the read-and-remove of the rendered file from `renderedPDF(of:)` so both paths
         share it, and keep `renderedPDF(of:)`'s behaviour.
      2. `resetHandoff(for date: CalendarDay, unlocking binder: BinderSession? = nil)`: delete as
         today when the date has a record, then call `binder?.unlockAll()` when
         `binder?.date == date`; with no record but a binder for that date with locked pages, only
         unlock. Keep the existing messages and guards otherwise.
      3. Leave `AppCore/Tests/Support/FakeDrive.swift` as it is (it answers `file-1` and `doc-1`
         every time).
      4. HandoffControllerTests: do not change `Self.binderDay`. In the new tests build a separate
         `BinderDay` with two meetings (ids `cal|a` and `cal|b`, an added copy of the first) and a
         `BinderSession` over `InMemoryBinderStore` (or whatever store the rig's `binder` uses),
         and a controller over it. Tests:
         - sending a meeting uploads `Magenda <date> part 1.pdf`, creates
           `Magenda <date> part 1 notes`, fires a schema 2 payload with `scope` `meeting` and
           `part` 1, locks the meeting page and its added copy in the binder, sets the success
           message, and lists the part in `days`; after Finish Day `days` holds the day's record
           before the part (`HandoffID.listOrder`);
         - the renderer received only the meeting's pages, with their ink;
         - a second meeting becomes part 2;
         - `canSendMeeting` is false on the overview, on a sent meeting, and once the day has a
           day record, and true on an unsent meeting page and on an added copy of it;
         - sending when the day is finished sets the "already finished" message and fires nothing;
           sending a sent meeting sets the "already sent" message;
         - a render failure and a save failure set their messages, store no record, and leave the
           pages unlocked again;
         - a fire failure keeps the part with its `lastError` and the pages locked, and Try again
           on the part (`perform(.retry, on: part.id)`) sends it;
         - Finish Day after sending a meeting fires a day payload whose meeting page entry and its
           added copies carry `earlierPart` 1, whose other pages carry none, and which reuses the
           day's own Drive IDs (never a part's);
         - approve-notes on the part fires for the part only (the day record is untouched);
         - `resetHandoff(for:unlocking:)` removes the day and the parts, unlocks the binder, and
           makes `canSendMeeting` true again; without a binder it leaves the binder locked; with
           no record but a locked binder it only unlocks;
         - `sentKeys(on:)` returns the parts' keys.
      5. Keep HandoffController.swift at 100 % line coverage.
      Stop with status=blocked if `BinderSession.lock`, `unlock`, `isLocked` or `unlockAll` (p1),
      or `DayHandoff.meetingPages`, the meeting initializer or the ID-keyed store (p2a, p2b), are
      missing or have other signatures than the plan's.
    acceptance:
      - "`swift test --package-path AppCore --filter HandoffControllerTests` passes (or the core job of tests.yml on the phase branch)"
      - "`grep -n 'public func sendMeeting(containing key: PageKey, of binder: BinderSession) async' AppCore/Sources/Handoff/HandoffController.swift` finds one line"
      - "`grep -n 'unlocking binder: BinderSession? = nil' AppCore/Sources/Handoff/HandoffController.swift` finds one line"
      - "`python3 scripts/check_coverage_floor.py` passes on the core job's coverage report"
  - id: p4-ui
    title: Send Meeting in the binder, locked pages, Start Over disabled, and the UI tests
    depends_on: [p3-send-meeting]
    complexity: M
    touches:
      - App/Screens/BinderView.swift
      - App/Screens/BinderToolbar.swift
      - App/Screens/BinderPageView.swift
      - App/Screens/AgendaView.swift
      - AppUITests/HandoffUITests.swift
    brief: |
      Implement Design section D8 except the ReviewView bullet (done in p2b), with the exact
      identifiers, labels, strings and modifier placement given there. No CHANGELOG line here.
      1. BinderToolbar.swift: the three new parameters and the two buttons as in D8.
      2. BinderPageView.swift: `let isLocked: Bool`, applied in `updateUIView` as
         `view.canvas.drawingGestureRecognizer.isEnabled = !isLocked`.
      3. BinderView.swift: the new IDs, `confirmsSendMeeting`, `sendMeetingKey`, the toolbar
         wiring (`canAddPage`, `canSendMeeting`, `sendMeeting: { sendMeetingKey = visibleKey; confirmsSendMeeting = true }`),
         the alert (with no `sendMeetingKey`, the Send button does nothing), the locked badge
         overlay and accessibility value, `isLocked:` on `BinderPageView`, Reset Hand-off's
         confirm calling `handoff.resetHandoff(for: binder.date, unlocking: binder)`, and its
         toolbar item condition. Keep the `#Preview` building.
      4. AgendaView.swift: Start Over `.disabled(!canRender || !controller.canStartOver)`.
      5. AppUITests/HandoffUITests.swift: add a helper `sendFirstMeeting(_ app:)`: swipe left on
         `binderView` until `sendMeetingButton` is enabled (at most 6 swipes, waiting for the page
         indicator to change after each one, as BinderUITests.testAFingerSwipesToTheNextPage
         does; the toolbar scrolls sideways, so check `isEnabled` and `isHittable` before the tap
         and stop as blocked if it is not hittable), tap it, tap `cancelSendMeetingButton` and
         check the button is still enabled, tap it again and `confirmSendMeetingButton`, and wait
         for `handoffMessage`. Add
         `testSendingAMeetingLocksItAndGivesItItsOwnReviewRow` (iPad only): launch, `render(app)`,
         `sendFirstMeeting`; check `sentBadge` exists, the page's accessibility value is
         `Sent to Claude`, `sendMeetingButton` is not enabled and `startOverButton` is not
         enabled; tap the overview link on the locked page's header if it has one, or else tap
         `binderOverviewButton`, and check the indicator reads "Page 1 of"; swipe back to a
         meeting page; tap `finishDayButton` and wait for it to become disabled, as
         `testFinishedDayIsReadyForReview`'s neighbour at line 137 does, before `openReview`; check
         `reviewStatus.0` and `reviewStatus.1` both reach a label beginning "Notes ready for
         review" and `reviewRow.1` exists. Add `testResetHandoffUnlocksASentMeeting`:
         `sendFirstMeeting`, tap `resetHandoffButton` and `confirmResetHandoffButton`, then check
         `sentBadge` is gone and `sendMeetingButton` is enabled again.
      6. Push the branch and dispatch `tests.yml` against it (`.claude/skills/steward/SKILL.md`).
         Read the `app (...)` jobs and the iPad `binder` UI shard.
      If the link check in the first test shows that a link tap on a locked page no longer moves
      pages, apply this fallback and nothing else: keep the tap recognizer on `BinderPageUIView`,
      set `view.canvas.isUserInteractionEnabled = !isLocked` instead of the gesture recognizer, and
      compute the point in the tap handler as `recognizer.location(in: pageView.canvas)` divided
      by `pageView.canvas.zoomScale`. If the swipe loop never finds an enabled `sendMeetingButton`,
      stop with status=blocked and report the page accessibility labels seen; do not change the
      fixture.
    acceptance:
      - tests.yml dispatched against the phase branch passes its three app jobs and the ui (ipad, newest, binder) job, with both new HandoffUITests tests run (not skipped) on the iPad
      - "`grep -n 'sendMeetingButton' App/Screens/BinderView.swift App/Screens/BinderToolbar.swift AppUITests/HandoffUITests.swift` finds the ID, its use in the toolbar and in the test"
      - "`grep -n 'controller.canStartOver' App/Screens/AgendaView.swift` finds one line"
  - id: p5-retire
    title: ADRs 0033 to 0035, the routine contract, README, changelog, and retire the plan
    depends_on: [p4-ui]
    complexity: S
    touches:
      - docs/adr/0033-a-meeting-can-be-sent-before-the-day-ends.md
      - docs/adr/0034-the-payload-moves-to-schema-2-and-marks-pages-sent-earlier.md
      - docs/adr/0035-start-over-is-refused-while-a-meeting-is-sent.md
      - docs/adr/0026-start-over-is-separate-from-render.md
      - docs/adr/0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md
      - docs/adr/0028-the-end-of-day-routine-is-started-through-its-api-trigger.md
      - docs/adr/0029-the-days-google-doc-is-the-review-record.md
      - docs/adr/0030-a-closed-days-handwriting-is-deleted-five-days-later.md
      - docs/adr/0032-a-sent-days-hand-off-can-be-reset-after-asking.md
      - docs/adr/README.md
      - docs/end-of-day-handoff.md
      - docs/release-testing.md
      - README.md
      - CHANGELOG.md
      - docs/send-meeting-early-plan.md
      - docs/send-meeting-early-plan-manual-steps.html
    brief: |
      1. Write ADRs 0033, 0034 and 0035 with the template in docs/adr/README.md, Status
         "Accepted — <today>. Implemented.", one decision each as in the plan's ADRs section.
         Take Context, Decision, Alternatives (the "Rejected" notes in D3, D4 and D7) and
         Verification (the source and test files the phases changed) from the plan's Design.
         ADR 0033's Consequences name ADR 0023 and ADR 0025 as in the plan. Link no plan document
         (ADR rule 4).
      2. Add one Status line to each amended ADR: 0026 and 0032 "Amended by [ADR 0035](...)",
         0028 "Amended by [ADR 0034](...)", 0027, 0029 and 0030 "Amended by [ADR 0033](...)".
         Change nothing else in them.
      3. docs/adr/README.md: add the three index rows.
      4. docs/end-of-day-handoff.md: rewrite to D10. Schema `magenda.end-of-day/2` with `scope`,
         `part` and `earlierPart` in the key list, a meeting-run example (D4), the part file names
         in the Drive layout table, the meeting run's steps, the rule that a day run skips
         `earlierPart` pages, and a "Sending a meeting early" section. Keep the "Sending a day
         again" section, and add that a reset also forgets the date's sent meetings and unlocks
         their pages. In the deletion section, say only a finished day starts the five-day
         deletion.
      5. README.md: one sentence after the Finish Day paragraph saying that Send Meeting on a
         meeting page sends that meeting on its own, with its own Doc, and locks its pages; and in
         the Start over paragraph, that Start Over is refused while a meeting is sent.
      6. docs/release-testing.md: add one checklist line for Send Meeting in the place where the
         Finish Day check is listed (read the file; follow its format).
      7. CHANGELOG.md under `## [Unreleased]`: one line for Send Meeting (own PDF and Doc, own
         review row, pages locked, Finish Day skips it in the notes) and one line saying the
         end-of-day routine must be updated to payload schema 2 (docs/end-of-day-handoff.md) and
         stops until it is.
      8. Delete docs/send-meeting-early-plan.md and docs/send-meeting-early-plan-manual-steps.html.
         `grep -rn 'send-meeting-early-plan' .` must find nothing.
      9. `python3 -m unittest discover -s scripts/tests` passes (the no-project-history guard
         reads the docs).
    acceptance:
      - "`ls docs/adr/0033-*.md docs/adr/0034-*.md docs/adr/0035-*.md` lists three files, each containing 'Accepted'"
      - "`grep -rn 'send-meeting-early-plan' . --exclude-dir=.git` finds nothing"
      - "`grep -n 'end-of-day/1' docs/end-of-day-handoff.md` finds nothing"
      - "`python3 -m unittest discover -s scripts/tests` passes"
```
