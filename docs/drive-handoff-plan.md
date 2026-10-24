# Plan: end-of-day hand-off to Google Drive and the Claude routine

## Goal

When the person finishes a day in the iPad binder, Magenda uploads one PDF of the day's pages
(printed content kept as text, handwriting composited on top) to a `Magenda` folder in their Google
Drive. It creates that day's Google Doc next to it and starts the person's end-of-day Claude
routine through the routine's API trigger. This replaces today's manual Share PDF → Drive → start
routine steps. A Review list in Magenda shows each finished day's state, opens the day's Doc, and
has the one approve button the Doc's status calls for. Each button starts the routine's next step.
Once the Doc says the day is closed, Magenda deletes that day's handwriting and PDF five days
later. Meetings that need a summary are named by a title → summary-skill map in the rules, or by
writing the skill on a printed "Summary:" line on the meeting page.

This is stage 2 of the design doc "Adaptive Daily Binder: Design"
(https://claude.ai/artifact/1CNKe98pEoZyTJPxPmNvMk, sections "Stage 2 design" and "Review loop").
Stage 1 (the binder with ink) is on `main`.

## Current state

Checked on `main` at `df7b1fd`.

- **Sign-in** asks for exactly `calendar.readonly` and `tasks.readonly`
  (`AppCore/Sources/Google/GoogleOAuth.swift:41-45`). `GoogleOAuth.tokens` throws
  `.missingScopes` when a token response's `scope` lacks one of them
  (`GoogleOAuth.swift:213-230`), on sign-in and on refresh alike. `OAuthTokens`
  (`GoogleOAuth.swift:92-107`) does not record the granted scopes. ADR 0013 says "The app never
  writes to Google"; ADR 0014 item 1 says "No Drive upload".
- **HTTP** (`AppCore/Sources/Google/HTTP.swift`): `HTTPMethod` has only `get` and `post`;
  `HTTPResponse` has `status` and `body`, no headers. `URLSessionHTTPClient`
  (`App/Platform/URLSessionHTTPClient.swift`) drops the response headers.
- **`GoogleSession.send`** (`GoogleSession.swift:179-206`) maps 2xx to success, 403 to
  `.forbidden`, 429 to `.rateLimited` and every other status to `.unexpectedResponse`. A refresh
  that fails with `.signedOut` deletes the stored tokens (`GoogleSession.swift:249-267`).
- **`AgendaController.load`** (`AgendaController.swift:210`) sends a `.signedOut` failure to
  the sign-in screen; every other failure, `.missingScopes` included, goes to `.failed(message)`,
  where the only action is "Try again". So after a scope change, an existing user would be stuck on
  a retry loop.
- **Export**: `AgendaController.exportBinder()` (`AgendaController.swift:368`) renders the
  open binder's plan with each page's ink through `AgendaRendering` into
  `tmp/Agendas/<date>.pdf` (`App/Rendering/PDFAgendaRenderer.swift`). Generated text stays text,
  and ink is a 3× image per page. `BinderView` (`App/Screens/BinderView.swift:126-133`) offers it as Share PDF.
- **Binder storage**: `BinderStore` (`AppCore/Sources/Binder/BinderStore.swift`) has `day`,
  `saveDay`, `ink`, `saveInk`, with no way to delete a day. ADR 0021: "Storage grows with every
  started day; nothing deletes a stored day."
- **Content IDs**: `AgendaDraft.content()` (`AgendaDraft.swift:96-123`) keeps event IDs in
  `AgendaContent.meetingIDs`, but `TodoItem` and `DelegatedItem` (`AgendaContent.swift:13-67`)
  carry no task ID. `DraftTask.id` and `DraftDelegated.id` are the Google task IDs
  (`DraftTask.swift:22,57`). `DraftEvent.id` is `<calendarID>|<eventID>` (`DraftEvent.swift:21`).
  `AgendaContent` is stored inside every `BinderDay` (`day.json`), so a new field has to decode
  from files written without it.
- **Meeting page**: the chrome page `meeting_unit` has only the label "Meeting title:" and the
  title slot at y 81.75–106.95 pt (`AppCore/Sources/Resources/slots.json`). Measured on
  `chrome.pdf` page 3, the header band ends at y 76 pt and the first ruled line is at y 147 pt, so
  y 108–146 is empty. `AgendaLayout.meetingPage` (`AgendaLayout.swift:169-174`) emits label runs,
  then title runs, then the header. `continuedOperations(of:in:)` (`AgendaLayout.swift:152`)
  relies on that order: labels first, then the title.
- **Rules**: `BinderRules` (`AppCore/Sources/Settings/BinderRules.swift`) decodes each field with a
  fallback to its default, so a new field is backward compatible. `RulesView`
  (`App/Screens/RulesView.swift`) edits lists, short names and person aliases. Its people section
  (`RulesView.swift:180-215`, IDs `peopleName`, `peopleEmail`, `peopleAdd`) is the two-field add
  pattern to copy.
- **Coverage**: `scripts/check_coverage_floor.py` sets `OVERALL_FLOOR = 100.0` over
  `AppCore/Sources/`, so every new AppCore line needs a test that runs it.
- **CI**: the iPad-only UI test classes `BinderUITests` and `StartOverUITests` run in the
  `binder` shard and are skipped in every `rest` shard (`.github/workflows/tests.yml:105-114`).
- **The routine fire API**, checked against the live documentation on 2026-10-24
  (https://platform.claude.com/docs/en/api/claude-code/routines-fire):
  - The call is `POST https://api.anthropic.com/v1/claude_code/routines/{trig_…}/fire`.
  - Headers: `Authorization: Bearer sk-ant-oat01-…` (one token per routine, which can only fire
    that routine) and `anthropic-version` (any version from `2023-06-01` on). The
    `anthropic-beta: experimental-cc-routine-2026-04-01` header is optional.
  - The body is `{"text": "…"}`, at most 65,536 characters. The routine receives the text as a
    literal string inside a `<routine-fire-payload>` block marked as untrusted data, and acts on it
    only if its saved prompt says so.
  - A 200 answers `{"type":"routine_fire","claude_code_session_id","claude_code_session_url"}`.
  - Errors: 400 (bad version, text too long, or routine paused), 401 (bad token), 403 (account has
    no access), 404 (no such routine), 429 with `Retry-After` (30 fires per routine per hour, 100
    per account), 500 and 503.
  - **There is no idempotency key**: every 200 starts a new session.

## Design

### D1. Google scopes and re-consent

- `GoogleOAuthConfiguration.scopes` becomes, in this order: `calendar.readonly`,
  `tasks.readonly`, `https://www.googleapis.com/auth/drive.file`. `drive.file` reaches only files
  the app created. The full Tasks write scope is **not** added in this stage (the user's
  decision). Stage 3 will need a second re-consent.
- `OAuthTokens` gains `public let scopes: [String]?` (optional, so tokens stored by older builds
  still decode: it is `nil` for them). The initializer gains a trailing `scopes: [String]? = nil`.
- `GoogleOAuth.tokens(from:previousRefreshToken:requireScopes:now:)` gains a parameter
  `previousScopes: [String]?`, placed after `previousRefreshToken`. The returned tokens' `scopes`
  are the response's `scope` split on spaces, else `previousScopes`. When that result is `nil` or
  lacks any of `GoogleOAuthConfiguration.scopes`, `tokens` throws `.missingScopes`. This replaces
  the existing `scope` check. `requireScopes` keeps its meaning: with it set, a missing `scope`
  throws even when `previousScopes` is given. So stored tokens either carry every required scope
  or are never stored, and the forced refresh below cannot repeat on every request.
- `GoogleSession.send` refreshes before sending when the access token expires within a minute
  **or** the stored `scopes` are `nil` or lack one of `GoogleOAuthConfiguration.scopes`. A refresh
  for tokens issued before this change then returns the old grant's `scope`, which throws
  `.missingScopes`. `GoogleSession.refresh` now deletes the stored tokens on `.missingScopes` too,
  as it already does on `.signedOut`, and rethrows it. A refresh passes `tokens.scopes` as
  `previousScopes`.
- `GoogleSession.send` maps a 404 to a new `GoogleAPIError.notFound`.
- `AgendaController.load` treats `.missingScopes` like `.signedOut`: `status = .signedOut`,
  `message = failure.userMessage`. That is the sign-in screen, with the message above the button
  (`SignInView.swift:42`).
- New and changed `GoogleAPIError.userMessage` texts:
  - `.missingScopes`: `Magenda needs your calendars, your tasks and the files it creates in Google Drive. Sign in again and allow all three.`
  - `.forbidden`: `Google refused the request. Check that the Calendar, Tasks and Drive APIs are enabled for this app.`
  - `.notFound` (new): `Google couldn't find that file. It may have been deleted.`
- `SetupView`'s intro text (`SetupView.swift:39`) becomes: `Magenda reads your calendar and tasks and saves finished days to your Google Drive through your own Google Cloud OAuth client. Create an iOS client for the bundle ID name.tkcs.magenda, then enter it here.`

### D2. HTTP

- `HTTPMethod` gains `put = "PUT"` and `patch = "PATCH"`.
- `HTTPResponse` gains `public var headers: [String: String]`. The initializer becomes
  `init(status: Int, body: Data, headers: [String: String] = [:])`. It also gains
  `public func header(_ name: String) -> String?`, which looks up a header case-insensitively.
- `URLSessionHTTPClient` fills `headers` from `HTTPURLResponse.allHeaderFields`, converting keys
  and values to `String` and skipping the rest.

### D3. Drive client (`AppCore/Sources/Google/GoogleDriveClient.swift`)

```swift
/// What the end-of-day hand-off needs from Google Drive.
public protocol DriveFiling: Sendable {
    func folderID(named name: String) async throws -> String
    func uploadPDF(_ data: Data, name: String, folderID: String, replacing fileID: String?) async throws -> String
    func createDoc(name: String, folderID: String, text: String) async throws -> String
    func exportText(ofDoc docID: String) async throws -> String
}
public struct GoogleDriveClient: DriveFiling { public init(sender: any AuthorizedHTTPSending) }
```

Every request goes through `sender`, so every error is a `GoogleAPIError`. A 2xx body that does
not decode, or a `Location` that is not `https://www.googleapis.com/…`, is `.unexpectedResponse`.
Request bodies are JSON from `JSONEncoder` with `.sortedKeys`. URLs are built with
`GoogleAPI.url(host:path:)`, `appending(path:)` and `GoogleAPI.withQuery`, never by string
concatenation of IDs.

| Call | Requests |
|---|---|
| `folderID(named:)` | 1. `GET https://www.googleapis.com/drive/v3/files` with query `q` = `name = '<name>' and mimeType = 'application/vnd.google-apps.folder' and trashed = false` (a `'` or `\` in the name is escaped with `\`), `spaces=drive`, `fields=files(id)`, `pageSize=10`. The first `files[].id` wins. 2. If there is none: `POST https://www.googleapis.com/drive/v3/files?fields=id` with body `{"mimeType":"application/vnd.google-apps.folder","name":"<name>"}` and `Content-Type: application/json; charset=UTF-8`. Returns `id`. |
| `uploadPDF` with `replacing == nil` | 1. `POST https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id`. Headers: `Content-Type: application/json; charset=UTF-8`, `X-Upload-Content-Type: application/pdf`, `X-Upload-Content-Length: <bytes>`. Body: `{"mimeType":"application/pdf","name":"<name>","parents":["<folderID>"]}`. The response's `Location` header is the upload URL. 2. `PUT <upload URL>` with the PDF bytes, `Content-Type: application/pdf`, timeout 300 s. Returns `id` from the JSON answer. |
| `uploadPDF` with `replacing: id` | 1. `PATCH https://www.googleapis.com/upload/drive/v3/files/<id>?uploadType=resumable&fields=id`, with the same headers and body `{}`. 2. The same `PUT`. If step 1 throws `GoogleAPIError.notFound`, the call does the `replacing == nil` path instead. |
| `createDoc` | `POST https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id`, `Content-Type: multipart/related; boundary=magenda-part-boundary`. The body is exactly `--magenda-part-boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n<metadata>\r\n--magenda-part-boundary\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n<text>\r\n--magenda-part-boundary--\r\n`, with metadata `{"mimeType":"application/vnd.google-apps.document","name":"<name>","parents":["<folderID>"]}`. Drive converts the text into a Google Doc. Returns `id`. |
| `exportText(ofDoc:)` | `GET https://www.googleapis.com/drive/v3/files/<docID>/export?mimeType=text%2Fplain`. Returns the body as UTF-8 with a leading U+FEFF removed. A body that is not UTF-8 is `.unexpectedResponse`. |

The upload is a single `PUT` of the whole file, not chunked. An interrupted upload starts over
with a new upload URL. A day's PDF is a few MB, so chunked resume would add a 308 path through
`GoogleSession` for little benefit.

Names: the folder is `Magenda`. The PDF is `Magenda <YYYY-MM-DD>.pdf`. The Doc is
`Magenda <YYYY-MM-DD> notes`.

### D4. The routine trigger (`AppCore/Sources/Handoff/RoutineTrigger.swift`)

```swift
/// The end-of-day routine's API trigger, as entered in Settings.
public struct RoutineCredentials: Codable, Equatable, Sendable {
    public let triggerID: String      // "trig_" + 1…64 ASCII letters or digits
    public let token: String          // "sk-ant-oat01-" + 1…500 chars of [A-Za-z0-9_-]
    public init?(fireURL: String, token: String)   // both trimmed of whitespace
    public var fireURL: URL           // https://api.anthropic.com/v1/claude_code/routines/<triggerID>/fire
}
public protocol RoutineCredentialsStore: Sendable { load() throws -> RoutineCredentials?; save(_:) throws; delete() throws }
public final class InMemoryRoutineCredentialsStore: RoutineCredentialsStore, @unchecked Sendable  // NSLock, like InMemoryClientCredentialsStore
public protocol RoutineFiring: Sendable {
    func isConfigured() -> Bool
    func fire(text: String) async throws -> URL   // the session URL
}
public struct RoutineTriggerClient: RoutineFiring { public init(http: any HTTPClient, credentials: any RoutineCredentialsStore) }
public enum RoutineTriggerError: Error, Equatable, Sendable { … ; public var userMessage: String }
```

- `RoutineCredentials.init?(fireURL:token:)` accepts the URL only when `URLComponents` gives
  scheme `https`, host `api.anthropic.com`, no port, query, fragment or user, and a path of
  exactly `/v1/claude_code/routines/<triggerID>/fire`. Anything else returns `nil`.
- `fire` sends `POST <fireURL>` with headers `Authorization: Bearer <token>`,
  `anthropic-version: 2023-06-01` and `Content-Type: application/json`, body
  `{"text":"<text>"}` (JSONEncoder) and timeout 30 s. It sends no beta header: the API
  reference says it is optional.
- A 200 whose JSON has `type == "routine_fire"` and a `claude_code_session_url` with scheme
  `https` and host `claude.ai` returns that URL. Anything else in a 200 is `.unexpectedResponse`.
- Errors and their exact `userMessage`:

| Case | When | `userMessage` |
|---|---|---|
| `.notConfigured` | no credentials stored | `Add the end-of-day routine in Settings to send this day for processing.` |
| `.rejectedToken` | 401 | `Claude rejected the routine token. Generate a new token at claude.ai/code/routines and enter it in Settings.` |
| `.notFound` | 404 | `That routine no longer exists. Check the fire URL in Settings.` |
| `.notStarted` | 400 | `Claude didn't start the routine. Check that it isn't paused at claude.ai/code/routines.` |
| `.forbidden` | 403 | `Your Claude account can't start routines. Check your plan and your organization's settings.` |
| `.rateLimited(retryAfter: TimeInterval?)` | 429; `Retry-After` parsed as whole seconds, else `nil` | `Claude is limiting routine runs right now. Try again later.` |
| `.unavailable` | 500–599 | `Claude is unavailable right now. Try again in a few minutes.` |
| `.network` | the `HTTPClient` threw | `Couldn't reach Claude. Check your connection and try again.` |
| `.unexpectedResponse` | any other status, or a 200 that does not decode | `Claude sent an unexpected response. Try again later.` |

The token is never logged and never appears in an error or message.

### D5. Content IDs and summary skills (AppCore)

- `TodoItem` gains `public var taskID: String?`, and `DelegatedItem` gains
  `public var taskID: String?`. Each is a trailing initializer parameter defaulting to `nil`.
  Synthesized `Codable` decodes a missing key as `nil`.
- `AgendaContent` gains `public var meetingSummarySkills: [String]`, parallel to `meetings`, where
  `""` means none. It is a trailing initializer parameter defaulting to `[]`. A hand-written
  `init(from:)` decodes it with `decodeIfPresent(...) ?? []` and every other field as today, so a
  stored `day.json` without it still decodes. `BinderDay.formatVersion` stays 1.
- `BinderRules` gains `public var summarySkills: [String: String]`, which maps a meeting title as
  entered to a skill name. It is a trailing initializer parameter `summarySkills: [String: String] = [:]`,
  is `[:]` in `.default`,
  and is decoded through the existing `value(_:_:)` fallback under CodingKey `summarySkills`.
- New `AppCore/Sources/Settings/SummarySkill.swift`:

```swift
/// Which summary skill a meeting asks for.
public enum SummarySkill {
    /// Whether `name` can be a skill name: 1…64 characters, the first an ASCII letter or digit,
    /// the rest ASCII letters, digits, "-", "_", ":" or ".".
    public static func isValidName(_ name: String) -> Bool
    /// The skill whose entry's `BinderText.fold`ed title equals the fold of `pageTitle` or of
    /// `originalTitle`; when several match, the one whose title sorts first. `nil` when none does
    /// or the matching skill is not a valid name.
    public static func skill(pageTitle: String, originalTitle: String, skills: [String: String]) -> String?
}
```

- `DraftEvent` gains `public var summarySkill: String?`, a trailing initializer parameter
  defaulting to `nil`. `EventSelection.draftEvents` sets it with
  `SummarySkill.skill(pageTitle: title, originalTitle: candidate.title, skills: rules.summarySkills)`.
  `AgendaDraft` gains `public let summarySkills: [String: String]`, which `AgendaBuilder` sets from
  `rules.summarySkills` through a trailing initializer parameter
  `summarySkills: [String: String] = [:]`. `AgendaDraft.applyShortName` and
  `AgendaDraft.setTitle(_:forEvent:)` recompute `summarySkill` for every event they change, with
  `SummarySkill.skill(pageTitle:originalTitle:skills: summarySkills)`.
- `AgendaDraft.content()` fills `TodoItem.taskID` from `DraftTask.id`, `DelegatedItem.taskID` from
  `DraftDelegated.id`, and `meetingSummarySkills` with `event.summarySkill ?? ""` for each meeting
  page, in the order of `meetings`.

### D6. The "Summary:" line on meeting pages

Every meeting page (and every added copy of one, since an added page copies its source's
operations) prints one line below the title. The label `Summary:` is drawn with the role, font
pack and weight of the `meeting.label` slot at 12 pt nominal.
- When `meetingSummarySkills[i]` is non-empty, the skill name follows the label in the same font.
  Its box is `PlanRect(x0: label.x + label.width + meetingSummaryGap, y0: 114.0, x1:
  meetingTitleRight, y1: 134.0)`, used as both box and container, and its text is
  `fitter.singleLine(skill, font:, maxWidth: box.x1 - box.x0)`. The label itself is placed in
  `meetingSummaryBox`.
- When it is empty, a ruled line runs from 6 pt after the label's right end to
  `TemplateGeometry.meetingTitleRight` at y 136. It has `TemplateGeometry.todoLineColor` and width
  `0.5`. The person writes a skill name there by hand when a one-off meeting needs a summary.

New `TemplateGeometry` constants: `meetingSummaryBox = PlanRect(x0: 56.8, y0: 114.0, x1: 566.95,
y1: 134.0)`, `meetingSummaryRuleY = 136.0`, `meetingSummaryGap = 6.0`,
`meetingSummaryPoints = 12.0`. The runs are placed with `placer.place(..., in: meetingSummaryBox,
container: meetingSummaryBox, alignment: .left)`. Operation order on a meeting page becomes:
label runs, title runs, summary operations, header. `continuedOperations(of:in:)`'s slicing still holds
because the summary operations come after the title runs. The blank meeting page of a day without
meetings prints the label and the ruled line.

`BinderLayout` gets this through `AgendaLayout` without change. Retained pages keep the content
they were laid out from, so they print whatever skill they had.

### D7. Rules editor: "Meeting summaries"

`RulesView` gains a section titled `Meeting summaries`, placed after the short-names section,
with:
- the footer `A meeting whose title matches gets this summary skill printed on its page. For a one-off meeting, write the skill on the page's Summary line.`;
- one row per entry, sorted by title, showing `<title> → <skill>`, with identifiers
  `ID.row("summaries", i)`; swipe to delete;
- an add row with a `TextField` `Meeting title` (`summaryTitleField`), a `TextField`
  `Summary skill` (`summarySkillField`, no autocapitalization or autocorrection) and a button
  `Add` (`summaryAdd`). Add normalizes the title with `TextFitter.normalized`, rejects an empty
  title, and rejects a skill for which `SummarySkill.isValidName` is false. A rejected skill shows
  `A skill name uses letters, digits, -, _, : and . only.` in a `Text` with identifier
  `summarySkillError`. A title whose `BinderText.fold` equals an existing entry's fold is rejected
  with `There is already a summary skill for that meeting title.` in the same `Text`.

"Reset rules" keeps `summarySkills`, as it keeps `shortNames` (`RulesView.swift:78`). Edits go
through `controller.updateSettings`, which reloads, so the draft picks the skills up.

### D8. Hand-off model (`AppCore/Sources/Handoff/`)

```swift
/// A step the end-of-day routine runs.
public enum RoutineStep: String, Codable, Sendable { case notes, approveNotes = "approve-notes", approveSummary = "approve-summary" }

/// The first line of the day's Doc, as the routine sets it.
public enum DocStatus: String, Codable, Sendable {
    case waitingForNotes, notesReady, summaryReady, closed, unknown
    /// Reads the first non-empty line of `text` (a leading U+FEFF and surrounding whitespace
    /// ignored). It must start with `Status:` (ASCII case-insensitive). The rest, trimmed, compared
    /// case-insensitively: `Waiting for notes`, `Notes ready for review`, `Summary ready for
    /// review`, `Closed`. Anything else is `.unknown`.
    public static func parse(_ text: String) -> DocStatus
    /// The line Magenda writes when it creates the Doc: "Status: Waiting for notes\n".
    public static let initialDocText: String
}

/// How far a finished day has come.
public enum HandoffStage: String, Codable, Sendable { case queued, uploaded, notesRequested, notesApproved, summaryApproved }

/// One page of the PDF, for the routine.
public struct HandoffPage: Equatable, Codable, Sendable {
    public let page: Int            // 1-based, the PDF's page order
    public let key: String          // PageKey.storageString
    public let calendarID: String?  // meeting pages: before the first "|" of the event key
    public let eventID: String?     // meeting pages: after it
    public let title: String?       // meeting pages: the meeting-page title
    public let summarySkill: String? // meeting pages with a mapped skill
    public let source: String?      // added pages: the storageString of the page they copy
}
public struct HandoffTask: Equatable, Codable, Sendable { public let taskID: String?; public let text: String; public let due: String }
public struct HandoffDelegated: Equatable, Codable, Sendable { public let taskID: String?; public let text: String; public let owner: String }

/// A finished day and how far its hand-off has come.
public struct DayHandoff: Equatable, Codable, Sendable {
    public static let formatVersion = 1      // decoding any other version throws, as BinderDay does
    public let version: Int
    public let date: CalendarDay
    public var checksum: String              // "sha256:" + 64 lowercase hex digits of the PDF
    public var pages: [HandoffPage]
    public var tasks: [HandoffTask]          // the printed to-do rows, in order
    public var delegated: [HandoffDelegated] // the delegated rows, in page order
    public var driveFileID: String?
    public var docID: String?
    public var stage: HandoffStage
    public var docStatus: DocStatus          // last read; .waitingForNotes until read
    public var closedOn: CalendarDay?        // the day Magenda first read `.closed`
    public var purged: Bool                  // the binder day and the PDF were deleted; this record stays
    public var lastError: String?
    public var sessionURL: URL?              // the last routine run started
    public var phase: HandoffPhase { get }
    /// What the routine receives for `step`.
    public func payload(step: RoutineStep) -> String
}
```

How `pages`, `tasks` and `delegated` are built, as
`DayHandoff.init(date:checksum:day:plan:)` from the `BinderDay` and its plan:
- one `HandoffPage` per `plan.pages` element, in order;
- for `.meeting(id)`:
  - `calendarID` and `eventID` are set only when `id` contains `|` (split at the first one);
    otherwise both are nil.
  - `title` and `summarySkill` (nil when empty) come from the content the page was laid out from
    (`day.content`, else the `RetainedPage` with that key). They are taken at position `i` where
    `meetingIDs[i] == id`, or where `id == "#\(i)"` (a meeting without an event ID).
  - For `.meeting("")` (the blank page of a day without meetings) both are nil;
- for `.extra(id)`, `source` is the `ExtraPage.source.storageString`;
- `tasks` are `day.content.todoItems` minus `plan.omittedTodoItems` (compared by `text` and
  `due`), and `delegated` is `day.content.delegated.sortedForPage()`.

`HandoffPhase` (what the Review list shows) and its exact `title`:

| Phase | When (checked in this order) | `title` | Action |
|---|---|---|---|
| `.closed(deleteOn: CalendarDay, purged: Bool)` | `closedOn != nil`; `deleteOn = closedOn + 5 days` | `Closed. Handwriting is deleted on <deleteOn ISO date>.`, or `Closed. Handwriting deleted.` when `purged` | none |
| `.waitingToUpload` | stage `queued` | `Waiting to upload` | `.retry` |
| `.waitingToSend` | stage `uploaded` | `Uploaded, not yet sent to Claude` | `.retry` |
| `.notesReady` | stage `notesRequested` and docStatus `notesReady` | `Notes ready for review` | `.approve(.approveNotes)` |
| `.writingNotes` | stage `notesRequested` | `Claude is writing the notes` | none |
| `.summaryReady` | stage `notesApproved` and docStatus `summaryReady` | `Summary ready for review` | `.approve(.approveSummary)` |
| `.working` | stage `notesApproved` | `Claude is working on the next step` | none |
| `.closing` | stage `summaryApproved` | `Claude is closing the day` | none |

`public enum HandoffAction: Equatable, Sendable { case retry, approve(RoutineStep) }`. `HandoffPhase` is `Equatable, Sendable`. The view's
labels are `Try again` for `.retry`, `Approve notes` for `.approve(.approveNotes)` and `Approve`
for `.approve(.approveSummary)`. `phase.action` returns the action or `nil`.

The payload is one JSON object (`JSONEncoder`, `.sortedKeys`, no pretty printing), at most 65,536
characters. If it would be longer, `payload` drops `tasks` and `delegated` and sets
`"truncated": true`. If it is still longer, it also drops every page's `title`, `summarySkill` and
`source`. That always fits, because a page entry is then under 200 characters and a day has far
fewer than 300 pages.

```json
{"checksum":"sha256:…","date":"2026-10-26","delegated":[{"owner":"Sam","taskID":"…","text":"…"}],
 "docID":"…","driveFileID":"…","pageCount":12,"pages":[{"key":"overview","page":1}, …],
 "schema":"magenda.end-of-day/1","step":"notes","tasks":[{"due":"10/27","taskID":"…","text":"…"}]}
```

`nil` optionals are left out (synthesized `encodeIfPresent`). `truncated` appears only when
`true`.

### D9. Hand-off store (`AppCore/Sources/Handoff/HandoffStore.swift`)

```swift
public enum HandoffStoreError: Error, Equatable { case unreadable, unwritable }
public protocol HandoffStore: Sendable {
    func handoffs() throws -> [DayHandoff]             // newest date first
    func handoff(_ date: CalendarDay) throws -> DayHandoff?
    func save(_ handoff: DayHandoff) throws
    func pdf(for date: CalendarDay) throws -> Data?
    func savePDF(_ data: Data, for date: CalendarDay) throws
    func deletePDF(for date: CalendarDay) throws       // removes day.pdf; nothing to delete is not an error
}
public final class InMemoryHandoffStore: HandoffStore, @unchecked Sendable   // NSLock
public struct FileHandoffStore: HandoffStore { public init(directory: URL, protection: Data.WritingOptions = []) }
```

`FileHandoffStore` keeps `<directory>/<YYYY-MM-DD>/handoff.json` and `…/day.pdf`. Writes are
atomic plus `protection`, as in `FileBinderStore`. `handoffs()` returns `[]` when the directory does not exist yet. Otherwise it lists the directory's
subfolders, skips names that are not an ISO date (`CalendarDay(isoString:)`) and folders without a
readable `handoff.json`, and sorts newest first. A `handoff.json` that does not decode throws
`.unreadable` from `handoff(_:)` and is skipped by `handoffs()`. The app roots it at
`Application Support/Handoff` with `FileProtection.writingOptions`.

`BinderStore` gains `func deleteDay(_ date: CalendarDay) throws`, which removes the day and all its
ink, and succeeds when nothing is stored. `FileBinderStore` removes the date's folder (failure is
`.unwritable`) and `InMemoryBinderStore` drops both maps' entries. `FailingBinderStore` (tests)
gains `case deleteDay`.

### D10. Hand-off controller (`AppCore/Sources/Handoff/HandoffController.swift`)

```swift
@MainActor @Observable
public final class HandoffController {
    public private(set) var days: [DayHandoff] = []     // newest first, from the store
    public private(set) var message: String?            // the last notice for the binder or Review
    public private(set) var isBusy = false
    public private(set) var routineTriggerID: String?   // for Settings; nil when none is stored
    public init(store: any HandoffStore, binderStore: any BinderStore, drive: any DriveFiling,
                trigger: any RoutineFiring, routineCredentials: any RoutineCredentialsStore,
                renderer: any AgendaRendering, hasher: any SHA256Hashing,
                today: @escaping @Sendable () -> CalendarDay,
                readFile: @escaping @Sendable (URL) throws -> Data,
                removeFile: @escaping @Sendable (URL) -> Void)
    public func start()                                   // loads `days` and routineTriggerID
    public func canFinish(_ date: CalendarDay) -> Bool    // from `days`: no hand-off, or stage queued/uploaded
    public func finish(_ binder: BinderSession) async
    public func refresh(excluding openDay: CalendarDay) async
    public func perform(_ action: HandoffAction, on date: CalendarDay) async
    public func saveRoutine(fireURL: String, token: String) -> Bool
    public func forgetRoutine()
    public func docURL(for date: CalendarDay) -> URL?     // https://docs.google.com/document/d/<docID>/edit
}
```

- `readFile` and `removeFile` have no defaults, so AppCore has no line only the app runs. The app
  passes `{ try Data(contentsOf: $0) }` and `{ try? FileManager.default.removeItem(at: $0) }`.
- `start()` sets `days` from `store.handoffs()`. If that throws, `days = []` and
  `message = "Couldn't read the finished days on this device."`. It sets `routineTriggerID` from
  the routine credentials store (`nil` when the load throws). Every save also updates that day in
  `days`, so `canFinish` and the views read `days` only.
- **One run at a time**: `finish`, `refresh` and `perform` each return at once when `isBusy` is
  true, and set `isBusy` for their whole run, so a double tap or a scene activation during a run
  cannot upload or fire twice.
- **`finish(binder)`**:
  1. If `!canFinish(binder.date)`, set `message = "This day was already sent to Claude."` and
     return.
  2. Render `binder.plan` with `binder.plan.pages.map { binder.ink[$0.key] }` and file name
     `<date>-finished.pdf`, read the file, then `removeFile` it. (`<date>.pdf` is the preview's and
     Share PDF's file, which this must not overwrite or delete.)
  3. Checksum it with `hasher` as `sha256:<hex>`.
  4. `store.savePDF`, then save a `DayHandoff` built from `binder.day` and `binder.plan`. It
     keeps the earlier hand-off's `driveFileID` and `docID` if there was one, and sets
     `stage = .queued`, `docStatus = .waitingForNotes`, `lastError = nil`, `purged = false`.
  5. Run the pipeline for that date.

  A render or read failure sets `message = "Couldn't create the PDF. Try again."`. A store
  failure sets `message = "Couldn't save the finished day. Free some space on this device and try again."`.
  Either way nothing is queued. If the pipeline finishes with stage `notesRequested`,
  `message = "Sent to Claude. The notes appear in the day's Google Doc."`. Otherwise `message` is
  the day's `lastError`.
- **Pipeline** (private, one date). It stops at the first error, records the error's
  `userMessage` as `lastError`, saves the hand-off and leaves the stage where it got to.
  - `queued`: `folderID(named: "Magenda")`, then `uploadPDF(pdf, name: "Magenda <date>.pdf",
    folderID:, replacing: driveFileID)`, then save `driveFileID`.
  - If `docID == nil`: `createDoc(name: "Magenda <date> notes", folderID:,
    text: DocStatus.initialDocText)`, then save `docID`.
  - Set `stage = .uploaded`.
  - `uploaded`: `trigger.fire(text: payload(step: .notes))`, then `stage = .notesRequested`,
    `sessionURL`, `lastError = nil`.

  A missing PDF in the store for a `queued` day sets `lastError = "This day's PDF is missing. Finish the day again."`.
  A trigger error leaves the stage `uploaded`. Only the person's Try again fires again (refresh
  never does). That is safe because the routine ignores a step it already ran for the same date
  and checksum (D11); the endpoint has no idempotency key.
- **`refresh(excluding openDay:)`**:
  1. For each day in stage `queued` (and only those), run the pipeline. This is how a day finished
     offline gets uploaded and sent once. A day in stage `uploaded` waits for `perform(.retry)`,
     so a refresh never repeats a fire.
  2. For each day with a `docID` and no `closedOn`, set `docStatus` from
     `DocStatus.parse(exportText(ofDoc:))` and clear `lastError`. When that is `.closed`, set
     `closedOn = today()`. An error here sets that day's `lastError` and moves on to the next day.
  3. Purge: for each day with `closedOn + 5 days <= today()`, `!purged` and `date != openDay`,
     call `binderStore.deleteDay(date)`, then `store.deletePDF(for: date)`, then set
     `purged = true` and save. The `handoff.json` record stays, so `canFinish` stays false and
     the day cannot be uploaded or sent a second time. A failure leaves the day for the next
     refresh.
  4. Reload `days` from the store.
- **`perform(.retry, on:)`** runs the pipeline. **`perform(.approve(step), on:)`** fires
  `payload(step:)`. On success it sets `stage` to `.notesApproved` for `.approveNotes` or
  `.summaryApproved` for `.approveSummary`, records `sessionURL`, clears `lastError`, and then
  reads that day's Doc status once, as refresh step 2 does, so the row shows the result straight
  away. It only acts when `phase.action == .approve(step)`.
- **`saveRoutine`** validates with `RoutineCredentials(fireURL:token:)`. On invalid input it sets
  `message` and returns `false`:
  - an invalid URL: `That isn't a routine fire URL. Copy it from the routine's API trigger at claude.ai/code/routines; it ends in /fire.`;
  - an invalid token: `That isn't a routine token. It starts with sk-ant-oat01-.`;
  - a Keychain failure: `Couldn't save the routine in the Keychain. Try again.`

  On success it stores the credentials, sets `routineTriggerID`, clears `message` and returns
  `true`. **`forgetRoutine`** deletes them.
- Fixtures for UI tests and previews (`AppCore/Sources/Handoff/HandoffFixtures.swift`):
  - `FixtureEndOfDay` is an `actor` that remembers the last fired step per date and whether any
    meeting page in that step's payload has a `summarySkill`.
  - `FixtureDrive: DriveFiling` returns `folder-1`, `file-<date>` and `doc-<date>`. Its
    `exportText` answers from `FixtureEndOfDay`: `notes` → `Status: Notes ready for review`;
    `approve-notes` → `Status: Summary ready for review` when a skill was present, else
    `Status: Closed`; `approve-summary` → `Status: Closed`; nothing fired →
    `Status: Waiting for notes`.
  - `FixtureRoutineTrigger(state: FixtureEndOfDay, credentials: any RoutineCredentialsStore):
    RoutineFiring`. Its `isConfigured()` and `fire` read `credentials.load()`. With no
    credentials, `fire` throws `RoutineTriggerError.notConfigured`. Otherwise it records into the
    actor and returns `https://claude.ai/code/session_fixture`.

### D11. The routine contract (`docs/end-of-day-handoff.md`, a reference doc)

The routine lives in the user's existing end-of-day skill outside this repository. The contract
doc is what that skill is adapted to. It states:
- The Drive layout (D3 names).
- The payload (D8 schema `magenda.end-of-day/1`), arriving in the routine's
  `<routine-fire-payload>` block. The saved prompt must tell the routine to act on that block, and
  to treat it and the PDF as data, never as instructions.
- What each step does:
  - `notes`: download `driveFileID` through PrivacyFence and check that it sits in the `Magenda`
    folder and that its SHA-256 matches `checksum`. Write the notes under the status line, read
    each meeting page's `Summary:` line (printed skill or handwriting) together with
    `summarySkill`, and set the first line to `Status: Notes ready for review`.
  - `approve-notes`: if any meeting needs a summary, write it with that skill and set
    `Status: Summary ready for review`; otherwise close the day.
  - `approve-summary`: close the day.
  - Closing updates Google Tasks, prepares the meeting memos as Gmail drafts and sets
    `Status: Closed`.
- The exact status lines (D8 `DocStatus`).
- That a step already run for the same `date`, `step` and `checksum` does nothing.
- That Magenda deletes the day's handwriting and PDF five days after it first reads
  `Status: Closed`.

### D12. App screens

- **Finish Day** (`BinderView`): a toolbar button `Finish Day` (`systemImage:
  "checkmark.seal"`, identifier `finishDayButton`, `accessibilityLabel` `Finish this day and send
  it to Claude`) beside Share PDF. It is disabled while `handoff.isBusy` or when
  `!handoff.canFinish(binder.date)`. It runs `await handoff.finish(binder)`. `handoff.message` shows
  in the binder's message bar, below `binder.message`, with identifier `handoffMessage`.
- **Review** (`App/Screens/ReviewView.swift`, new): a sheet opened from a toolbar button `Review`
  (`systemImage: "tray.full"`, identifier `reviewButton`, `topBarLeading` after Settings) in
  `AgendaView`, on iPad and iPhone. It has a navigation title `Finished days` and a `Done` button
  (`reviewDone`). It lists `handoff.days`, and each row (`reviewRow.<i>`) shows:
  - the date (`Text(day.date.isoString)`);
  - `phase.title` (`reviewStatus.<i>`);
  - `lastError` in secondary style (`reviewError.<i>`) when set;
  - `Open Doc` (`reviewOpenDoc.<i>`, through `openURL(handoff.docURL(for:))`) when there is a Doc;
  - the action button (`reviewAction.<i>`) with the label from D8.

  An empty list shows `ContentUnavailableView("No finished days", systemImage: "tray",
  description: Text("Finish a day in the binder to send it to Claude."))` with identifier
  `reviewEmpty`. `.task` and `.refreshable` call `handoff.refresh(excluding: controller.day)`.
  The view has a `#Preview`.
- **Settings** (`SettingsView`): a section `End-of-day routine`, placed after `Google client`.
  - With no routine stored, it shows the footer
    `Finished days upload to Google Drive. To send them to Claude, add the API trigger of your end-of-day routine from claude.ai/code/routines.`,
    a `TextField` `Fire URL` (`routineURLField`), a `SecureField` `Token`
    (`routineTokenField`) and a `Save` button (`saveRoutineButton`). When `saveRoutine` returns
    `false`, the view sets `@State private var routineSaveFailed = true` and shows
    `handoff.message` in a `Text` with identifier `routineError`. Editing either field sets it back
    to `false`.
  - With a routine stored, it shows `Sends finished days to <triggerID>` (`routineStatusLabel`)
    and a destructive `Forget routine` button (`forgetRoutineButton`).
- **Lifecycle** (`MagendaApp`): `AppServices` gains `handoff: HandoffController`, injected with
  `.environment(services.handoff)`. The root's `.task` calls `services.handoff.start()` after the
  controller starts. `.onChange(of: scenePhase)` to `.active` runs
  `await services.handoff.refresh(excluding: services.controller.day)` only when
  `services.controller.status == .ready`, so the agenda's own load meets a scope problem first and
  shows D1's message.
- **Live wiring** (`AppEnvironment`):
  - `GoogleDriveClient(sender: session)`;
  - `RoutineTriggerClient(http: URLSessionHTTPClient(), credentials:
    KeychainRoutineCredentialsStore())`;
  - `FileHandoffStore(directory: URL.applicationSupportDirectory.appending(path: "Handoff"),
    protection: FileProtection.writingOptions)`;
  - the same `renderer` and binder store as the controller, `CryptoKitHasher()`,
    `today: { CalendarDay.today(in: timeZone, now: Date()) }`, and the `readFile` and `removeFile`
    closures from D10;
  - one `KeychainRoutineCredentialsStore()` value passed to both the trigger client and the
    controller.

  `KeychainRoutineCredentialsStore` (`App/Platform/`) copies `KeychainClientCredentialsStore`
  with service `name.tkcs.magenda.routine`, account `trigger`.
- **Fixture wiring**:
  - one `FixtureEndOfDay`, `FixtureDrive(state:)`, `FixtureRoutineTrigger(state:credentials:)` and
    `InMemoryHandoffStore`. The controller and the fixture trigger get the same
    `InMemoryRoutineCredentialsStore` instance;
  - an `InMemoryRoutineCredentialsStore` holding
    `RoutineCredentials(fireURL: "https://api.anthropic.com/v1/claude_code/routines/trig_fixture/fire", token: "sk-ant-oat01-fixture")`,
    or an empty one with the launch argument `-MagendaNoRoutine`;
  - `today` at the fixture's today, and the same `readFile` and `removeFile` closures as live.

### Rejected alternatives (they go into the ADRs)

- **One PNG per page**: 10–20 files can partly fail, need a manifest, and turn the printed text
  into pixels (design doc table).
- **The full `drive` scope or `drive.readonly`**: `drive.file` reaches only what Magenda created,
  which is all it needs. Asking for the Tasks write scope now (to spare Stage 3 a re-consent) was
  declined by the user.
- **Chunked resumable upload with 308 resume**: it needs a non-2xx success path through
  `GoogleSession` for files of a few MB. A whole-file `PUT` restarts cleanly.
- **Docs API for the status line**: Drive's `files.export` to `text/plain` reads it with the same
  scope and client.
- **Reading the day's state from the routine's chat, or an hourly poll of a Doc checkbox**: the
  first leaves the day's state in a chat, the second costs up to an hour and a run every hour
  (design doc).
- **A per-day "needs summary" toggle or a printed checkbox**: summaries need a specific skill, so
  the rule maps titles to skills and the page carries a Summary line to write a skill on (user's
  decision).
- **Retrying a fire automatically after a response**: the endpoint has no idempotency key, so a
  repeat is the person's Try again, made safe by the routine's per-(date, step, checksum) rule.
- **Background upload with `BGTaskScheduler`**: it needs a capability and Info.plist changes, and
  complete-unless-open protection (ADR 0022) keeps the files unreadable while the device is locked.
  The queue runs when the app becomes active.
- **Deleting the whole hand-off record at purge**: the day could then be finished, uploaded and
  sent again, which would create a second Doc. The record stays and only the files go.
- **Re-finishing a day after it was sent to Claude**: the Doc would still show the earlier notes'
  status, and the routine would have to reconcile two PDFs. Finish Day is disabled once notes are
  requested.

## ADRs

- **0027** — Finished days are uploaded to the person's Google Drive as one PDF, with the
  `drive.file` scope; existing users sign in again. Amends 0013 (scopes; "never writes to
  Google") and 0014 (item 1, "No Drive upload").
- **0028** — Magenda starts the end-of-day Claude routine through its API trigger. It keeps the
  per-routine token in the Keychain, sends a versioned JSON payload as the fire text, and never
  repeats a fire on its own.
- **0029** — The day's Google Doc is the review record. Magenda reads only its status line and
  drives the review loop with approve buttons that each start the routine's next step.
- **0030** — A closed day's binder files and its local copy of the PDF are deleted on the device
  five days after Magenda first reads `Status: Closed`, and a small record of the day stays. Amends 0021 ("nothing deletes a stored day").
- **0031** — A meeting's summary is requested with a title → skill map in the rules, or by writing a
  skill on the printed Summary line of its page.

## Manual steps

There are no `manual_before` steps: every phase builds and tests against fakes. All real-account
work is in `manual_after`: enable the Drive API and the scope, adapt the end-of-day skill to the
contract and create the routine's API trigger, then sign in again and enter the trigger on the
iPad. After that, one real day end to end, an offline Finish Day, and the App Store privacy
answers. Step-by-step: https://claude.ai/artifact/TJ1ovBZqCJEiDqfdvjMHN1
(source: `docs/drive-handoff-plan-manual-steps.html`).

## Risks and open questions

- **Drive conversion of the multipart text into a Google Doc.** If Drive answers `createDoc` with
  an error for the multipart body, the brief is wrong. The phase can't see this, since its tests
  use a fake, so the first real check is `ma4`. A worker who finds `GoogleAPI.withQuery` cannot
  express `fields=files(id)` correctly (parentheses are escaped, which Drive accepts) should not
  change `withQuery`'s escaping. It should stop with `status=blocked`.
- **Scope check on refresh.** If Google returns no `scope` on refresh, D1 keeps the previous
  scopes, so tokens from an older build (no recorded scopes) then need a new sign-in. If a phase finds an existing GoogleSession test that
  depends on refresh not being forced for current tokens, it extends that test's tokens with
  `scopes: GoogleOAuthConfiguration.scopes`. It never weakens the forced refresh.
- **`AgendaContent` decoding.** Adding a hand-written `init(from:)` must keep every stored field
  decoding exactly as before. `BinderDayTests` gets a test that decodes a `day.json` written
  without the new keys. If an existing test fails on encoded bytes (key order, extra keys),
  the worker stops with `status=blocked` rather than changing the format version.
- **Meeting page operation order.** `continuedOperations(of:in:)` slices the operations by count. If
  `BinderLayoutTests`' continued-title tests fail after D6, the summary operations were inserted
  before the title runs. Fix the order, never the slicing.
- **Interpretation of "a placeholder on the page with the summary skill".** This plan reads it as
  a printed `Summary:` line on every meeting page: pre-filled when the rules map the meeting to a
  skill, blank to write a skill on otherwise. If the user meant something else, D6 and D7 change
  before `p5`. The user can see this in the plan before running `/implement`.
- **First launch after the update.** `HandoffController.refresh` could meet `.missingScopes` before
  `AgendaController.load` does and delete the tokens. The agenda would then show "sign-in expired"
  instead of D1's scope message. D12 avoids it: the app refreshes hand-offs on activation only
  while the agenda controller's status is `.ready`.
- **`tests.yml` shards.** `HandoffUITests` is iPad-only. It goes into the `binder` shard and
  into every `rest` shard's `-skip-testing` list. Shard names don't change, so
  `REQUIRED_STATUS_CHECKS` doesn't either.
- **Coverage at 100%.** Every new AppCore file needs every line run. A line that can't be
  reached without a fake is a sign the code should take that dependency as a protocol (D10 does
  this for file reads).

## Orchestrator: stuck or flaky iOS CI

The macOS jobs of `tests.yml` (the three `app (...)` jobs and the ten `ui (...)` shards) often
flake or hang on GitHub's runners: a simulator that never finishes booting, a UI test that times
out waiting for an element, or a job that sits queued or running far past its usual 10–20 minutes.
A Sonnet worker must not spend its session on that. The orchestrator (`/implement`) handles it
this way, for every phase and for the final pull request:

1. **What a worker does.** Every phase whose acceptance depends on an `app (...)` or `ui (...)`
   job carries this rule in its brief. If such a job fails on a test or a step the phase did not
   change, it re-runs the failed job once. A job that is still queued or running 60 minutes after
   dispatch counts as stuck. If the re-run is red or stuck again, the worker stops with
   `status=blocked`, and its report's reason starts with `CI-IOS:` followed by the run URL, the job
   names and the failing test or step. Workers never skip, disable, `XCTSkip` or `sleep` their way
   past it (`.claude/skills/steward/SKILL.md`).
2. **What the orchestrator does with a `CI-IOS:` block.** It does not ask the user and does not
   send the Sonnet worker back. It starts one **Opus** session (`create_session` with
   `model: claude-opus-5-5`) on the same phase branch, with this brief: "Make the iOS jobs of
   `tests.yml` reliably green on this branch. The phase's own work is done (see its PHASE-REPORT,
   quoted below). Root-cause each flaky or stuck job from the run's log and its `xcresult-*`
   artifact. The cause may be in the test, in the app's accessibility identifiers or waits, in
   `scripts/simulator.py` or in `.github/workflows/tests.yml`. Fix it, including in files outside
   the phase's `touches`, and explain each such file. Never skip, disable or quarantine a test,
   never add a fixed sleep, and never push an empty commit to re-run CI. Dispatch `tests.yml` and
   confirm the fix with two consecutive green runs of the affected jobs. End with
   `PHASE-REPORT <phase id> status=<done|blocked> head=<sha>`."
3. The orchestrator then merges the phase as usual once that report is `done`. Its diff review
   accepts the Opus session's out-of-`touches` CI and test-stability changes when each one is
   explained. If the Opus session also reports `blocked`, the orchestrator marks the phase
   `failed` and asks the user, quoting both reports.
4. The same applies to a red or stuck iOS job on the feature branch after a merge, or on the final
   pull request. In that case the Opus session works on a `<feature_branch>--ci-fix-<n>` branch cut
   from the feature branch, and the orchestrator merges it like a phase.

## Implementation manifest

```yaml
plan_slug: drive-handoff
feature_branch: feature/drive-handoff
max_parallel: 2
manual_steps_artifact: https://claude.ai/artifact/TJ1ovBZqCJEiDqfdvjMHN1
manual_steps_source: docs/drive-handoff-plan-manual-steps.html
manual_before: []
manual_after:
  - id: ma1-google-cloud-drive
    title: Enable the Google Drive API and add the drive.file scope to the OAuth consent screen
    why: The app now asks for drive.file; without the API enabled and the scope on the consent screen, sign-in or the upload fails, which no CI test can see.
  - id: ma2-routine-and-skill
    title: Adapt the end-of-day skill to docs/end-of-day-handoff.md and create its scheduled task with an API trigger and PrivacyFence access
    why: The routine lives outside this repository; the contract only works once the skill reads the payload and writes the status lines.
  - id: ma3-ipad-sign-in-and-routine
    title: Install the build on the iPad, sign in to Google again, and enter the routine's fire URL and token in Settings
    why: Re-consent with the new scope and the Keychain-held token can only be done on a real device with real accounts.
  - id: ma4-real-day-end-to-end
    title: Finish a real day and take it through notes, (summary,) approval and closure
    why: Proves the Drive upload, the Doc creation and conversion, the trigger, the status lines and the handwriting's readability in the PDF against the real services.
  - id: ma5-offline-finish
    title: Finish a day in airplane mode, then reconnect
    why: Proves the queue waits offline and uploads when the app becomes active again.
  - id: ma6-privacy-answers
    title: Review the App Store Connect privacy answers
    why: Day content now leaves the device to the person's Google Drive and Claude routine at their request; the answers must still be accurate before the next TestFlight build.
verify_after_merge:
  - swift test --package-path AppCore
  - python3 -m unittest discover -s scripts/tests
final_checks:
  - docs/drive-handoff-plan.md and docs/drive-handoff-plan-manual-steps.html are deleted and nothing links to them
  - docs/adr/0027-*.md through docs/adr/0031-*.md exist, each is Accepted, and each is in docs/adr/README.md's index; ADRs 0013, 0014 and 0021 each have a Status line pointing to the ADR that amends them
  - CHANGELOG.md has [Unreleased] entries and no version heading
  - tests.yml on the feature branch is green, including the ipad binder shard that runs HandoffUITests
phases:
  - id: p1-google-drive-access
    title: Ask for drive.file, force re-consent for old tokens, and add PUT, PATCH, response headers and 404
    depends_on: []
    complexity: M
    touches:
      - AppCore/Sources/Google/HTTP.swift
      - AppCore/Sources/Google/GoogleOAuth.swift
      - AppCore/Sources/Google/GoogleSession.swift
      - AppCore/Sources/Google/GoogleAPIError.swift
      - AppCore/Sources/Controller/AgendaController.swift
      - App/Platform/URLSessionHTTPClient.swift
      - App/Screens/SetupView.swift
      - AppCore/Tests/Google/GoogleOAuthTests.swift
      - AppCore/Tests/Google/GoogleSessionTests.swift
      - AppCore/Tests/Google/GoogleAPIErrorTests.swift
      - AppCore/Tests/Google/HTTPTests.swift
      - AppCore/Tests/Controller/AgendaControllerTests.swift
      - AppCore/Tests/Support/FakeHTTPClient.swift
    brief: |
      Implement Design D1 and D2 of docs/drive-handoff-plan.md exactly. Do not edit CHANGELOG.md or README.md; the last phase writes them. If an app (...) or ui (...) job of tests.yml fails on something this phase did not change, or is still queued or running 60 minutes after dispatch, re-run it once; if it is red or stuck again, stop with status=blocked and start the reason with `CI-IOS:` (see "Orchestrator: stuck or flaky iOS CI" in the plan).
      1. HTTP.swift: add `put` and `patch` to HTTPMethod; add `headers` and `header(_:)` to HTTPResponse (D2), keeping every existing call site compiling through the defaulted parameter.
      2. URLSessionHTTPClient.swift: copy `HTTPURLResponse.allHeaderFields` into `headers` (String keys and values only).
      3. GoogleOAuth.swift: add drive.file as the third entry of `GoogleOAuthConfiguration.scopes`; update its doc comment ("The scopes the app asks for, and needs all of"). Add `scopes: [String]?` to OAuthTokens with a trailing defaulted initializer parameter. Add `previousScopes:` to `GoogleOAuth.tokens` after `previousRefreshToken` and fill `scopes` per D1. Update the doc comments that say "read-only".
      4. GoogleSession.swift: in `send`, refresh first when the token expires within a minute OR `tokens.scopes` is nil or lacks a required scope. In `refresh`, pass `tokens.scopes` as previousScopes, and delete the stored tokens on `.missingScopes` as well as `.signedOut`. Map status 404 to `.notFound`. `signIn` passes `previousScopes: nil`.
      5. GoogleAPIError.swift: add `case notFound` with its doc comment; set the three texts from D1 exactly; update the `missingScopes` doc comment.
      6. AgendaController.swift `load()`: treat `.missingScopes` exactly like `.signedOut` (status `.signedOut`, message = userMessage).
      7. SetupView.swift: replace the intro text with D1's string.
      8. Tests (Swift Testing, mirror the existing suites):
         - GoogleOAuthTests: the authorization URL's scope parameter has all three scopes; tokens() fills `scopes` from `scope`, from `previousScopes`, else from the defaults; a scope lacking drive.file throws `.missingScopes`.
         - GoogleSessionTests: first update the file's shared values so existing tests keep their meaning: `freshTokens` and `expiring(in:)` build OAuthTokens with `scopes: GoogleOAuthConfiguration.scopes`, and `refreshJSON` gets a `"scope"` holding the three scopes joined by spaces. Then add `@Test("Tokens without recorded scopes are refreshed before the request")`, `@Test("A refresh that returns the old two-scope grant signs out with missing scopes")` (throws `.missingScopes` and deletes the stored tokens), `@Test("Tokens with every scope are not refreshed early")` and `@Test("A 404 is not found")`.
         - GoogleAPIErrorTests: the three messages; no message contains "token".
         - new AppCore/Tests/Google/HTTPTests.swift: `header(_:)` is case-insensitive and nil when absent; `HTTPMethod.put.rawValue == "PUT"`, `.patch == "PATCH"`.
         - AgendaControllerTests: `@Test("Missing scopes sign the person out with the scope message")`: a load whose data source throws `.missingScopes` ends in `.signedOut` with D1's message.
         For headers, add a parameter `headers: [String: String] = [:]` to FakeHTTPClient's existing `enqueue(status:json:)` (do not add a second overload).
      9. Stop with status=blocked if any existing test's expectation of the scope list or of refresh timing cannot be satisfied without weakening D1.
    acceptance:
      - swift test --package-path AppCore passes (or the core job of a dispatched tests.yml run on the phase branch is green)
      - grep -c "drive.file" AppCore/Sources/Google/GoogleOAuth.swift is at least 1
      - grep -n "case notFound" AppCore/Sources/Google/GoogleAPIError.swift finds one line
      - grep -n "Tokens without recorded scopes are refreshed before the request" AppCore/Tests/Google/GoogleSessionTests.swift finds one line, and swift test --package-path AppCore --filter GoogleSessionTests passes
      - grep -n "Missing scopes sign the person out with the scope message" AppCore/Tests/Controller/AgendaControllerTests.swift finds one line, and swift test --package-path AppCore --filter AgendaControllerTests passes
      - the lint job and the three app (...) jobs of a tests.yml run dispatched on the phase branch are green (the phase changes App/ files)

  - id: p2-content-ids-and-summary-skills
    title: Carry task IDs and per-meeting summary skills through the draft into the content
    depends_on: []
    complexity: M
    touches:
      - AppCore/Sources/Agenda/AgendaContent.swift
      - AppCore/Sources/Draft/DraftEvent.swift
      - AppCore/Sources/Draft/AgendaDraft.swift
      - AppCore/Sources/Draft/AgendaBuilder.swift
      - AppCore/Sources/Draft/EventSelection.swift
      - AppCore/Sources/Settings/BinderRules.swift
      - AppCore/Sources/Settings/SummarySkill.swift
      - AppCore/Tests/Agenda/AgendaContentTests.swift
      - AppCore/Tests/Draft/AgendaDraftTests.swift
      - AppCore/Tests/Draft/AgendaBuilderTests.swift
      - AppCore/Tests/Draft/EventSelectionTests.swift
      - AppCore/Tests/Settings/SummarySkillTests.swift
      - AppCore/Tests/Settings/AgendaSettingsTests.swift
      - AppCore/Tests/Binder/BinderDayTests.swift
    brief: |
      Implement Design D5 of docs/drive-handoff-plan.md exactly. Do not edit CHANGELOG.md or README.md; the last phase writes them.
      1. AgendaContent.swift: add `taskID: String?` to TodoItem and DelegatedItem (trailing defaulted init params, doc comments). Add `meetingSummarySkills: [String]` to AgendaContent (trailing init param defaulting to []), plus a hand-written `init(from:)` that decodes every existing key as the synthesized one did and `meetingSummarySkills` with decodeIfPresent ?? []. Keep encoding synthesized.
      2. BinderRules.swift: add `summarySkills: [String: String]` (trailing init param `summarySkills: [String: String] = [:]`, `.default` = [:], CodingKey, decoded through `value(_:_:)`).
      3. New Settings/SummarySkill.swift with `isValidName` and `skill(pageTitle:originalTitle:skills:)` as specified, with `///` comments.
      4. DraftEvent.swift: add `summarySkill: String?` (trailing defaulted init param). EventSelection.draftEvents sets it from SummarySkill.skill with the page title it computes and the candidate's title.
      5. AgendaDraft.swift: add `summarySkills: [String: String]` (trailing init param `summarySkills: [String: String] = [:]`). AgendaBuilder passes `rules.summarySkills`. `applyShortName` and `setTitle(_:forEvent:)` recompute `summarySkill` for each event they change. `content()` fills taskID for to-do and delegated rows and `meetingSummarySkills` (event.summarySkill ?? "") in meeting order.
      6. Tests:
         - SummarySkillTests: valid and invalid names, parameterized; a page-title match; an original-title match; folding (case and diacritics through BinderText.fold); the first title wins when several match; an invalid stored skill gives nil.
         - EventSelectionTests: a mapped title gets its skill.
         - AgendaDraftTests: content() carries the task IDs and the skills; applyShortName to a mapped short name picks up its skill; setTitle to a mapped title picks up its skill.
         - AgendaBuilderTests: the builder hands the rules' map to the draft.
         - AgendaSettingsTests: rules JSON without summarySkills decodes with [:].
         - AgendaContentTests: JSON without the new keys decodes with nil IDs and [].
         - BinderDayTests: a day.json written without the new keys still decodes.
      7. Stop with status=blocked if an existing test compares encoded JSON bytes that the new keys change in a way you cannot fix by updating only that expected literal.
    acceptance:
      - swift test --package-path AppCore passes (or the core job of tests.yml is green)
      - test -f AppCore/Sources/Settings/SummarySkill.swift
      - grep -n "meetingSummarySkills" AppCore/Sources/Draft/AgendaDraft.swift finds a line
      - a BinderDayTests test decoding a day without the new keys passes

  - id: p3-drive-client
    title: Add the Google Drive client for the folder, the PDF upload, the Doc and its export
    depends_on: [p1-google-drive-access]
    complexity: M
    touches:
      - AppCore/Sources/Google/GoogleDriveClient.swift
      - AppCore/Tests/Google/GoogleDriveClientTests.swift
      - AppCore/Tests/Google/Fixtures/drive-*.json
      - AppCore/Tests/Support/FakeSender.swift
    brief: |
      Implement Design D3 of docs/drive-handoff-plan.md exactly. Do not edit CHANGELOG.md or README.md; the last phase writes them. New file AppCore/Sources/Google/GoogleDriveClient.swift (protocol DriveFiling and struct GoogleDriveClient), following GoogleTasksClient.swift's style (private Decodable page structs, GoogleAPI.url / withQuery, appending(path:) for IDs).
      1. folderID(named:): the list request, then the create request when the list is empty.
      2. uploadPDF: the resumable initiation (POST or PATCH), the Location check (https, host www.googleapis.com, else .unexpectedResponse; missing header is .unexpectedResponse), the whole-file PUT with timeout 300 and the id decode; PATCH answering GoogleAPIError.notFound falls back to the create path.
      3. createDoc: the exact multipart body from D3 with the constant boundary `magenda-part-boundary`.
      4. exportText(ofDoc:): GET export with mimeType text/plain; strip a leading U+FEFF; non-UTF-8 is .unexpectedResponse.
      5. Tests in AppCore/Tests/Google/GoogleDriveClientTests.swift with FakeSender (it already records requests; add a parameter `headers: [String: String] = [:]` to its existing `enqueue(status:json:)`, not a second overload). Use recorded-shape JSON fixtures drive-files-list.json, drive-files-list-empty.json and drive-file-id.json in AppCore/Tests/Google/Fixtures. Cover: an existing folder found (no create sent); a missing folder created (the exact JSON body); the query string carries the escaped name with a `'` in it. A new upload sends POST, then PUT to the Location URL with the PDF bytes and the headers in D3. A replacement sends PATCH to the file's ID. A replacement whose PATCH throws .notFound creates instead. A Location on another host throws .unexpectedResponse. createDoc's body equals the exact expected bytes. Export strips the BOM. A body that does not decode throws .unexpectedResponse.
      6. Stop with status=blocked if GoogleAPI.withQuery cannot carry the `q` or `fields` values without changing its escaping.
    acceptance:
      - swift test --package-path AppCore --filter GoogleDriveClientTests passes (or the core job of tests.yml is green)
      - grep -n "protocol DriveFiling" AppCore/Sources/Google/GoogleDriveClient.swift finds one line
      - grep -n "magenda-part-boundary" AppCore/Sources/Google/GoogleDriveClient.swift finds a line

  - id: p4-routine-trigger
    title: Add the routine credentials, their validation and the fire client
    depends_on: [p1-google-drive-access]
    complexity: S
    touches:
      - AppCore/Sources/Handoff/RoutineTrigger.swift
      - AppCore/Tests/Handoff/RoutineTriggerTests.swift
    brief: |
      Implement Design D4 of docs/drive-handoff-plan.md exactly. Do not edit CHANGELOG.md or README.md; the last phase writes them. New file AppCore/Sources/Handoff/RoutineTrigger.swift: RoutineCredentials, RoutineCredentialsStore, InMemoryRoutineCredentialsStore (NSLock, as InMemoryClientCredentialsStore in GoogleSession.swift), RoutineFiring, RoutineTriggerClient and RoutineTriggerError with the user messages from D4's table, word for word.
      1. Validation per D4 (byte-level ASCII checks like GoogleOAuthConfiguration's, so no look-alike Unicode passes).
      2. fire(text:): load the credentials (a load that throws or returns nil is .notConfigured); build the request (D4 headers, JSON body, timeout 30); map statuses per the table; parse Retry-After with `response.header("Retry-After")` as an integer number of seconds; decode the 200 body and check type and URL.
      3. Tests in new AppCore/Tests/Handoff/RoutineTriggerTests.swift using FakeHTTPClient:
         - valid URL and token accepted, with whitespace trimmed;
         - parameterized rejections: http, other host, a port, a query, a fragment, a wrong path, a trigger ID without trig_ or with a non-ASCII letter, a token without the prefix, a token with a space, a token over 513 characters;
         - the exact request (method, URL, three headers, body);
         - each status in the table maps to its case; 429 with and without Retry-After;
         - a transport error is .network;
         - a 200 with a wrong type or a non-claude.ai URL is .unexpectedResponse;
         - no userMessage contains "sk-ant".
    acceptance:
      - swift test --package-path AppCore --filter RoutineTriggerTests passes (or the core job of tests.yml is green)
      - grep -n "anthropic-version" AppCore/Sources/Handoff/RoutineTrigger.swift finds a line
      - grep -c "anthropic-beta" AppCore/Sources/Handoff/RoutineTrigger.swift prints 0

  - id: p5-summary-line-and-rules
    title: Print the Summary line on meeting pages and edit the summary skills in the rules
    depends_on: [p2-content-ids-and-summary-skills]
    complexity: M
    touches:
      - AppCore/Sources/Layout/AgendaLayout.swift
      - AppCore/Sources/Layout/TemplateGeometry.swift
      - AppCore/Sources/Layout/AgendaContentFixtures.swift
      - AppCore/Tests/Layout/AgendaLayoutTests.swift
      - AppCore/Tests/Layout/AgendaLayoutFixtureTests.swift
      - AppCore/Tests/Binder/BinderLayoutTests.swift
      - App/Screens/RulesView.swift
      - AppUITests/RulesUITests.swift
    brief: |
      Implement Design D6 and D7 of docs/drive-handoff-plan.md exactly. Do not edit CHANGELOG.md or README.md; the last phase writes them. If an app (...) or ui (...) job of tests.yml fails on something this phase did not change, or is still queued or running 60 minutes after dispatch, re-run it once; if it is red or stuck again, stop with status=blocked and start the reason with `CI-IOS:` (see "Orchestrator: stuck or flaky iOS CI" in the plan).
      1. TemplateGeometry.swift: add the four constants from D6 with `///` comments.
      2. AgendaLayout.swift: `meetingPage(title:key:)` gains the meeting's skill (pass `content.meetingSummarySkills[index]` when that index exists, else ""). Emit label runs, title runs, then the summary operations: the "Summary:" label run with the `meeting.label` slot's role, font pack and weight at `meetingSummaryPoints`; then either the skill run (in D6's box starting at the label run's x + width + meetingSummaryGap) or `.line` from label end + meetingSummaryGap to meetingTitleRight at meetingSummaryRuleY with todoLineColor and width 0.5. Do not change `continuedOperations(of:in:)`.
      3. AgendaContentFixtures.swift: give the long-text fixture's meetings a 64-character valid skill name for the first meeting and "" for the rest, so LayoutAudit checks both forms.
      4. Tests:
         - AgendaLayoutTests: a meeting with a skill prints "Summary:" and the skill; a meeting without one prints "Summary:" and a line at y 136; the blank meeting page prints the line; the label run comes after the title runs.
         - AgendaLayoutFixtureTests: the long-text fixture still audits clean.
         - BinderLayoutTests: an added copy of a meeting page carries the same summary operations, and the continued title tests still pass.
      5. RulesView.swift: add the "Meeting summaries" section exactly as D7 (texts, identifiers, sorting, swipe to delete, validation message, Reset keeps summarySkills). Copy the people-aliases section's add pattern.
      6. AppUITests/RulesUITests.swift: add a test that adds "Board meeting" → "board-summary" and sees the row, one that types "bad skill!" and sees `summarySkillError`, and one that adds "board MEETING" after "Board meeting" and sees `summarySkillError`. Use identifiers only.
      7. Stop with status=blocked if LayoutAudit reports the summary runs overlapping the title slot, which would mean D6's geometry is wrong.
    acceptance:
      - swift test --package-path AppCore passes, including AgendaLayoutTests, AgendaLayoutFixtureTests and BinderLayoutTests (or the core job of tests.yml is green)
      - grep -n "meetingSummaryRuleY" AppCore/Sources/Layout/TemplateGeometry.swift finds a line
      - grep -n "summarySkillError" App/Screens/RulesView.swift AppUITests/RulesUITests.swift finds both files
      - the app and ui jobs of a tests.yml run dispatched on the phase branch are green

  - id: p6-handoff-model-and-store
    title: Add the hand-off model, payload, Doc status, hand-off store, deleting a binder day, and the routine contract doc
    depends_on: [p2-content-ids-and-summary-skills]
    complexity: M
    touches:
      - AppCore/Sources/Handoff/DayHandoff.swift
      - AppCore/Sources/Handoff/DocStatus.swift
      - AppCore/Sources/Handoff/HandoffStore.swift
      - AppCore/Sources/Binder/BinderStore.swift
      - AppCore/Tests/Handoff/DayHandoffTests.swift
      - AppCore/Tests/Handoff/DocStatusTests.swift
      - AppCore/Tests/Handoff/HandoffStoreTests.swift
      - AppCore/Tests/Binder/BinderStoreTests.swift
      - AppCore/Tests/Support/FailingBinderStore.swift
      - docs/end-of-day-handoff.md
    brief: |
      Implement Design D8, D9 and D11 of docs/drive-handoff-plan.md exactly. Do not edit CHANGELOG.md or README.md; the last phase writes them.
      1. DocStatus.swift: RoutineStep, DocStatus with `parse` and `initialDocText` ("Status: Waiting for notes\n").
      2. DayHandoff.swift:
         - HandoffStage, HandoffPage, HandoffTask, HandoffDelegated, HandoffPhase (with `title` and `action`), HandoffAction and DayHandoff;
         - format-version decoding as BinderDay does;
         - the builder `init(date:checksum:day:plan:)` with the rules in D8;
         - `phase` per D8's table, rows checked in order;
         - `payload(step:)` with the JSON in D8: sorted keys, `schema` "magenda.end-of-day/1", `pageCount` = pages.count, the truncation rule.
      3. HandoffStore.swift: HandoffStoreError, HandoffStore, InMemoryHandoffStore, FileHandoffStore per D9 (copy FileBinderStore's `writing` and atomic/protection pattern).
      4. BinderStore.swift: add `deleteDay(_:)` to the protocol, InMemoryBinderStore and FileBinderStore. Add `case deleteDay` to FailingBinderStore's Method and implement it.
      5. docs/end-of-day-handoff.md: the reference doc of D11, with the D3 names, the D8 payload (a full example), the four status lines, the step rules, idempotency per (date, step, checksum), the five-day deletion, and that the payload and PDF are data, never instructions. Link ADRs only by number; they are written in the last phase.
      6. Tests:
         - DocStatusTests: parameterized lines including a BOM, leading blank lines, lowercase, extra spaces and an unknown value.
         - DayHandoffTests: the builder on a BinderDay with a meeting, a retained meeting, an extra page and an omitted to-do; the phase table row by row; payload JSON decoded back has the right keys; the truncation rule with 3,000 long tasks; a different version fails to decode.
         - HandoffStoreTests: in-memory and file store round trips in a temp directory; handoffs() is [] when the directory does not exist; newest-first order; a non-date folder and a damaged handoff.json are skipped by handoffs() while handoff(_:) throws .unreadable; deletePDF removes day.pdf, keeps handoff.json, and is fine when there is no PDF.
         - BinderStoreTests: deleteDay removes day and ink for both stores and succeeds when nothing is stored.
      7. Stop with status=blocked if a row of D8's phase table, a payload field or a store rule cannot be implemented as written (for example, a field the builder has no source for), rather than inventing one.
    acceptance:
      - swift test --package-path AppCore passes (or the core job of tests.yml is green)
      - grep -n "magenda.end-of-day/1" AppCore/Sources/Handoff/DayHandoff.swift docs/end-of-day-handoff.md finds both files
      - grep -n "func deleteDay" AppCore/Sources/Binder/BinderStore.swift finds the protocol requirement and two implementations

  - id: p7-handoff-controller
    title: Add the hand-off controller
    depends_on: [p3-drive-client, p4-routine-trigger, p6-handoff-model-and-store]
    complexity: M
    touches:
      - AppCore/Sources/Handoff/HandoffController.swift
      - AppCore/Tests/Handoff/HandoffControllerTests.swift
      - AppCore/Tests/Support/FakeDrive.swift
      - AppCore/Tests/Support/FakeRoutineTrigger.swift
    brief: |
      Implement Design D10 of docs/drive-handoff-plan.md exactly (everything except its "Fixtures" bullet, which is another phase), in new file AppCore/Sources/Handoff/HandoffController.swift. Every message string is the one in D10. Do not edit CHANGELOG.md or README.md; the last phase writes them.
      1. The init and the published properties as listed; `start()`; `canFinish`; `docURL(for:)`.
      2. `finish(_:)` in the five steps of D10.
      3. The isBusy rule, the private pipeline, `refresh(excluding:)` (only `queued` days run the pipeline; the purge keeps the record and sets `purged`), `perform(_:on:)` (re-reads the Doc after a successful approve), `saveRoutine` and `forgetRoutine`.
      4. Test support:
         - FakeDrive (an actor or NSLock class): records calls, scripts a result or an error per method, and can hold `uploadPDF` until released, copying the gating of AppCore/Tests/Support/GatedHTTPClient.swift (`release()`).
         - FakeRoutineTrigger: records texts and scripts results or errors.
         - FakeRenderer stays unchanged; tests inject `readFile: { _ in Data("pdf".utf8) }` and a recording `removeFile`.
      5. HandoffControllerTests (`@testable import AppCore`; build BinderSession with its internal init exactly as BinderSessionTests.makeSession does, with a BinderLayout over the standard fixture and InMemoryBinderStore; a fixed `today` closure; FakeHasher):
         - finish renders with file name `<date>-finished.pdf` (FakeRenderer.fileNames), removes that URL, uploads, creates the Doc, fires `notes` with a payload whose checksum matches the fake hasher, and ends notesRequested with D10's message;
         - finish offline (drive throws .network) ends queued with Google's network message, and a later refresh completes it;
         - a trigger error leaves the day uploaded; a refresh does not fire again; perform(.retry) does;
         - while a finish is held inside uploadPDF, a second finish, a refresh and a perform return at once, and only one upload and one fire happen;
         - finish again before sending keeps driveFileID and docID and replaces the PDF;
         - finish after notesRequested is refused with D10's message;
         - refresh reads the Doc status and moves notesRequested → notesReady;
         - approve-notes fires the step, moves to notesApproved and re-reads the Doc (a scripted `Status: Closed` makes the phase closed at once), while an approve not offered by the phase does nothing;
         - reading `Status: Closed` sets closedOn today; the purge deletes the binder day and the PDF and sets purged only once closedOn + 5 days <= today, never for the excluded day, and canFinish stays false afterwards;
         - start() with a store whose handoffs() throws sets D10's message and days = [];
         - saveRoutine rejects a bad URL and a bad token with their messages, and saves and forgets a valid one;
         - a missing PDF gives its lastError;
         - render and store failures give their messages.
      6. Stop with status=blocked if a D10 rule leaves a day in a state with no next step (no action, and nothing a refresh does moves it), rather than adding a transition D10 does not list.
    acceptance:
      - swift test --package-path AppCore --filter HandoffControllerTests passes, and swift test --package-path AppCore passes (or the core job of tests.yml is green)
      - grep -n "This day was already sent to Claude." AppCore/Sources/Handoff/HandoffController.swift finds a line
      - grep -n "finished.pdf" AppCore/Sources/Handoff/HandoffController.swift finds a line

  - id: p7b-handoff-fixtures
    title: Add the fixture Drive and routine trigger for UI tests and previews
    depends_on: [p4-routine-trigger, p6-handoff-model-and-store]
    complexity: S
    touches:
      - AppCore/Sources/Handoff/HandoffFixtures.swift
      - AppCore/Tests/Handoff/HandoffFixturesTests.swift
    brief: |
      Implement the "Fixtures" bullet of Design D10 in docs/drive-handoff-plan.md exactly, in new file AppCore/Sources/Handoff/HandoffFixtures.swift: `actor FixtureEndOfDay`, `FixtureDrive(state:)` and `FixtureRoutineTrigger(state:credentials:)`, each public with `///` comments. Do not edit CHANGELOG.md or README.md; the last phase writes them.
      1. FixtureEndOfDay records, per date, the last step fired and whether that payload had a meeting page with a `summarySkill`. Decode the payload with JSONDecoder into a private struct holding `date`, `step` and `pages[].summarySkill`; a payload that does not decode is recorded as nothing.
      2. FixtureDrive answers per D10. The date for `exportText(ofDoc:)` is the part after "doc-".
      3. FixtureRoutineTrigger reads its credentials store on every call per D10.
      4. Tests in AppCore/Tests/Handoff/HandoffFixturesTests.swift: the status sequence without a skill (waiting → notes ready → closed), with a skill (waiting → notes ready → summary ready → closed), the IDs it returns, `notConfigured` with an empty credentials store, and an undecodable payload leaving the status at waiting.
    acceptance:
      - swift test --package-path AppCore --filter HandoffFixturesTests passes (or the core job of tests.yml is green)
      - grep -n "actor FixtureEndOfDay" AppCore/Sources/Handoff/HandoffFixtures.swift finds one line

  - id: p8-app-wiring-and-settings
    title: Wire the hand-off controller into the app, keep the routine token in the Keychain, and add the routine settings
    depends_on: [p7-handoff-controller, p7b-handoff-fixtures]
    complexity: M
    touches:
      - App/AppEnvironment.swift
      - App/MagendaApp.swift
      - App/Platform/KeychainRoutineCredentialsStore.swift
      - App/Screens/SettingsView.swift
      - AppTests/PlatformTests.swift
      - AppUITests/SettingsUITests.swift
    brief: |
      Implement the Lifecycle, Live wiring, Fixture wiring and Settings parts of Design D12 in docs/drive-handoff-plan.md exactly. Do not edit CHANGELOG.md or README.md; the last phase writes them. If an app (...) or ui (...) job of tests.yml fails on something this phase did not change, or is still queued or running 60 minutes after dispatch, re-run it once; if it is red or stuck again, stop with status=blocked and start the reason with `CI-IOS:` (see "Orchestrator: stuck or flaky iOS CI" in the plan).
      1. App/Platform/KeychainRoutineCredentialsStore.swift: copy KeychainClientCredentialsStore.swift with service "name.tkcs.magenda.routine", account "trigger", type RoutineCredentials.
      2. AppEnvironment.swift: AppServices gains `handoff: HandoffController`. Build it live and for fixtures exactly as D12 says. Fixtures use InMemoryHandoffStore and the fixture binder store already chosen. `-MagendaNoRoutine` gives an empty routine store.
      3. MagendaApp.swift: inject `.environment(services.handoff)`. In the existing `.task`, call `services.handoff.start()` after `controller.start()`. Add `@Environment(\.scenePhase)` and `.onChange(of: scenePhase)`: when it becomes `.active`, `await services.handoff.refresh(excluding: services.controller.day)`.
      4. SettingsView.swift: the "End-of-day routine" section from D12 with its exact texts and identifiers, reading `@Environment(HandoffController.self)`. Save calls `saveRoutine` and clears the fields on success.
      5. AppTests/PlatformTests.swift: a KeychainRoutineCredentialsStore round trip and delete, copying the client-credentials store test.
      6. AppUITests/SettingsUITests.swift: with `-MagendaNoRoutine`, typing an invalid URL and a token then Save shows `routineError`, and a valid URL and token then Save shows `routineStatusLabel` with "trig_". Without the argument, the status label shows trig_fixture and Forget brings back `routineURLField`.
      7. Update the SwiftUI previews that build AppServices so they still compile, injecting `handoff` where a view needs it.
      8. Stop with status=blocked if an existing SettingsUITests test fails because the new section moved what it scrolls to, and the fix would need more than adding a scroll or a waitForExistence to that test.
    acceptance:
      - the app and ui jobs of a tests.yml run dispatched on the phase branch are green
      - grep -n "name.tkcs.magenda.routine" App/Platform/KeychainRoutineCredentialsStore.swift finds a line
      - grep -n "routineStatusLabel" App/Screens/SettingsView.swift AppUITests/SettingsUITests.swift finds both files

  - id: p9-finish-day-and-review
    title: Add Finish Day to the binder and the Review list of finished days
    depends_on: [p8-app-wiring-and-settings]
    complexity: M
    touches:
      - App/Screens/BinderView.swift
      - App/Screens/AgendaView.swift
      - App/Screens/ReviewView.swift
      - AppUITests/HandoffUITests.swift
      - .github/workflows/tests.yml
      - docs/testing-policy.md
      - .claude/skills/steward/SKILL.md
    brief: |
      Implement the Finish Day and Review parts of Design D12 in docs/drive-handoff-plan.md exactly. Do not edit CHANGELOG.md or README.md; the last phase writes them. If an app (...) or ui (...) job of tests.yml fails on something this phase did not change, or is still queued or running 60 minutes after dispatch, re-run it once; if it is red or stuck again, stop with status=blocked and start the reason with `CI-IOS:` (see "Orchestrator: stuck or flaky iOS CI" in the plan).
      1. BinderView.swift: read `@Environment(HandoffController.self)`. Add the Finish Day toolbar item next to Share PDF with D12's title, image, identifier, label and enabled rule. Show `handoff.message` in the message bar after `binder.message`, identifier `handoffMessage`.
      2. New App/Screens/ReviewView.swift: per D12, with an `ID` enum (reviewDone, reviewEmpty, reviewRow(i), reviewStatus(i), reviewError(i), reviewOpenDoc(i), reviewAction(i)), accessibility labels on every button, `@Environment(\.openURL)`, `.task` and `.refreshable` refresh, and a `#Preview` using AppEnvironment.previewServices().
      3. AgendaView.swift: the Review toolbar button (D12) and its sheet.
      4. New AppUITests/HandoffUITests.swift, iPad only (skip on iPhone with the same check BinderUITests uses), launched with the fixture and `-MagendaFingerDrawing`:
         - Render, then Finish Day, then open Review: row 0's status is "Notes ready for review", and Open Doc exists.
         - Tap Approve notes: the status starts with "Closed. Handwriting is deleted on" (the standard fixture has no mapped skill, and approve re-reads the Doc).
         - With `-MagendaNoRoutine`: after Finish Day, Review shows "Uploaded, not yet sent to Claude" with the not-configured error and a Try again button.
         - Finish Day is disabled after the day was sent.
         Wait with waitForExistence; never sleep.
      5. .github/workflows/tests.yml: add `-only-testing:MagendaUITests/HandoffUITests` to the ipad `binder` shard, and `-skip-testing:MagendaUITests/HandoffUITests` to all three `rest` shards.
      6. docs/testing-policy.md and .claude/skills/steward/SKILL.md: say the binder shard runs the binder, Start over and hand-off UI tests.
      7. Stop with status=blocked if a UI test needs a Doc status the fixtures in HandoffFixtures.swift cannot produce, rather than adding test-only behavior to the app.
    acceptance:
      - the app and ui jobs, including "ui (ipad, newest, binder)", of a tests.yml run dispatched on the phase branch are green
      - grep -n "HandoffUITests" .github/workflows/tests.yml prints 4 lines
      - test -f App/Screens/ReviewView.swift

  - id: p10-retire
    title: Write ADRs 0027 to 0031, update the docs and the changelog, and delete the plan
    depends_on: [p5-summary-line-and-rules, p9-finish-day-and-review]
    complexity: M
    touches:
      - docs/adr/0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md
      - docs/adr/0028-the-end-of-day-routine-is-started-through-its-api-trigger.md
      - docs/adr/0029-the-days-google-doc-is-the-review-record.md
      - docs/adr/0030-a-closed-days-handwriting-is-deleted-five-days-later.md
      - docs/adr/0031-meeting-summaries-are-requested-by-skill.md
      - docs/adr/0013-google-sign-in-uses-pkce-with-aswebauthenticationsession.md
      - docs/adr/0014-agenda-inputs-come-live-from-google-calendar-and-google-tasks.md
      - docs/adr/0021-a-binder-day-is-stored-as-a-content-snapshot-and-ink-per-page-key.md
      - docs/adr/README.md
      - README.md
      - docs/release-testing.md
      - docs/end-of-day-handoff.md
      - docs/README.md
      - CHANGELOG.md
      - scripts/check_coverage_floor.py
      - docs/drive-handoff-plan.md
      - docs/drive-handoff-plan-manual-steps.html
    brief: |
      1. Write ADRs 0027–0031 from the "ADRs" section and the "Rejected alternatives" of docs/drive-handoff-plan.md, using docs/adr/README.md's template, Status "Accepted — <today>. Implemented.", Verification naming the files and tests the phases added. Link only to source files, ADRs and the routine API documentation URL, never to the plan.
      2. Add one Status line each, in the linked form the existing amendments use, and change nothing else in their bodies:
         - ADR 0013: "Amended by [ADR 0027](0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md): the app also asks for drive.file and writes finished days to Drive."
         - ADR 0014: "Amended by [ADR 0027](0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md): finished days are uploaded to Google Drive."
         - ADR 0021: "Amended by [ADR 0030](0030-a-closed-days-handwriting-is-deleted-five-days-later.md): a closed day's binder files are deleted five days after closure."
      3. docs/adr/README.md: add the five rows to the index.
      4. README.md:
         - "Google Cloud setup": also enable the Google Drive API, and add the third scope https://www.googleapis.com/auth/drive.file (three scopes).
         - Add a section "Finishing a day" after "Binder (iPad)": Finish Day, the Magenda folder and Doc, the routine settings, the Review list and its buttons, summary skills and the Summary line, and the five-day deletion. Cite ADRs 0027–0031 and link docs/end-of-day-handoff.md.
      5. docs/release-testing.md "Human checks": add the real-account end-of-day check (Finish Day → Drive → routine → Approve → Closed) and the offline Finish Day check.
      6. docs/end-of-day-handoff.md: replace bare ADR mentions with links to the new ADR files. docs/README.md: link docs/end-of-day-handoff.md.
      7. CHANGELOG.md under [Unreleased] (Added / Changed lines): Finish Day uploads the day to Google Drive and starts the end-of-day Claude routine; the Review list with Open Doc and approve buttons; summary skills in the rules and the Summary line on meeting pages; a closed day's handwriting is deleted five days after closure; Magenda now asks for access to the files it creates in Google Drive, so sign in again after updating.
      8. scripts/check_coverage_floor.py: add 100.0 floors with a one-line comment each for AppCore/Sources/Google/GoogleDriveClient.swift, Handoff/RoutineTrigger.swift, Handoff/DayHandoff.swift, Handoff/DocStatus.swift, Handoff/HandoffStore.swift, Handoff/HandoffController.swift, Handoff/HandoffFixtures.swift and Settings/SummarySkill.swift.
      9. Dispatch tests.yml on the branch. If an app (...) or ui (...) job of tests.yml fails on something this phase did not change, or is still queued or running 60 minutes after dispatch, re-run it once; if it is red or stuck again, stop with status=blocked and start the reason with `CI-IOS:` (see "Orchestrator: stuck or flaky iOS CI" in the plan).
      10. Delete docs/drive-handoff-plan.md and docs/drive-handoff-plan-manual-steps.html; grep the repo for "drive-handoff-plan" and remove every remaining reference.
    acceptance:
      - ls docs/adr/0027-* docs/adr/0028-* docs/adr/0029-* docs/adr/0030-* docs/adr/0031-* lists five files
      - grep -c "| \[003[01]\]\|| \[002[789]\]" docs/adr/README.md prints 5
      - grep -rn "drive-handoff-plan" --exclude-dir=.git . prints nothing
      - python3 -m unittest discover -s scripts/tests passes (includes the no-project-history guard)
      - the core job (coverage floor) of a tests.yml run dispatched on the branch is green
```
