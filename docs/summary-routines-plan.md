# Plan: one dedicated Claude routine per summary

> **Orchestrator: this plan's PR is stacked.** It builds on `plan/settings-improvements`, which
> itself carries `plan/send-meeting-early` (PR #14 → send-meeting-early → settings-improvements).
> This plan branch already contains `feature/settings-improvements` as of `4909938`, which holds
> send-meeting-early's hand-off phases p1–p3 and settings-improvements' p1 and p3. The pull request
> opens with **base `feature/settings-improvements`, not `main`** (see "Stacked on
> settings-improvements" below; it overrides `/implement` sections 5 and 6 where they say `main`).

## Goal

Today one Claude routine, the end-of-day routine, does everything after a day is sent: it writes the
notes, writes any meeting summaries with the skill named for the meeting, updates Google Tasks and
prepares Gmail drafts. The person does not want a routine that is started through an API trigger
to hold that many permissions, and does not want several summary skills writing other assets from
one place.

After this change:

- Each kind of summary is its own **summary routine**: a Claude routine with its own API trigger
  and its own token, set up once in **Settings → Summary routines** (a name, the fire URL, the
  token). The end-of-day routine no longer writes summaries.
- A meeting asks for summaries by **checkboxes**, not by a typed skill name: the person ticks
  summary routines per meeting title in **Settings → Binder rules → Meeting summaries**, or for one
  meeting on its **Edit sheet** in the agenda. A meeting can tick any number of routines.
- After the person taps **Approve notes** (the notes step, which reads the PDF, is done), Magenda
  starts each ticked summary routine once, each with a payload naming only the meetings it
  summarizes. Each routine writes its summary into the day's Doc, or the meeting's Doc for a
  meeting sent early. When every ticked summary has arrived the Review row offers
  **Approve summaries**, and that starts the end-of-day routine's new `close` step.

There is no issue; the request is the `/make-plan` argument (session `01BfjJVfiganWDv38aEwUbGN`).

## Current state

The line numbers below are from `plan/summary-routines` as cut (the tree of
`feature/settings-improvements` at `4909938`). The hand-off files moved under send-meeting-early;
nothing here may be assumed from `main`.

- **Summary skills.** `BinderRules.summarySkills: [String: String]` maps a meeting title to a skill
  name (`AppCore/Sources/Settings/BinderRules.swift`); `SummarySkill` validates names and looks the
  skill up by folded title (`AppCore/Sources/Settings/SummarySkill.swift`, 35 lines). The skill is
  carried in `DraftEvent.summarySkill`, `AgendaDraft.summarySkills`, `AgendaContent.meetingSummarySkills`
  (`AppCore/Sources/Agenda/AgendaContent.swift:95`), printed after a `Summary:` label on the
  meeting page (`AgendaLayout.meetingSummaryOperations`, `AppCore/Sources/Layout/AgendaLayout.swift:180`,
  with a ruled line to handwrite a skill on when none is mapped) and sent as
  `HandoffPage.summarySkill` in the payload (`AppCore/Sources/Handoff/DayHandoff.swift`).
- **One routine.** `RoutineCredentials` (fire URL + token, `RoutineTrigger.swift`) is stored once in
  the Keychain (`App/Platform/KeychainRoutineCredentialsStore.swift`) and entered in
  `SettingsView.routineSection` (`App/Screens/SettingsView.swift`). `HandoffController` fires it
  with `RoutineStep` `notes`, `approve-notes`, `approve-summary` (`AppCore/Sources/Handoff/DocStatus.swift:4`).
  In the routine, `approve-notes` writes the summary when any page has a skill, then sets
  `Status: Summary ready for review`; `approve-summary` closes.
- **Doc status.** `DocStatus` reads only the Doc's first line (`Waiting for notes`, `Notes ready for
  review`, `Summary ready for review`, `Closed`). `DayHandoff.phase` maps stage × status to a Review
  row; `HandoffAction` is `.retry` or `.approve(RoutineStep)`.
- **Records.** After send-meeting-early a record is a finished day or a meeting sent early
  (`HandoffID`, `HandoffPart`), each with its own PDF and Doc; the payload is schema
  `magenda.end-of-day/2` with `scope`, `part` and `pages[].earlierPart`. A day's pages that were
  sent in a part carry `earlierPart` and must not be processed again.
- **Settings.** `AgendaSettings` (`AppCore/Sources/Settings/AgendaSettings.swift`) has the rules and
  `driveFolderName`. `AgendaController.updateSettings` (`AgendaController.swift:258`) reloads when
  `after.rules` changed and clears the rendered PDF on any change but the folder name.
- **Coverage.** `scripts/check_coverage_floor.py` requires 100 % line coverage over AppCore with
  per-file floors for `SummarySkill.swift`, `RoutineTrigger.swift`, `DayHandoff.swift`,
  `DocStatus.swift`, `HandoffController.swift` and `HandoffFixtures.swift`.
- **Docs.** `docs/end-of-day-handoff.md` is the routine contract; ADR 0031 is the skill decision.

## Design

### D1. Summary routines (names, storage, validation)

New file `AppCore/Sources/Settings/SummaryRoutine.swift`:

```swift
/// A summary routine the person set up: one Claude routine with its own API trigger.
public struct SummaryRoutine: Equatable, Hashable, Codable, Identifiable, Sendable {
    /// A lowercase UUID string, made when the routine is added and never changed.
    public let id: String
    /// What the checkboxes and the meeting page show.
    public var name: String
    public init(id: String, name: String)

    /// The longest name accepted, in characters.
    public static let maxNameLength = 40
    /// What Settings shows when `validatedName` returns nil.
    public static let invalidNameMessage = "Use 1 to 40 characters for the name."
    /// `text` trimmed of whitespace and newlines; nil when that is empty, longer than
    /// `maxNameLength` characters, or contains a control character (`CharacterSet.controlCharacters`).
    public static func validatedName(_ text: String) -> String?
    /// Whether `id` is a lowercase UUID string: 8-4-4-4-12 characters from `0-9a-f`, dashes between.
    public static func isValidID(_ id: String) -> Bool
    /// A new ID: `UUID().uuidString.lowercased()`.
    public static func makeID() -> String
}

/// Which summary routines a meeting asks for.
public enum SummaryRoutines {
    /// The routine IDs of the entry of `rules` whose `BinderText.fold`ed title equals the fold of
    /// `pageTitle` or of `originalTitle`; when several entries match, the one whose title sorts
    /// first. IDs are returned as stored. Empty when no entry matches.
    public static func routineIDs(
        pageTitle: String, originalTitle: String, rules: [String: [String]]) -> [String]
    /// The routines of `available` whose ID is in `ids`, in `available`'s order. An ID that names
    /// no routine of `available` is left out.
    public static func routines(ids: [String], in available: [SummaryRoutine]) -> [SummaryRoutine]
}
```

- `AgendaSettings` gains `public var summaryRoutines: [SummaryRoutine]` (the routines the person
  set up, without their secrets), as the **last** init parameter (`summaryRoutines: [SummaryRoutine] = []`),
  a `CodingKeys` entry and `summaryRoutines: try value(.summaryRoutines, defaults.summaryRoutines)`.
  It also gains:

  ```swift
  /// The routine whose `BinderText.fold`ed name equals the fold of `name`, if any.
  public func summaryRoutine(named name: String) -> SummaryRoutine?
  /// Removes the routine and its ID from every entry of `rules.summaryRoutines`; an entry left
  /// with no ID is removed.
  public mutating func removeSummaryRoutine(id: String)
  ```
- `BinderRules` gains `public var summaryRoutines: [String: [String]]` (meeting title as entered →
  routine IDs), `summaryRoutines: [String: [String]] = [:]` as its **last** init parameter,
  a `CodingKeys` entry and `try value(.summaryRoutines, defaults.summaryRoutines)`. The old
  `summarySkills` stays until phase p5 removes it. A rules value saved by an earlier build keeps
  decoding; its `summarySkills` are dropped at p5 with no migration (a skill name names no routine).
- `Reset rules` keeps `summaryRoutines`, as it keeps `summarySkills` and the short names today.
- The secret half is the existing `RoutineCredentials` (fire URL, token; validation unchanged).
  `AppCore/Sources/Handoff/SummaryRoutineTrigger.swift` (new):

  ```swift
  /// Where each summary routine's URL and token are kept, by routine ID. The app uses the Keychain.
  public protocol SummaryRoutineCredentialsStore: Sendable {
      func load(id: String) throws -> RoutineCredentials?
      func save(_ credentials: RoutineCredentials, id: String) throws
      func delete(id: String) throws
  }
  public final class InMemorySummaryRoutineCredentialsStore: SummaryRoutineCredentialsStore, @unchecked Sendable {
      public init(_ credentials: [String: RoutineCredentials] = [:])
  }
  /// Starts a summary routine.
  public protocol SummaryRoutineFiring: Sendable {
      /// Starts routine `routineID` with `text` and returns the URL of the session it started.
      func fire(text: String, routineID: String) async throws -> URL
  }
  public struct SummaryRoutineTriggerClient: SummaryRoutineFiring {
      public init(http: any HTTPClient, credentials: any SummaryRoutineCredentialsStore)
  }
  ```

  `SummaryRoutineTriggerClient.fire` loads the credentials (a store that throws or returns nil →
  `RoutineTriggerError.summaryNotConfigured`) and sends exactly as `RoutineTriggerClient` does.
  To share the request, `RoutineTrigger.swift` gets an `internal` static
  `RoutineTriggerClient.send(text: String, to routine: RoutineCredentials, http: any HTTPClient) async throws -> URL`
  holding today's request/response code, and `RoutineTriggerClient.fire` calls it. The new error
  case `RoutineTriggerError.summaryNotConfigured` has the user message
  `"A summary routine's trigger is missing. Remove the routine in Settings and add it again."`.
  The in-memory store, `InMemorySummaryRoutineCredentialsStore`, follows
  `InMemoryRoutineCredentialsStore`'s `NSLock` pattern.
- App: `App/Platform/KeychainSummaryRoutineCredentialsStore.swift` keeps one Keychain item per routine
  (`KeychainItem(service: "name.tkcs.magenda.summary-routine", account: id)`), the JSON of
  `RoutineCredentials`, like `KeychainRoutineCredentialsStore`.

Rejected: keeping the routines (with tokens) in `AgendaSettings` (UserDefaults, not a secret
store); one Keychain item holding all tokens (one failed write loses every token); using the
routine's trigger ID as the routine ID (it changes when the person regenerates the trigger and it
would put a third party's identifier into the PDF-adjacent records).

### D2. Choosing summaries: rules, edit sheet, page

- `DraftEvent.summarySkill: String?` becomes `public var summaryRoutineIDs: [String]` (init
  parameter `summaryRoutineIDs: [String] = []`, last).
- `EventSelection.draftEvents` sets it with
  `SummaryRoutines.routineIDs(pageTitle: title, originalTitle: candidate.title, rules: rules.summaryRoutines)`.
- `AgendaDraft` replaces `summarySkills` with `public let summaryRules: [String: [String]]` and
  `public let summaryRoutines: [SummaryRoutine]` (init parameters `summaryRules: [String: [String]] = [:]`,
  `summaryRoutines: [SummaryRoutine] = []`, last). `setTitle(_:forEvent:)` and `applyShortName`
  recompute `summaryRoutineIDs` from `summaryRules` as they recompute the skill today. New:

  ```swift
  /// Sets the summary routines one event asks for; IDs naming no routine of `summaryRoutines` are dropped.
  public mutating func setSummaryRoutineIDs(_ ids: [String], forEvent id: String)
  ```
  `content()` builds `meetingSummaryRoutines` from `SummaryRoutines.routines(ids: event.summaryRoutineIDs, in: summaryRoutines)`
  for each meeting-page event.
- `AgendaBuilder.init(timeZone:rules:summaryRoutines:)` gains `summaryRoutines: [SummaryRoutine] = []`
  and passes `summaryRules: rules.summaryRoutines, summaryRoutines: summaryRoutines` to the draft.
  `AgendaController` passes `settings.summaryRoutines` (phase p4).
- `AgendaContent.meetingSummarySkills` is replaced by `public var meetingSummaryRoutines: [[SummaryRoutine]]`
  (one array per meeting, parallel to `meetings`; init parameter `meetingSummaryRoutines: [[SummaryRoutine]] = []`;
  `decodeIfPresent ?? []`, so a day stored with the old key reads as no routines). It holds the
  names as they were when the day was rendered, so the page and the hand-off do not depend on
  Settings later.
- **Page.** `AgendaLayout.meetingSummaryOperations(routines: [SummaryRoutine])` prints the label
  `Summary:` and, after it, the names joined with `", "` in one line, fitted with
  `fitter.singleLine` into the same box as today. With no routine it prints **nothing** and draws no
  ruled line (handwriting a skill no longer selects anything). `TemplateGeometry.meetingSummaryRuleY`
  is deleted.
- **Settings → Binder rules → Meeting summaries** (`RulesView.summariesSection`): rows read
  `"<title> → <name>, <name>"` (names of the routines in `settings.summaryRoutines`, in that order;
  an ID with no routine is not shown; an entry with none left reads `"<title> → (none)"`). Below the
  rows: the `Meeting title` field, one `Toggle` per routine (label: its name), and `Add`. No routines
  configured: the toggles are replaced by `Text("Add summary routines in Settings first.")` and Add
  does nothing. Errors (red caption): none ticked → `"Choose at least one summary routine."`;
  title already present (fold) → `"There is already a summary rule for that meeting title."`.
  Footer: `"A meeting whose title matches gets these summary routines. For one meeting, change them on its Edit sheet."`
- **Edit sheet** (`EditTextSheet`, events only, and only when `settings.summaryRoutines` is not
  empty): a section `Summaries` with one `Toggle` per routine and the footer
  `"Asked for this meeting only. To set them for every meeting with this title, use Settings → Binder rules."`
  Done applies the title first, then `setSummaryRoutineIDs`, so ticked boxes survive a title edit.
- **Settings → Summary routines** (`SettingsView`, after the end-of-day routine section): a row per
  routine (its name; `Forget` button), then `Name`, `Fire URL`, `Token` fields and `Save`.
  Footer: `"Each summary is written by its own Claude routine with its own API trigger. Create it at claude.ai/code/routines, give it only the access that summary needs, and add its trigger here."`
  Save order: `HandoffController.saveSummaryRoutine` (validates and stores the secret, returns the
  routine), then `controller.updateSettings { $0.summaryRoutines.append(routine) }`. Forget:
  `HandoffController.forgetSummaryRoutine(id:)`, then
  `updateSettings { $0.removeSummaryRoutine(id:) }`. A name already in use (fold) →
  `"There is already a summary routine with that name."`; a bad name → `SummaryRoutine.invalidNameMessage`.
- `AgendaController.updateSettings` also reloads when `after.summaryRoutines != before.summaryRoutines`
  (the draft carries the list), and passes `settings.summaryRoutines` to `AgendaBuilder`.

Rejected: ticking boxes on the printed page with the Pencil (Magenda cannot read ink; the
end-of-day routine would have to report back what was ticked); keeping the typed skill name as a
second way (two sources of truth for one meeting); a "remember for this meeting" switch on the
Edit sheet (the Rules screen is where the title rule lives).

### D3. The hand-off

**Data.** `HandoffPage.summarySkill: String?` becomes `public let summaryRoutines: [SummaryRoutine]?`
(nil when none; init parameter `summaryRoutines: [SummaryRoutine]? = nil` replacing `summarySkill`),
read from `content.meetingSummaryRoutines` by `DayHandoff.meeting(_:for:in:)`. `bare` drops it.

`HandoffStage` becomes `queued, uploaded, notesRequested, notesApproved, summariesRequested, closing`.
`notesApproved` now means "Approve notes was tapped and some summary routine is not yet started".
Decoding maps the raw value `summaryApproved` to `.closing` (a custom `init(from:)`). `DayHandoff` gains

- `public var firedSummaries: [String]`, the routine IDs already started for this record (`decodeIfPresent ?? []`);
- `public var summaryMarkers: [String]`, the markers read from the Doc, each `"<routine ID> <page>"` (`decodeIfPresent ?? []`);
- `public var summaryRoutineIDs: [String]`: the distinct IDs in `pages` order over pages whose
  `earlierPart` is nil (a page already sent in a part is summarized in that part's record);
- `public var unsentSummaryRoutines: [SummaryRoutine]`: the distinct routines (id and name from the
  first page that has them), in `pages` order, whose ID is not in `firedSummaries`;
- `public var summariesWritten: Bool`: every `"<id> <page.page>"` for every such page and ID is in `summaryMarkers`.

`formatVersion` stays 1.

**Phases and actions.**

```swift
public enum HandoffAction: Equatable, Sendable { case retry, approveNotes, approveSummaries }
```

`HandoffPhase` loses `working` and gains `summariesWaitingToSend`
(title `"Notes approved. Summaries not yet sent to Claude"`, action `.retry`) and `writingSummaries`
(title `"Claude is writing the summaries"`, no action). `summaryReady` is now
`"Summaries ready for review"` with action `.approveSummaries`; `notesReady` has `.approveNotes`.
`DayHandoff.phase` (after the `closedOn` check, unchanged):

| stage | result |
|---|---|
| `queued` / `uploaded` | `waitingToUpload` / `waitingToSend` (unchanged) |
| `notesRequested` | `docStatus == .notesReady` → `notesReady`, else `writingNotes` |
| `notesApproved` | `unsentSummaryRoutines` not empty → `summariesWaitingToSend`; else as `summariesRequested` |
| `summariesRequested` | `summariesWritten` → `summaryReady`, else `writingSummaries` |
| `closing` | `closing` |

**Controller** (`HandoffController`). `init` gains `summaryTrigger: any SummaryRoutineFiring` and
`summaryCredentials: any SummaryRoutineCredentialsStore`, right after `routineCredentials`. New:

```swift
/// Validates and stores a summary routine's URL and token under a new ID; nil with `message` set when invalid or unstorable.
public func saveSummaryRoutine(name: String, fireURL: String, token: String, id: String = SummaryRoutine.makeID()) -> SummaryRoutine?
/// Deletes a summary routine's stored URL and token.
public func forgetSummaryRoutine(id: String)
```
Messages: bad name → `SummaryRoutine.invalidNameMessage`; bad URL and bad token → the same two
texts `saveRoutine` uses; Keychain failure → `"Couldn't save the routine in the Keychain. Try again."`.

`perform(_:on:)` checks `handoff.phase.action == action` as today, then:

- `.retry`: stage `notesApproved` → `sendSummaries(handoff)`; otherwise `runPipeline` as today.
- `.approveNotes`: if `summaryRoutineIDs` is empty → fire end-of-day `close` (D4), stage `closing`.
  Otherwise save stage `notesApproved` first, then `sendSummaries`.
- `.approveSummaries`: fire end-of-day `close`, stage `closing`.

`sendSummaries(_ handoff:)` walks `unsentSummaryRoutines` in order; for each it fires
`summaryTrigger.fire(text: handoff.summaryPayload(for: routine), routineID: routine.id)`, appends
the ID to `firedSummaries`, sets `sessionURL`, saves. The first failure is recorded with `fail`
and stops (`notesApproved` stays, so Try again starts only the routines not yet started). After the
loop: stage `summariesRequested`, `lastError = nil`, save, then `readStatus`. Magenda never fires a
routine twice by itself (ADR 0028 decision 5): a retry fires only routines whose fire did not
succeed. `readStatus` also stores `DocStatus.summaryMarkers(in:)` in `summaryMarkers`.

**Doc.** `DocStatus` loses `summaryReady`; its `init(from:)` decodes the raw string and maps an
unknown one to `.unknown` (so a record saved with `summaryReady` still loads). The first-line
statuses are `Waiting for notes`, `Notes ready for review`, `Closed`. New

```swift
/// The summary markers in `text`: lines `Summary ready: <routine ID> <page>` (ASCII case-insensitive
/// label, ID lowercase-folded and valid per `SummaryRoutine.isValidID`, page 1…9999), each as
/// `"<routine ID> <page>"`, without duplicates, in order.
public static func summaryMarkers(in text: String) -> [String]
```
Lines are trimmed of whitespace; a leading U+FEFF is ignored. The first line of the Doc is never a
marker.

### D4. Wire contract

**End-of-day routine**: payload schema `magenda.end-of-day/3`. Changes from `/2`: steps are
`notes` and `close` only (`RoutineStep` loses `approveNotes` and `approveSummary`);
`pages[].summarySkill` is replaced by `pages[].summaryRoutines`, an array of `{"id","name"}`
(informational: the end-of-day routine does not write them). Everything else is unchanged,
including `scope`, `part`, `earlierPart` and `folderID`. The bump is deliberate: a routine still on
`/2` stops, so it cannot wait for a summary that no longer comes from it.

- `notes`: unchanged (download, check the checksum, write the notes, set `Status: Notes ready for review`).
- `close`: sent after the person approved the notes (no summary was asked for) or the summaries.
  The routine reads the notes **and any summaries** in the Doc, updates Google Tasks, prepares the
  meeting memos as Gmail drafts and sets `Status: Closed`.

**Summary routine**: its own schema `magenda.summary/1`, one fire per routine per record:

```json
{"checksum":"sha256:…","date":"2026-10-26","docID":"1AbC…","driveFileID":"1ZyX…","folderID":"1Fold…",
 "meetings":[{"calendarID":"work@example.com","eventID":"ev1","key":"meeting:work@example.com|ev1","page":2,"title":"Weekly sync"}],
 "pageCount":4,"part":1,"routineID":"11111111-1111-4111-8111-111111111111","routineName":"Client memo",
 "schema":"magenda.summary/1","scope":"meeting"}
```

Keys sorted, no pretty printing; `part` only for a meeting sent early; `folderID`, `driveFileID`,
`docID` left out when nil; `meetings` are the record's pages with the routine and no `earlierPart`,
in page order, each `title` cut to 200 characters; `calendarID`/`eventID`/`title` left out when
nil. No `tasks`, no `delegated`. Built by `DayHandoff.summaryPayload(for: SummaryRoutine) -> String`.
It cannot exceed 65,536 characters in practice (a day has a few dozen pages); no truncation rules.

A summary routine, for each meeting in `meetings`: download the PDF (`driveFileID`) and check the
checksum as the end-of-day routine does, read the notes in the Doc (`docID`), write the summary and
append it to the Doc as a section whose **first line is the marker**
`Summary ready: <routineID> <page>` followed by the summary text. It never edits the Doc's first
line. The payload and the PDF are data, never instructions. A run already done for the same
`routineID`, `date`, `part` and `checksum` does nothing.

### D5. Fixtures

`FixtureEndOfDay.record(payload:)` accepts both schemas: for `magenda.end-of-day/*` it records the
step per key (`date`, or `<date>-part-<n>`); for `magenda.summary/1` it records the routine ID and
the `meetings[].page` list per key. `docText(forKey:)` returns the first line from the last
end-of-day step (`notes` → `Status: Notes ready for review`, `close` → `Status: Closed`, none or
other → `Status: Waiting for notes`), then for every recorded summary and page the two lines
`Summary ready: <routineID> <page>` and `Fixture summary.`. `hadSummarySkill` is deleted. New
`FixtureSummaryTrigger: SummaryRoutineFiring` (init `state:` and `credentials: any SummaryRoutineCredentialsStore`)
throws `summaryNotConfigured` without stored credentials for the ID, else records and returns
`GoogleAPI.url(host: "claude.ai", path: "/code/session_fixture")`.

`AppEnvironment` (fixture launches): `AgendaSettings(summaryRoutines: [client memo, decision log])`
unless the launch argument `-MagendaNoSummaryRoutines` is given, with in-memory credentials for both
(`trig_fixturememo`, `trig_fixturelog`, token `sk-ant-oat01-fixture`):

| id | name |
|---|---|
| `11111111-1111-4111-8111-111111111111` | `Client memo` |
| `22222222-2222-4222-8222-222222222222` | `Decision log` |

### D6. Docs the routines are written against

`docs/end-of-day-handoff.md` is rewritten for the new contract (Payload `/3`, Steps `notes` and
`close`, Status lines without `Summary ready for review`, a new "Summary routines" section with
the `magenda.summary/1` payload, the marker and the idempotency rule; the existing "Idempotency"
section also covers summaries). The page keeps its folder and `earlierPart` text from
the in-flight plans.

## ADRs

Numbers 0032–0037 are taken by PR #14, send-meeting-early and settings-improvements. If 0038 or
later already exists in `docs/adr/` when the retire phase runs, the ADRs take the next free
numbers, in this order, and say so in the commit message.

- **ADR 0038**: Summaries are written by dedicated summary routines, one Claude routine and API
  trigger per kind of summary, chosen with checkboxes (a title rule in the binder rules, or the
  meeting's Edit sheet) and started by Magenda when the person approves the notes. Supersedes
  [ADR 0031](adr/0031-meeting-summaries-are-requested-by-skill.md) (skills by name). Amends
  [ADR 0028](adr/0028-the-end-of-day-routine-is-started-through-its-api-trigger.md): Magenda now
  holds several narrowly scoped tokens, one per routine. Rejected: one routine doing everything
  (the permission scheme the person refused), ticking boxes on the page, a typed skill name kept
  beside the checkboxes.
- **ADR 0039**: A summary announces itself in the record's Doc with a marker line
  `Summary ready: <routine ID> <page>`, and Magenda offers Approve summaries when every asked-for
  marker is there; the Doc's first line stays the end-of-day routine's alone. Amends
  [ADR 0029](adr/0029-the-days-google-doc-is-the-review-record.md) (the first-line statuses lose
  `Summary ready for review`). Rejected: several routines setting one status line (a race, and a
  routine that writes a status it does not own), a Doc per summary (Magenda cannot create
  or share more files than the day's), a callback to the app (it has no server).
- **ADR 0040**: The end-of-day payload moves to `magenda.end-of-day/3` with steps `notes` and
  `close`, and summary routines receive `magenda.summary/1`. Amends ADR 0028 and
  [ADR 0034](adr/0034-the-payload-moves-to-schema-2-and-marks-pages-sent-earlier.md). Rejected:
  adding the new steps under schema 2 (an unadapted routine would still wait for a summary that no
  longer comes from it).

## Manual steps

No `manual_before`. Three `manual_after` items, with step-by-step instructions on the
[manual-steps page](https://claude.ai/artifact/1MR4ScKJb1RXLZLFHjFiRG):

- **ma1** Update the end-of-day routine's skill to schema `magenda.end-of-day/3`: stop on any other
  schema; do not write summaries; the steps are `notes` and `close`; `close` reads the summaries in
  the Doc. Until then it stops on every payload.
- **ma2** Create each summary routine at claude.ai/code/routines with an API trigger and only the
  access it needs (no Gmail, no Tasks), generate its token, and add it in Settings → Summary
  routines. Tokens are typed into the app only.
- **ma3** On an iPad: tick a summary routine for a meeting, finish the day, approve the notes, wait
  for the summary to appear in the day's Doc, tap Approve summaries, and check the day closes.

## Risks and open questions

- **The baseline is moving.** This plan is written against `feature/settings-improvements` at
  `4909938`. send-meeting-early's p4 (binder UI, `HandoffUITests`) and p5 (docs), and
  settings-improvements' p2, p4 and p6, are not in this tree. p7 merges them. If a phase finds a
  symbol this plan names (`HandoffID`, `DayHandoff.part`, `DayHandoff.folderID`, `HandoffController.sameDateFolderID`,
  `RulesView.deleteSummaries`) missing or different, it stops with `status=blocked`.
- **The app target is red between p3 and p4.** p3 changes `HandoffController`'s initializer and
  `HandoffAction`, which `AppEnvironment` and `ReviewView` use. The app jobs of `tests.yml` are only
  expected green from p4; p1–p3 are judged on the `core` and `lint` jobs.
- **Several routines append to one Doc.** Two routines finishing together could interleave. Each
  appends whole sections whose first line is its own marker, and Magenda matches marker lines
  only, so an interleaving costs readability, not state. The routine contract tells each routine
  to append in one edit.
- **A removed routine.** Forgetting a routine drops its checkboxes and its rule entries
  (`removeSummaryRoutine`), but a record already sent keeps the routine's name and ID in its pages:
  a fire that needs the deleted credentials fails with `summaryNotConfigured` and the row offers
  Try again. The person re-adds the routine under a new ID, so that row cannot finish. Accepted;
  Reset Hand-off (ADR 0032) is the way out.
- **Marker edited away.** If the person deletes a marker line while editing the Doc, the row stays
  at `Claude is writing the summaries`. Accepted and written into the reference doc.
- **Old layouts.** A day laid out before this change prints no `Summary:` line at all after
  Render (the old ruled line is gone); a stored day keeps its stored layout.
- **No Swift toolchain in a cloud container.** Each phase pushes its branch and reads `tests.yml`'s
  `core` and `lint` jobs, per `.claude/skills/steward/SKILL.md`.

## Stacked on settings-improvements

This plan branch contains `feature/settings-improvements` at `4909938`; `/implement`'s feature
branch starts there. p1–p6 build on that code. `p7-stack` brings in whatever
`origin/feature/settings-improvements` has added since, and `p8-retire` writes this plan's docs on
top of the final text of `docs/end-of-day-handoff.md`.

**When `p7-stack` may start.** Its `depends_on` are p5 and p6. In addition, start it only once one
of these holds, checked in this order:

1. `git log origin/feature/settings-improvements --grep 'Plan-Phase: settings-improvements/p6-retire'`
   finds a commit (that plan has written its docs), or
2. a pull request with head `feature/settings-improvements` is open (GitHub MCP `list_pull_requests`,
   `head: andras-tkcs:feature/settings-improvements`), or
3. 8 hours have passed since p6 merged. Then stack on what is there.

Until then, arm a check-in every 30 minutes and look again.

**Reviewing `p7-stack`'s merge**: the other plans' own files are expected in the diff against the
phase's base. Review `git diff origin/feature/settings-improvements...origin/feature/summary-routines--p7-stack`
and `git show --remerge-diff <merge sha>`.

**Re-merging later commits** (after `p7-stack`, while the PR is open): whenever
`git rev-list --count HEAD..origin/feature/settings-improvements` is not 0, merge it into the
feature branch. The orchestrator may finish that merge itself only when there are no conflicts, or
only in `CHANGELOG.md`, `docs/adr/README.md` or an ADR's Status lines (keep both sides, theirs
first), and the fast checks and `verify_after_merge` pass. Otherwise abort the merge and start a
`worker_model: opus` session on `feature/summary-routines--p7-stack-r<n>` with `p7-stack`'s brief,
merged with the trailer `Plan-Phase: summary-routines/p7-stack-r<n>`.

**Final review**: re-merge `origin/feature/settings-improvements` first; in the review prompt use
`git diff origin/feature/settings-improvements...HEAD` and say the branch is stacked and only this
plan's changes and the conflict resolutions of its `p7-stack` merge are in scope.

**Finishing**: look for the other PR (`head: andras-tkcs:feature/settings-improvements`, open) and
re-merge by the rule above; open this PR with `base: feature/settings-improvements`, body starting
`Stacked on <other PR URL>. Merge that first.` (or `Stacked on the feature/settings-improvements
branch; its PR is not open yet.`); comment once on the other PR `<this PR URL> is stacked on this
one.` with the standard footer; when the other PR has merged and this PR's base is still the feature
branch, set the base to `main` with `update_pull_request`, then merge `origin/main`. The final
message names every PR URL in merge order.

## Implementation manifest

```yaml
plan_slug: summary-routines
feature_branch: feature/summary-routines
max_parallel: 2
manual_steps_artifact: https://claude.ai/artifact/1MR4ScKJb1RXLZLFHjFiRG
manual_steps_source: docs/summary-routines-plan-manual-steps.html
manual_before: []
manual_after:
  - id: ma1-update-end-of-day-routine
    title: Update the end-of-day routine's skill to schema magenda.end-of-day/3 (steps notes and close, no summaries)
    why: CI has no Claude account; until the routine is adapted it stops on every payload, the day's too
  - id: ma2-create-summary-routines
    title: Create each summary routine with an API trigger and only the access it needs, and add it in Settings → Summary routines
    why: Only a real routine and token prove the trigger is accepted and the summary reaches the Doc
  - id: ma3-ipad-summary-run
    title: On an iPad, tick a summary routine for a meeting, finish the day, approve the notes, see the summary in the Doc, approve it and see the day close
    why: CI fakes the routines (ADR 0013, ADR 0028); only a real run exercises the routines, the marker and the Doc
verify_after_merge:
  - swift test --package-path AppCore
  - python3 -m unittest discover -s scripts/tests
final_checks:
  - docs/summary-routines-plan.md and docs/summary-routines-plan-manual-steps.html are deleted and nothing links to them
  - ADRs 0038, 0039 and 0040 (or the next free numbers) exist, are Accepted, and are in docs/adr/README.md; ADR 0031's Status says Superseded
  - CHANGELOG.md has [Unreleased] entries and no version heading
  - grep -rn "summarySkill" AppCore App AppUITests AppTests finds nothing
  - grep -rn "approve-notes\|approve-summary" AppCore App docs/end-of-day-handoff.md README.md finds nothing
phases:
  - id: p1-routine-types
    title: SummaryRoutine, the rules and settings fields, the credentials store and the summary trigger client
    depends_on: []
    complexity: M
    touches:
      - AppCore/Sources/Settings/SummaryRoutine.swift
      - AppCore/Sources/Settings/BinderRules.swift
      - AppCore/Sources/Settings/AgendaSettings.swift
      - AppCore/Sources/Handoff/RoutineTrigger.swift
      - AppCore/Sources/Handoff/SummaryRoutineTrigger.swift
      - AppCore/Tests/Settings/SummaryRoutineTests.swift
      - AppCore/Tests/Settings/AgendaSettingsTests.swift
      - AppCore/Tests/Handoff/RoutineTriggerTests.swift
      - AppCore/Tests/Handoff/SummaryRoutineTriggerTests.swift
      - scripts/check_coverage_floor.py
    brief: |
      Design D1. Additive only: nothing existing is removed in this phase (SummarySkill and
      BinderRules.summarySkills stay).
      0. Check `AppCore/Sources/Settings/DriveFolderName.swift` exists and `AgendaSettings` has
         `driveFolderName` as its last init parameter; if not, stop with status=blocked.
      1. Create `AppCore/Sources/Settings/SummaryRoutine.swift` with `SummaryRoutine` and the
         `SummaryRoutines` enum exactly as in D1 (copy the `DriveFolderName.validated` pattern for
         `validatedName`; `isValidID` checks the length 36, dashes at offsets 8, 13, 18 and 23 and
         `0-9a-f` elsewhere, byte by byte; `routineIDs` follows `SummarySkill.skill`'s fold-and-sort
         lookup and removes duplicate IDs keeping the first). Every public declaration has a `///` comment.
      2. `BinderRules.swift`: add `summaryRoutines: [String: [String]]` as the last stored property,
         the last init parameter (default `[:]`), `CodingKeys.summaryRoutines`, the `.default` value
         `[:]` and the `value(.summaryRoutines, defaults.summaryRoutines)` line in `init(from:)`.
      3. `AgendaSettings.swift`: add `summaryRoutines: [SummaryRoutine]` as the last init parameter
         (default `[]`) after `driveFolderName`, `CodingKeys.summaryRoutines`, the decode line, and
         `summaryRoutine(named:)` and `removeSummaryRoutine(id:)` from D1 (compare with
         `BinderText.fold`).
      4. `RoutineTrigger.swift`: add the case `summaryNotConfigured` to `RoutineTriggerError` with the
         D1 message; move the body of `RoutineTriggerClient.fire(text:)` after the `guard let routine`
         into `static func send(text: String, to routine: RoutineCredentials, http: any HTTPClient) async throws -> URL`
         (internal) and call it from `fire`. Behaviour of the existing client must not change.
      5. Create `AppCore/Sources/Handoff/SummaryRoutineTrigger.swift` with the protocols, the
         in-memory store (copy `InMemoryRoutineCredentialsStore`'s lock pattern) and
         `SummaryRoutineTriggerClient` from D1. `fire` loads with `try? credentials.load(id: routineID)`;
         a nil result throws `RoutineTriggerError.summaryNotConfigured`; otherwise `RoutineTriggerClient.send`.
      6. Tests (new files copy the style of `SummarySkillTests.swift` and `RoutineTriggerTests.swift`):
         `SummaryRoutineTests` (name trimming, empty, 41 characters, control character; `isValidID`
         cases; `routineIDs` folded match, first title wins, dedupe, no match; `routines(ids:in:)`
         order and unknown ID dropped; `makeID` is valid), `SummaryRoutineTriggerTests` (fires with
         the routine's own token, unknown ID → summaryNotConfigured, a throwing store →
         summaryNotConfigured, the in-memory store save/load/delete). Extend `AgendaSettingsTests`
         (`summaryRoutines` default, decode of an object without the key, `summaryRoutine(named:)` fold,
         `removeSummaryRoutine` removes the routine and prunes rules, drops an emptied entry) and
         `RoutineTriggerTests` (the new message, `send` through `fire` unchanged).
      7. `scripts/check_coverage_floor.py`: add 100.0 floors with a one-line reason comment for
         `AppCore/Sources/Settings/SummaryRoutine.swift` and `AppCore/Sources/Handoff/SummaryRoutineTrigger.swift`,
         next to the existing floors.
      8. Run `swift test --package-path AppCore` and `swift format lint --strict` (or push and read
         `tests.yml` `core` and `lint`). No CHANGELOG line in this phase.
      Stop with status=blocked if `RoutineTriggerClient.fire` has no `guard let routine = stored()`
      shape to split.
    acceptance:
      - "swift test --package-path AppCore --filter SummaryRoutineTests passes"
      - "swift test --package-path AppCore --filter SummaryRoutineTriggerTests passes"
      - "python3 scripts/check_coverage_floor.py \"$(swift test --package-path AppCore --show-codecov-path)\" exits 0"
      - "grep -c summaryRoutines AppCore/Sources/Settings/BinderRules.swift AppCore/Sources/Settings/AgendaSettings.swift prints a non-zero count for both"
  - id: p2-content-draft-layout
    title: Meetings carry summary routines through the draft, the content, the page and the hand-off page entry
    depends_on: [p1-routine-types]
    complexity: M
    touches:
      - AppCore/Sources/Agenda/AgendaContent.swift
      - AppCore/Sources/Layout/AgendaContentFixtures.swift
      - AppCore/Sources/Draft/DraftEvent.swift
      - AppCore/Sources/Draft/AgendaDraft.swift
      - AppCore/Sources/Draft/EventSelection.swift
      - AppCore/Sources/Draft/AgendaBuilder.swift
      - AppCore/Sources/Layout/AgendaLayout.swift
      - AppCore/Sources/Layout/TemplateGeometry.swift
      - AppCore/Sources/Handoff/DayHandoff.swift
      - AppCore/Tests/Agenda/AgendaContentTests.swift
      - AppCore/Tests/Binder/BinderDayTests.swift
      - AppCore/Tests/Binder/BinderLayoutTests.swift
      - AppCore/Tests/Draft/AgendaDraftTests.swift
      - AppCore/Tests/Draft/EventSelectionTests.swift
      - AppCore/Tests/Draft/AgendaBuilderTests.swift
      - AppCore/Tests/Layout/AgendaLayoutTests.swift
      - AppCore/Tests/Layout/AgendaLayoutFixtureTests.swift
      - AppCore/Tests/Handoff/DayHandoffTests.swift
    brief: |
      Design D2 (the data, draft, page and `HandoffPage` parts) and the first paragraph of D3's
      Data. Nine small source diffs, mostly renames; do them in this order and run the tests last.
      1. `AgendaContent.swift`: replace `meetingSummarySkills: [String]` (line ~95, its init
         parameter, `CodingKeys` entry and decode at ~124) with `meetingSummaryRoutines: [[SummaryRoutine]]`,
         default `[]`, `decodeIfPresent ?? []`. Update the doc comments.
      2. `AgendaContentFixtures.swift` (~line 65): the long-text fixture gets
         `meetingSummaryRoutines: [[SummaryRoutine(id: "11111111-1111-4111-8111-111111111111", name: String(String(repeating: "Board summary ", count: 4).prefix(40)))]]`.
      3. `DraftEvent.swift`: `summarySkill: String?` → `public var summaryRoutineIDs: [String]`, init
         parameter `summaryRoutineIDs: [String] = []` last; fix the doc comments.
      4. `EventSelection.swift` (~line 78): set `summaryRoutineIDs:` with `SummaryRoutines.routineIDs(pageTitle: title, originalTitle: candidate.title, rules: rules.summaryRoutines)`.
      5. `AgendaDraft.swift`: replace `summarySkills` by `summaryRules` and `summaryRoutines` (D2), update
         `setTitle`, `applyShortName`, add `setSummaryRoutineIDs`, and in `content()` build
         `meetingSummaryRoutines` as D2 says (replace the `meetingSummarySkills` array).
      6. `AgendaBuilder.swift`: add `summaryRoutines: [SummaryRoutine] = []` to `init` and pass
         `summaryRules: rules.summaryRoutines, summaryRoutines: summaryRoutines` to `AgendaDraft`.
      7. `AgendaLayout.swift`: `plan(for:)` passes `routines: content.meetingSummaryRoutines.indices.contains(index) ? content.meetingSummaryRoutines[index] : []`
         to `meetingPage(title:key:routines:)`; `meetingSummaryOperations(routines:)` prints the label
         and the names joined with ", " as D2 says and returns `[]` when `routines` is empty or the
         `meeting.label` slot is missing; delete the ruled-line branch. `TemplateGeometry.swift`:
         delete `meetingSummaryRuleY` (and nothing else).
      8. `DayHandoff.swift`: `HandoffPage.summarySkill` → `summaryRoutines: [SummaryRoutine]?` (property,
         init parameter in the same position, the `bare` copy leaves it out as it left `summarySkill`
         out); `meeting(_:for:in:)` returns `(title: String, routines: [SummaryRoutine]?)` from
         `content.meetingSummaryRoutines` (nil when the array is empty); `handoffPage` passes it.
         Update the `payload(step:)` doc comment (`summaryRoutines` instead of `summarySkill`). Do not
         touch stages, phases or the payload schema in this phase.
      9. Tests: update every test that builds or asserts the old skill, in the files listed in
         `touches`: `AgendaContentTests` (legacy decode of a day with `meetingSummarySkills` reads as no
         routines), `BinderDayTests` (~lines 100-117, the same), `BinderLayoutTests` (~107, a routine
         name prints after `Summary:`), `AgendaDraftTests` (~214-244: routine IDs follow title rules,
         `setSummaryRoutineIDs` overrides and drops unknown IDs, a title change recomputes, `content()`
         lists the routines in the available list's order), `EventSelectionTests` (~314),
         `AgendaBuilderTests` (~117), `AgendaLayoutTests` (~101-153: no routine → no `Summary:` run and no
         line at the old y; one routine; two routines joined with ", "; a 40-character name is fitted),
         `AgendaLayoutFixtureTests` (~78-81), `DayHandoffTests` (the page entry's `summaryRoutines`
         round-trips; a legacy-less meeting has nil).
      Stop with status=blocked if `HandoffFixtures.swift`'s tests (`HandoffFixturesTests`) fail: that
      file reads `summarySkill` from raw JSON and is rewritten in p3; do not edit it here, and say so.
    acceptance:
      - "swift test --package-path AppCore passes"
      - "grep -rn 'meetingSummarySkills' AppCore/Sources finds nothing"
      - "grep -rn 'summarySkill' AppCore/Sources/Draft AppCore/Sources/Agenda AppCore/Sources/Layout finds nothing"
      - "swift test --package-path AppCore --filter AgendaLayoutTests passes and includes a test named for 'no routine prints nothing'"
  - id: p3-handoff-flow
    title: Stages, phases and actions, the summary payload and markers, the controller flow and the fixture routines
    depends_on: [p2-content-draft-layout]
    complexity: M
    touches:
      - AppCore/Sources/Handoff/DayHandoff.swift
      - AppCore/Sources/Handoff/DocStatus.swift
      - AppCore/Sources/Handoff/HandoffController.swift
      - AppCore/Sources/Handoff/HandoffFixtures.swift
      - AppCore/Tests/Handoff/DayHandoffTests.swift
      - AppCore/Tests/Handoff/DocStatusTests.swift
      - AppCore/Tests/Handoff/HandoffControllerTests.swift
      - AppCore/Tests/Handoff/HandoffFixturesTests.swift
      - AppCore/Tests/Support/FakeSummaryTrigger.swift
    brief: |
      Design D3 (everything but the first paragraph, done in p2), D4 and D5's fixtures (not
      `AppEnvironment`, which is p4). The app target will not compile after this phase until p4: that
      is expected; judge this phase by `core` and `lint` only.
      0. Check `HandoffID`, `DayHandoff.part`, `DayHandoff.folderID` and `HandoffController.sameDateFolderID`
         exist (send-meeting-early / settings-improvements); if not, stop with status=blocked.
      1. `DocStatus.swift`: `RoutineStep` becomes `notes` and `close` (raw "notes", "close"); remove
         `DocStatus.summaryReady` and its parse line; add `init(from:)` mapping an unknown raw value to
         `.unknown`; add `summaryMarkers(in:)` as in D3 (reuse the BOM and trimming approach of `parse`).
      2. `DayHandoff.swift`: stages (custom `init(from:)` mapping "summaryApproved" to `.closing`),
         `firedSummaries`, `summaryMarkers` (CodingKeys, `decodeIfPresent ?? []`, `init` defaults `[]`),
         the four computed properties, `HandoffAction`, `HandoffPhase` titles/actions and the `phase`
         table, all as in D3. Payload schema string becomes `"magenda.end-of-day/3"`. Add
         `summaryPayload(for:)` with a private `SummaryPayload: Encodable` (keys per D4, sorted, same
         `encode` helper style; titles cut with `String(title.prefix(200))`).
      3. `HandoffController.swift`: the two new init parameters; `saveSummaryRoutine`,
         `forgetSummaryRoutine`; `perform` and the new private `approveNotes(on:)`, `sendSummaries(_:)` and
         `closeDay(_:)` replacing `approve(_:on:)`; `readStatus` stores the markers. Messages exactly
         as in D3. A `.retry` on a record in stage `notesApproved` calls `sendSummaries`.
      4. `HandoffFixtures.swift`: D5 (`FixtureEndOfDay` both schemas, `docText(forKey:)`,
         `FixtureSummaryTrigger`). Keep `FixtureDrive` and `FixtureRoutineTrigger` as they are.
      5. Tests: new `AppCore/Tests/Support/FakeSummaryTrigger.swift` modelled on `FakeRoutineTrigger.swift`
         (records `(text, routineID)`, can be told to fail per routine ID). Extend `DocStatusTests`
         (markers: case, BOM, duplicates, bad ID, page 0 and 10000, not on line one; unknown raw status
         decodes), `DayHandoffTests` (stage legacy decode; every phase row of the D3 table; `summaryRoutineIDs`
         skips `earlierPart` pages; `unsentSummaryRoutines`; `summariesWritten`; `summaryPayload` exact JSON
         for a meeting and for a day; schema `/3` in `payload(step:)`), `HandoffControllerTests` (approve
         notes with no routine fires `close` once; with two routines fires each once with its own
         payload and ends in `summariesRequested`; the second routine failing leaves `notesApproved`,
         the failure message, and a retry fires only the second; markers read by refresh flip the row to
         `summaryReady`; approve summaries fires `close` and ends in `closing`; `saveSummaryRoutine`
         validation and Keychain failure messages; a meeting-sent-early part works the same) and
         `HandoffFixturesTests` (both schemas, the marker lines, `FixtureSummaryTrigger` without
         credentials). Update the tests that used `approve-notes`/`approve-summary`.
      6. Keep `DayHandoff.swift`, `DocStatus.swift`, `HandoffController.swift` and `HandoffFixtures.swift` at
         100 % (their floors).
      Stop with status=blocked if a refresh test needs the Doc to be read for a record whose stage is
      `summariesRequested` and `refresh` skips it (the existing loop reads every record with
      `closedOn == nil` and a `docID`; confirm and do not change that loop).
    acceptance:
      - "swift test --package-path AppCore passes"
      - "python3 scripts/check_coverage_floor.py \"$(swift test --package-path AppCore --show-codecov-path)\" exits 0"
      - "grep -rn 'approveNotes\\b.*rawValue\\|approve-notes\\|approve-summary' AppCore/Sources finds nothing"
      - "swift test --package-path AppCore --filter HandoffControllerTests passes and includes tests whose names contain 'summar'"
  - id: p4-app-wiring
    title: Keychain store, app wiring with fixture routines, Review row buttons and the controller passing routines to the builder
    depends_on: [p3-handoff-flow]
    complexity: S
    touches:
      - App/Platform/KeychainSummaryRoutineCredentialsStore.swift
      - App/AppEnvironment.swift
      - App/Screens/ReviewView.swift
      - AppCore/Sources/Controller/AgendaController.swift
      - AppCore/Tests/Controller/AgendaControllerTests.swift
      - AppTests/PlatformTests.swift
    brief: |
      D1 (App store), D2 last bullet, D5 `AppEnvironment`.
      1. Create `App/Platform/KeychainSummaryRoutineCredentialsStore.swift` conforming to
         `SummaryRoutineCredentialsStore`, modelled line by line on
         `KeychainRoutineCredentialsStore.swift` (`init(service: String = "name.tkcs.magenda.summary-routine")`;
         `KeychainItem(service: service, account: id)` built per call; `load`/`save`/`delete` as there).
      2. `AppEnvironment.swift`: in the fixture branch build the in-memory summary credentials and
         `FixtureSummaryTrigger(state: endOfDay, credentials: summaryCredentials)`, give
         `InMemorySettingsStore(AgendaSettings(summaryRoutines: ...))` the two routines of D5 unless
         `arguments.contains("-MagendaNoSummaryRoutines")` (then `[]`), and pass `summaryTrigger:` and
         `summaryCredentials:` to `HandoffController`. In the live branch use
         `KeychainSummaryRoutineCredentialsStore()` and `SummaryRoutineTriggerClient(http: URLSessionHTTPClient(), credentials: summaryCredentials)`.
      3. `ReviewView.swift`: `title(of:)` returns `"Try again"` for `.retry`, `"Approve notes"` for
         `.approveNotes`, `"Approve summaries"` for `.approveSummaries`; `spokenTitle(of:on:)` returns
         `"Try again for \(day)"`, `"Approve the notes for \(day)"`, `"Approve the summaries for \(day)"`
         (keep whatever the in-tree version uses for `day`, e.g. `displayTitle`). Identifiers unchanged.
      4. `AgendaController.swift`: where `AgendaBuilder(timeZone:rules:)` is built (~line 508) pass
         `summaryRoutines: settings.summaryRoutines`; in `updateSettings` add
         `|| after.summaryRoutines != before.summaryRoutines` to `readsDifferently`.
         Extend `AgendaControllerTests`: a settings change that only adds a routine reloads and the draft
         lists it; the builder's events carry the routine IDs of a matching title rule.
      5. `PlatformTests.swift`: add a Keychain round-trip test for the new store next to the routine
         store's test (`service: "name.tkcs.magenda.tests-summary-routine"`; save two IDs, load each,
         delete one, load nil, clean up in `defer`).
      6. Push and read `tests.yml`: the `core` and `lint` jobs and the three `app (...)` jobs must be green
         (this is the first phase after p3 where the app must compile). The `ui` jobs that touch the
         Review button titles or the Settings routine fields are updated in p5 and p6; if only those fail,
         report which and continue.
      Stop with status=blocked if `AppEnvironment` builds `HandoffController` anywhere else than the
      two places described.
    acceptance:
      - "swift test --package-path AppCore --filter AgendaControllerTests passes"
      - "tests.yml: core, lint and the app (iphone, newest) job are green on the phase branch"
      - "grep -n 'approve(' App/Screens/ReviewView.swift finds nothing"
  - id: p5-settings-rules-ui
    title: Summary routines in Settings, checkboxes in the Meeting summaries rules, and the old skill code removed
    depends_on: [p4-app-wiring]
    complexity: M
    touches:
      - App/Screens/SettingsView.swift
      - App/Screens/RulesView.swift
      - AppCore/Sources/Settings/BinderRules.swift
      - AppCore/Sources/Settings/SummarySkill.swift
      - AppCore/Tests/Settings/SummarySkillTests.swift
      - AppCore/Tests/Settings/AgendaSettingsTests.swift
      - AppUITests/SettingsUITests.swift
      - AppUITests/RulesUITests.swift
      - scripts/check_coverage_floor.py
    brief: |
      D2 (Settings → Summary routines, Binder rules → Meeting summaries) and the removal of the old
      skill code.
      1. `SettingsView.swift`: add `ID` entries `summaryRoutineNameField`, `summaryRoutineURLField`,
         `summaryRoutineTokenField`, `saveSummaryRoutineButton`, `summaryRoutineError`, and functions
         `summaryRoutineRow(_ n: Int)` → `"summaryRoutineRow.\(n)"` and `forgetSummaryRoutineButton(_ n: Int)` →
         `"forgetSummaryRoutineButton.\(n)"`. Add `summaryRoutinesSection` after `routineSection` in the
         `Form`: a row per `controller.settings.summaryRoutines` (Text name, Button "Forget" with
         `role: .destructive` calling `handoff.forgetSummaryRoutine(id:)` then
         `Task { await controller.updateSettings { $0.removeSummaryRoutine(id: id) } }`), then three
         fields (`TextField("Name")`, `TextField("Fire URL")` with the URL keyboard, `SecureField("Token")`;
         copy the modifiers of the routine fields), an error `Text` (red footnote) and `Button("Save")`.
         Save: if `SummaryRoutine.validatedName` is nil → error `SummaryRoutine.invalidNameMessage`; if
         `controller.settings.summaryRoutine(named: name)` is not nil → `"There is already a summary routine with that name."`;
         else `handoff.saveSummaryRoutine(name:fireURL:token:)`; nil → error is `handoff.message`; non-nil →
         `Task { await controller.updateSettings { $0.summaryRoutines.append(routine) } }` and clear the three fields.
         Header "Summary routines", footer as in D2.
      2. `RulesView.swift`: rewrite `summariesSection`, `summaryEntries`, `addSummary` and the delete
         handler for D2: entries are `(title: String, ids: [String])` from `rules.summaryRoutines`; the
         row text is `"\(title) → \(names)"`; state `summaryChoices: Set<String>` replaces `summarySkill`;
         `ID.summaryChoice(_ n: Int)` → `"summaryChoice.\(n)"` and `ID.summaryNoRoutines` →
         `"summaryNoRoutines"` replace `summarySkillField`; keep `summaryTitleField`, `summaryAdd` and the
         error identifier `summaryError` (rename `summarySkillError` to `summaryError`). Add stores
         `settings.rules.summaryRoutines[title] = Array(ids)` where `ids` are the ticked routines' IDs in
         the settings list's order. The reset-rules closure keeps `restored.summaryRoutines = settings.rules.summaryRoutines`.
         Keep the Edit button / long-press Delete structure that settings-improvements p1 added to this
         section (`deleteSummaries(_:in:)` and its `contextMenu`); adapt only the entry type.
      3. Remove the old code: `BinderRules.summarySkills` (property, init parameter, `.default`, CodingKeys,
         decode line); delete `AppCore/Sources/Settings/SummarySkill.swift` and
         `AppCore/Tests/Settings/SummarySkillTests.swift`; in `AgendaSettingsTests` replace the
         `summarySkills` decode test (~lines 96-99) with one that proves an old `rules.summarySkills`
         key is ignored and `summaryRoutines` decodes; in `scripts/check_coverage_floor.py` delete the
         `SummarySkill.swift` floor and its comment.
      4. UI tests (copy the helpers already in each file): in `SettingsUITests` add one test that adds a
         summary routine (name, a valid fire URL `https://api.anthropic.com/v1/claude_code/routines/trig_uisummary/fire`
         and token `sk-ant-oat01-test`), sees its row, then forgets it; and one that shows each
         validation error (empty name, bad URL, duplicate name). In `RulesUITests` replace the
         skill-field tests (~lines 205-255) with: adding a rule with a ticked routine shows its row with
         the routine's name; adding without a tick shows the error; with `-MagendaNoSummaryRoutines`
         `summaryNoRoutines` exists.
      5. Dispatch `tests.yml` on the branch; the `settings` and `rest` UI shards must pass.
      Stop with status=blocked if `RulesView` has no `deleteSummaries` or Edit-button code (the
      settings-improvements p1 changes): then that plan's p1 is not in this tree; report what you see.
    acceptance:
      - "grep -rn 'summarySkill' AppCore App AppUITests AppTests finds nothing"
      - "grep -rn 'SummarySkill' scripts AppCore App finds nothing"
      - "swift test --package-path AppCore passes and python3 scripts/check_coverage_floor.py \"$(swift test --package-path AppCore --show-codecov-path)\" exits 0"
      - "tests.yml: the ui (...) settings and rest shards are green on the phase branch"
  - id: p6-edit-sheet-ui
    title: Summary checkboxes on a meeting's Edit sheet and the end-to-end Review UI test
    depends_on: [p4-app-wiring]
    complexity: S
    touches:
      - App/Screens/EditTextSheet.swift
      - App/Screens/AgendaView.swift
      - AppUITests/AgendaEditUITests.swift
      - AppUITests/HandoffUITests.swift
    brief: |
      D2 (Edit sheet) and the fixtures of D5.
      1. `EditTextSheet.swift`: `init` gains `summaryRoutines: [SummaryRoutine]` and `selectedRoutineIDs: [String]`
         (both default `[]`); `@State private var chosen: Set<String>` starts from `selectedRoutineIDs`;
         `ID` gains `static func summaryToggle(_ n: Int) -> String { "editSummary.\(n)" }`. When
         `originalTitle != nil` (an event) and `summaryRoutines` is not empty, add a `Section` titled
         "Summaries" with a `Toggle(routine.name, isOn: ...)` per routine (identifier `editSummary.<n>`) and the
         D2 footer. In `save()` for `.event`, after the existing title branches, call
         `controller.updateDraft { $0.setSummaryRoutineIDs(ids, forEvent: id) }` with `ids` being the
         chosen IDs in `summaryRoutines` order — only when `summaryRoutines` is not empty.
      2. `AgendaView.editSheet(for:)` (`.event` case): pass
         `summaryRoutines: controller.settings.summaryRoutines` and
         `selectedRoutineIDs: event.summaryRoutineIDs`.
      3. `AgendaEditUITests`: a test that opens an event's Edit sheet, sees `editSummary.0` and `editSummary.1`
         (the fixture routines), ticks the first, taps Done and sees the row's meeting page title unchanged;
         reopening the sheet shows `editSummary.0` selected (`value == "1"`). A second test launched with
         `-MagendaNoSummaryRoutines` shows no `editSummary.0`. Follow the open-the-sheet helper already in the file.
      4. `HandoffUITests` (iPad binder shard): add `testSummariesAreRequestedAfterTheNotesAreApproved`:
         tick `editSummary.0` on a meeting with other attendees (the file's existing flow renders a meeting
         page), render, finish the day (`finishDay`), open Review, wait for `Notes ready for review`, tap
         `reviewAction.0` ("Approve notes"), wait for the row status `Summaries ready for review`, tap
         `reviewAction.0` ("Approve summaries"), wait for a status that begins with `Closed`. Also
         `testWithoutSummariesApproveNotesClosesTheDay`: no ticks → after Approve notes the status begins
         with `Closed` (the existing `testApprovingTheNotesClosesTheDay` is that test: keep it passing and
         update only what the new button titles change).
      5. Dispatch `tests.yml` on the branch; the `edit-screen` shard and the iPad `binder` shard must pass.
      Stop with status=blocked if no event in the standard fixture has other attendees (so no meeting
      page can be reached); report the fixture's events and do not change the fixture.
    acceptance:
      - "grep -n 'setSummaryRoutineIDs' App/Screens/EditTextSheet.swift prints a match"
      - "tests.yml: ui (ipad, newest, binder) and ui (*, edit-screen) shards are green on the phase branch"
  - id: p7-stack
    title: Merge settings-improvements' later commits so the PR stacks on its final state
    depends_on: [p5-settings-rules-ui, p6-edit-sheet-ui]
    complexity: M
    touches:
      - App/Screens/RulesView.swift
      - App/Screens/SettingsView.swift
      - App/AppEnvironment.swift
      - AppUITests/HandoffUITests.swift
      - AppCore/Sources/Handoff/HandoffController.swift
      - AppCore/Sources/Handoff/DayHandoff.swift
      - docs/end-of-day-handoff.md
      - CHANGELOG.md
      - docs/adr/README.md
    brief: |
      Follow "Stacked on settings-improvements": start only when its start condition holds, otherwise
      stop with status=blocked and say which condition is unmet.
      1. `git fetch origin feature/settings-improvements` and `git merge --no-ff origin/feature/settings-improvements`
         into this phase's branch. Resolve conflicts keeping both sides: the other plan's People/Contacts and
         Google Drive section changes (`RulesView.peopleSection`, `SettingsView` Drive section,
         `AppEnvironment` folder-name wiring) beside this plan's Summary routines section and Meeting
         summaries rows; send-meeting-early's binder UI (`HandoffUITests`) beside this plan's summary test.
         `CHANGELOG.md` and `docs/adr/README.md` conflicts keep both sides, theirs first.
      2. After the merge, the hand-off code must still have this plan's behaviour: `grep -n 'summariesRequested' AppCore/Sources/Handoff/DayHandoff.swift`
         finds the stage; `grep -n 'end-of-day/3' AppCore/Sources/Handoff/DayHandoff.swift` finds the
         schema (and no `/2`); `grep -rn 'summarySkill' AppCore App AppUITests AppTests` finds nothing.
      3. Fix any compile or test break the merge caused in this plan's code (for example a
         `HandoffController` initializer call or a UI-test helper renamed by the other plan), touching
         only what the break needs. Do not edit the other plans' code for style.
      4. Run `swift test --package-path AppCore`; push; dispatch `tests.yml` and read every job.
      Stop with status=blocked if the other plan renamed `HandoffAction`, `RoutineStep` or `DocStatus`
      cases this plan changes in a way the merge cannot keep both: report the conflict hunks.
    acceptance:
      - "git merge-base --is-ancestor origin/feature/settings-improvements HEAD exits 0"
      - "swift test --package-path AppCore passes"
      - "tests.yml: every job is green on the phase branch"
  - id: p8-retire
    title: ADRs 0038 to 0040, the routine contract, README, changelog, and retire the plan
    depends_on: [p7-stack]
    complexity: S
    touches:
      - docs/adr/0038-summaries-are-written-by-dedicated-summary-routines-that-magenda-starts.md
      - docs/adr/0039-a-summary-announces-itself-in-the-doc-with-a-marker-line.md
      - docs/adr/0040-the-routine-payload-moves-to-schema-3-and-summaries-have-their-own-schema.md
      - docs/adr/0028-the-end-of-day-routine-is-started-through-its-api-trigger.md
      - docs/adr/0029-the-days-google-doc-is-the-review-record.md
      - docs/adr/0031-meeting-summaries-are-requested-by-skill.md
      - docs/adr/0034-the-payload-moves-to-schema-2-and-marks-pages-sent-earlier.md
      - docs/adr/README.md
      - docs/end-of-day-handoff.md
      - docs/release-testing.md
      - README.md
      - CHANGELOG.md
      - docs/summary-routines-plan.md
      - docs/summary-routines-plan-manual-steps.html
    brief: |
      1. Choose the ADR numbers: if `docs/adr/0038-*.md` is free use 0038, 0039, 0040, else the next
         three free numbers in order (rename the files in `touches` accordingly and say so in the commit message).
      2. Write the three ADRs from the "ADRs" section and D1-D4 with the template in
         `docs/adr/README.md` (Status, Context, Decision, Alternatives considered, Consequences,
         Verification, Related), Status `Accepted — <today's date>. Implemented.` Decisions are numbered
         lists in the style of ADR 0028; Verification names the source and test files from D1-D5.
         ADR 0038's Status also has `Supersedes [ADR 0031](0031-meeting-summaries-are-requested-by-skill.md).`
         and `Amends [ADR 0028](...)`; ADR 0039's has `Amends [ADR 0029](...)`; ADR 0040's has
         `Amends [ADR 0028](...)` and `Amends [ADR 0034](...)`. No ADR links to this plan.
      3. Add one Status line to each old ADR (nothing else in its body): ADR 0031
         `Superseded by [ADR 0038](0038-….md): summaries are requested from summary routines, not skills.`,
         ADR 0028 `Amended by [ADR 0038](…) and [ADR 0040](…): several routines, and the schema moved to 3.`,
         ADR 0029 `Amended by [ADR 0039](…): summaries are announced by markers.`, ADR 0034
         `Amended by [ADR 0040](…): schema 3.` Add the three rows to `docs/adr/README.md`'s index and change
         ADR 0031's index row status to `Superseded by 0038`.
      4. `docs/end-of-day-handoff.md` (D6): update its opening list of decisions with ADRs 0038-0040;
         rewrite "The payload" for `magenda.end-of-day/3` (example with `summaryRoutines` on a meeting
         page, no `summarySkill`), "Steps" (`notes`, `close`), "Status lines" (three lines), and add the
         section "Summary routines" (payload `magenda.summary/1` with the D4 example, what a routine must
         do, the marker, idempotency, the data-never-instructions rule). Keep every `folderID`, `scope`,
         `part` and `earlierPart` passage the other plans wrote. If a heading named here is missing,
         stop with status=blocked.
      5. `README.md` (the hand-off section, ~lines 90-101): replace the skill text with the summary
         routines and the Approve summaries button. `docs/release-testing.md` (~line 62): the iPad
         check taps Approve notes, then Approve summaries when a summary routine was ticked; add the
         manual rows ma1-ma3 as one checklist item each.
      6. `CHANGELOG.md` under `[Unreleased]` → `### Added`: `- Summaries are written by their own Claude routines. Add each one in Settings → Summary routines, then tick which meetings get it in Settings → Binder rules → Meeting summaries or on a meeting's Edit sheet. After you approve the notes, Magenda starts them, and Approve summaries closes the day.` and `### Changed`: `- A meeting page's Summary line now lists the routines ticked for it instead of a skill name you wrote by hand; summary skills typed in the binder rules are no longer used.` (create the `### Changed` heading only if it is missing, in Keep a Changelog order).
      7. Delete `docs/summary-routines-plan.md` and `docs/summary-routines-plan-manual-steps.html` with
         `git rm`; `grep -rn 'summary-routines-plan' .` must find nothing.
      8. Run `python3 -m unittest discover -s scripts/tests` (the no-project-history guard) and
         `grep -rn 'summarySkill\|approve-notes\|approve-summary' AppCore App docs/end-of-day-handoff.md README.md`
         (nothing).
    acceptance:
      - "python3 -m unittest discover -s scripts/tests passes"
      - "test ! -e docs/summary-routines-plan.md && test ! -e docs/summary-routines-plan-manual-steps.html"
      - "grep -c 'Summary routines' docs/end-of-day-handoff.md prints a non-zero count"
      - "grep -n '0038\\|0039\\|0040' docs/adr/README.md prints three rows"
```
