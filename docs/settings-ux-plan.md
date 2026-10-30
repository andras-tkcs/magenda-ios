# Settings UX: calendar and look screens, title patterns, several names per person, a Drive folder picker

## Goal

Settings gets shorter and easier to use. The calendar checklist at the top and the font and colour
rows each move to a screen of their own, reached from a single row that shows the current choice
("Calendars: Work, Family", "Look: Outfit"). Under Binder rules → Meeting summaries, a rule can be
a **pattern**: a regular expression matched against the whole meeting title, so
`delivery sync [0-9]+` catches "Delivery Sync 2026" and every later instance. Under Binder rules →
People, one entry can list several names for one email ("Bob, Robert → robert@example.com"). The
Google Drive folder is no longer typed or pasted: Settings → Google Drive → Folder opens a browser
of the person's Drive, where they open folders, pick one, or create a new one. Doing that
needs the full `drive` scope, so everyone signs in again once after updating.

The request came from the maintainer in a planning session; there is no issue.

## Current state

- **Settings form** (`App/Screens/SettingsView.swift`, 618 lines). `body` (`:112`) lists, in
  order: `calendarsSection` (`:172`, one checkmark row per calendar, IDs `calendarRow.<n>`),
  `taskListsSection`, `lookSection` (`:268`, four font rows `fontOption.<pack>`, five hex rows
  `colorField.<role>`, `colorError`, `resetColorsButton`), the Binder rules link, client, Drive
  (`:376`), routine, summary routines, account, about. `ColorRole` (`:51`) and the hex helpers
  (`:300`–`:358`) serve only the look section. `Route` (`:78`) has one case, `.rules`, pushed by
  the `NavigationStack(path:)` at `:113`.
- **Drive folder** (`SettingsView.swift:376`–`:436`). A "Folder name" text field
  (`driveFolderField`, validated by `DriveFolderName.validated`, error `driveFolderError`) and an
  "Existing folder link (optional)" field (`driveFolderLinkField`, parsed by
  `DriveFolderName.folderID(from:)`), footer `driveFolderFooter`. The settings hold
  `driveFolderName` and `driveFolderID` (`AgendaSettings.swift:18`–`:21`).
  `HandoffController.runPipeline` (`HandoffController.swift:407`–`:417`) uses, for a date's first
  upload, `existingFolderID()` if set, else `drive.folderID(named: folderName())`, which finds or
  creates the folder (`GoogleDriveClient.swift:32`). Both closures are wired in
  `App/AppEnvironment.swift:100`–`:101` and `:140`–`:141`. With the `drive.file` scope a pasted
  folder that Magenda did not create is invisible to Magenda, so uploading into it fails; that
  is why the link field doesn't work in practice.
- **Scopes** (`AppCore/Sources/Google/GoogleOAuth.swift:42`–`:46`): `calendar.readonly`,
  `tasks.readonly`, `drive.file`. A stored grant without all of them makes the token
  refresh throw `.missingScopes`, which deletes the tokens and sends the person to sign-in with
  `GoogleAPIError.missingScopes.userMessage` (`GoogleAPIError.swift:34`). Tests pin the scope
  strings in `AppCore/Tests/Google/GoogleOAuthTests.swift:11`–`:12` and `:102`.
- **Summary rules** (`BinderRules.summaryRoutines: [String: [String]]`, `BinderRules.swift:18`):
  meeting title as entered → routine IDs. `SummaryRoutines.routineIDs(pageTitle:originalTitle:rules:)`
  (`SummaryRoutine.swift:78`) matches by `BinderText.fold` equality, the title sorting first winning.
  Called from `EventSelection.swift:78`, `AgendaDraft.swift:44` and `:69` (the draft keeps
  `summaryRules`, set by `AgendaBuilder.swift:32`). `AgendaSettings.removeSummaryRoutine`
  (`AgendaSettings.swift:79`) prunes rules. UI: `RulesView.summariesSection` (`RulesView.swift:232`),
  `addSummary` (`:292`).
- **People rules** (`BinderRules.personAliases: [String: String]`): `BinderText.fold(name)` →
  lowercased email. Several names for one email are already representable as several keys;
  only the UI makes it awkward: one name per Add (`RulesView.addPerson`, `:368`), one row per
  name (`peopleSection`, `:320`). Matching: `TaskSelection.attends` (`TaskSelection.swift:89`).
- **UI tests** find elements by identifier. `AppUITests/SettingsUITests.swift` drives the hex,
  font and folder rows on the settings form (`:125`–`:198`); `AppUITests/RulesUITests.swift`
  drives people and summaries (`:152`–`:230`). `scripts/ui_shards.py` keeps one timing per
  `SettingsUITests` and `RulesUITests` *method* (`CLASS_SECONDS`, `:43`–`:68`); `--check` (the
  `scripts` CI job) fails when a method has no entry or an entry names a method that is gone.
- **Coverage floors** (`scripts/check_coverage_floor.py`): `GoogleOAuth.swift`,
  `GoogleDriveClient.swift`, `SummaryRoutine.swift`, `EventSelection.swift` and `BinderText.swift`
  are at 100 %.

## Design

### D1. Calendars and Look screens

- `Route` in `SettingsView` becomes:
  ```swift
  enum Route: Hashable {
      case rules
      case calendars
      case look
      case driveFolder(DriveFolder?)   // added in p5, not p1
  }
  ```
  `.navigationDestination(for: Route.self)` switches over it.
- The first section of the settings form is one row, replacing `calendarsSection`:
  `NavigationLink(value: Route.calendars) { LabeledContent("Calendars", value: <summary>) }` with
  identifier `calendarsLink` and `.accessibilityElement(children: .combine)` on the `LabeledContent`, so the value is part of the row's label (tests read the label). The summary comes from AppCore:
  ```swift
  /// What Settings shows for the chosen calendars.
  public enum CalendarSelection {
      /// "Primary calendar" when `selectedIDs` is empty; else the titles of the calendars of
      /// `calendars` whose ID is selected, in `calendars`' order: one title, "A, B" for two, or
      /// "A, B and N more" for more; "N selected" when no selected ID names a known calendar.
      public static func summary(selectedIDs: [String], calendars: [GoogleCalendar]) -> String
  }
  ```
  in `AppCore/Sources/Settings/CalendarSelection.swift`.
- `App/Screens/CalendarsView.swift`: `struct CalendarsView: View`, navigation title "Calendars",
  a `Form` (identifier `calendarsForm`) with the old section's rows unchanged (checkmark buttons,
  `.isSelected` trait, `calendarRow.<n>`), and the same footer "None selected uses your primary
  calendar." `isSelected` and `toggleCalendar` move there. `ID` enum: `form = "calendarsForm"`,
  `calendarRow(_:)`.
- The look section is replaced, in the same place in the form, by one row:
  `NavigationLink(value: Route.look) { LabeledContent("Look", value: controller.settings.fontPack.displayName) }`
  with identifier `lookLink` and the same `.accessibilityElement(children: .combine)`.
- `App/Screens/LookView.swift`: `struct LookView: View`, navigation title "Look", a `Form`
  (identifier `lookForm`) with two sections: "Font" (the font rows) and "Colors" (the five colour
  rows and "Reset colors"). `ColorRole`, `hexDrafts`, `invalidRoles`, `colorRow`, `swatch`,
  `hexBinding`, `commitHex` and `resetHexDrafts` move there unchanged; `resetHexDrafts()` runs in
  `LookView`'s `.onAppear`. Its `ID` enum holds `form = "lookForm"`, `colorError`,
  `resetColorsButton`, `fontOption(_:)` and `colorField(_:)`, with the same strings as today.
- `SettingsView.ID` loses everything that moved and gains `calendarsLink = "calendarsLink"` and
  `lookLink = "lookLink"`. The settings view's doc comment is updated to say the calendars and the
  look are a row each.

### D2. Meeting-title patterns for summary rules

- New field `BinderRules.summaryRoutinePatterns: [String: [String]]` — a pattern as entered
  (trimmed) → routine IDs. Init parameter `summaryRoutinePatterns: [String: [String]] = [:]` after
  `summaryRoutines`; `CodingKeys` case `summaryRoutinePatterns`; decoding keeps the default `[:]`
  when missing; `BinderRules.default` has `[:]`. Settings written by an older build decode
  unchanged, and an older build ignores the key.
- `AppCore/Sources/Settings/TitlePattern.swift`:
  ```swift
  /// A meeting-title pattern: a regular expression that must match the whole title, ignoring case
  /// and accents (ADR 0052).
  public enum TitlePattern {
      /// The longest pattern accepted, in characters.
      public static let maxLength = 200
      /// What the rules screen shows when `validated` returns nil.
      public static let invalidMessage =
          "That isn't a valid pattern. Use a regular expression, like delivery sync [0-9]+."
      /// `text` trimmed of whitespace and newlines; nil when that is empty, longer than
      /// `maxLength`, or does not compile as a regular expression on its own.
      public static func validated(_ text: String) -> String?
      /// Whether `pattern` matches all of `BinderText.fold(title)`; false for a pattern that
      /// `validated` refuses.
      public static func matches(_ pattern: String, title: String) -> Bool
  }
  ```
  Implementation: `NSRegularExpression` (Foundation, works on Linux; no `Regex` literal, so no
  availability question). The pattern is first folded with
  `.folding(options: [.diacriticInsensitive], locale: nil)` only (not lowercased, so `\D`
  keeps its meaning). `validated` requires both the folded pattern and `"^(?:" + folded + ")$"` to compile (the
  wrapped form catches things like an unterminated `\Q`); `matches` compiles the wrapped form with
  `[.caseInsensitive]`, takes `let folded = BinderText.fold(title)` and returns whether
  `firstMatch` over `NSRange(folded.startIndex..., in: folded)` exists. Compile on every call; no
  `static let` cache of an `NSRegularExpression` (not `Sendable`, a Swift 6 error). Requiring the bare pattern
  to compile first means its parentheses balance, so it cannot escape the `(?:…)` wrapper.
- `SummaryRoutines.routineIDs` gains a parameter, defaulted so other callers compile:
  ```swift
  public static func routineIDs(
      pageTitle: String, originalTitle: String, rules: [String: [String]],
      patterns: [String: [String]] = [:]
  ) -> [String]
  ```
  An exact title rule still wins. Only when none matches, the first pattern in `patterns.keys.sorted()`
  that `TitlePattern.matches` against `pageTitle` or `originalTitle` gives the IDs. The same
  de-duplication applies. The doc comment says so.
- `AgendaDraft` gains `public let summaryPatterns: [String: [String]]` (doc: "The summary routine
  IDs per meeting-title pattern, see ``SummaryRoutines``."), an init parameter
  `summaryPatterns: [String: [String]] = [:]` right after `summaryRules`, and passes
  `patterns: summaryPatterns` at both `routineIDs` calls (`setTitle`, `applyShortName`). Like
  `setTitle`'s `let rules = summaryRules`, copy it to a local first (`let patterns =
  summaryPatterns`) before the mutating `update` closure, to avoid an overlapping access to `self`.
  `AgendaBuilder` passes `summaryPatterns: rules.summaryRoutinePatterns`. `EventSelection` passes
  `patterns: rules.summaryRoutinePatterns`.
- `AgendaSettings.removeSummaryRoutine(id:)` prunes `rules.summaryRoutinePatterns` exactly as it
  prunes `rules.summaryRoutines`; its doc comment names both.
- `RulesView`:
  - State `@State private var summaryIsPattern = false`.
    - The "Meeting title" field (`summaryTitleField`) gets `.autocorrectionDisabled()` and
    `.textInputAutocapitalization(.never)`, so a typed pattern is not rewritten.
  - Below the "Meeting title" field: `Toggle("Pattern", isOn: $summaryIsPattern)` with identifier
    `summaryPatternToggle`.
  - `addSummary`: after the "Choose at least one summary routine." check, when
    `summaryIsPattern`: `guard let pattern = TitlePattern.validated(summaryTitle)` else
    `summaryError = TitlePattern.invalidMessage`; if `rules.summaryRoutinePatterns[pattern] != nil`
    then `summaryError = "There is already a summary rule for that pattern."`; else save
    `$0.rules.summaryRoutinePatterns[pattern] = ids` and reset title, choices, error and
    `summaryIsPattern = false`. The non-pattern path is unchanged.
  - Rows: after the title rows, one row per pattern, sorted by pattern, text
    `"Pattern: \(pattern) → \(routineNames(ids))"`, identifier `rulesRow.summaryPatterns.<n>`,
    with the same context-menu Delete and `.onDelete` as the title rows, removing
    `settings.rules.summaryRoutinePatterns[pattern]`.
  - "Reset rules" also keeps `summaryRoutinePatterns` (`restored.summaryRoutinePatterns =
    settings.rules.summaryRoutinePatterns`).
  - Footer: "A meeting whose title matches gets these summary routines. With Pattern on, the title
    is a regular expression that must match the whole meeting title, like delivery sync [0-9]+;
    a rule for the exact title wins over a pattern. For one meeting, change them on its Edit
    sheet."

### D3. Several names for one person

Storage stays `personAliases: [String: String]`; nothing is migrated.

- In `AppCore/Sources/Settings/PersonAlias.swift`:
  ```swift
  extension PersonAlias {
      /// One alias per comma-separated name of `names`, all for `email`, in the order typed; a
      /// name repeated once folded is kept once. Empty when the email is blank or no name is left
      /// once trimmed.
      public static func aliases(names: String, email: String) -> [PersonAlias]

      /// The aliases of `personAliases` grouped by email: one group per email, sorted by email,
      /// each with its folded names sorted.
      public static func groups(_ personAliases: [String: String]) -> [PersonGroup]
  }

  /// One person of the People rules: an email and every name that stands for it.
  public struct PersonGroup: Equatable, Sendable {
      /// The lowercased email.
      public let email: String
      /// The folded names, sorted.
      public let names: [String]
      /// Creates a group.
      public init(email: String, names: [String])
  }
  ```
  `aliases` builds each entry with the existing `PersonAlias(name:email:)`.
- `RulesView.peopleSection`: rows come from `PersonAlias.groups(rules.personAliases)`, text
  `"\(group.names.joined(separator: ", ")) → \(group.email)"`, identifiers
  `rulesRow.people.<n>` as today. Deleting a row removes every key whose value is that
  email. The name field's placeholder becomes "Names in tasks". `addPerson` saves every alias of
  `PersonAlias.aliases(names: personName, email: personEmail)`, and does nothing when that is empty.
  An email already listed simply gains the names. Footer: "Matches “Name – to be discussed” tasks
  to meeting attendees whose first name differs. Separate several names for one person with commas.
  Choose from Contacts fills in a name and email you can still change."
- A single name keeps today's row text (`nora → nora.kim@example.com`), so
  `testChoosingAContactFillsThePerson` keeps passing unchanged.

### D4. Full `drive` scope and Drive folder browsing (AppCore)

- `GoogleOAuthConfiguration.scopes` becomes `calendar.readonly`, `tasks.readonly`,
  `https://www.googleapis.com/auth/drive`. `drive` covers everything `drive.file` did. A stored grant
  with `drive.file` lacks `drive`, so the existing `.missingScopes` path sends everyone to sign in
  again once; no new code is needed for that.
- `GoogleAPIError.missingScopes.userMessage` becomes "Magenda needs your calendars, your tasks and
  your Google Drive. Sign in again and allow all three."
- `AppCore/Sources/Google/DriveFolder.swift`:
  ```swift
  /// A folder in the person's Google Drive.
  public struct DriveFolder: Equatable, Hashable, Identifiable, Sendable {
      /// The ID Drive's API uses for the root of My Drive.
      public static let rootID = "root"
      /// Drive's folder ID.
      public let id: String
      /// The folder's name as Drive has it.
      public let name: String
      /// Creates a folder.
      public init(id: String, name: String)
  }

  /// Lists and creates folders in Google Drive, for the folder picker.
  public protocol DriveFolderBrowsing: Sendable {
      /// The folders directly inside `parentID` (a folder ID or `DriveFolder.rootID`), not
      /// trashed, in Drive's natural name order.
      func folders(in parentID: String) async throws -> [DriveFolder]
      /// Creates a folder called `name` inside `parentID` and returns it.
      func createFolder(named name: String, in parentID: String) async throws -> DriveFolder
  }
  ```
- `GoogleDriveClient` conforms to `DriveFolderBrowsing` (in an extension in
  `GoogleDriveClient.swift`):
  - Both methods first check `parentID == DriveFolder.rootID ||
    DriveFolderName.folderID(from: parentID) == parentID`, else throw `GoogleAPIError.notFound`
    without sending anything. That way a malformed ID never reaches the query string.
  - `folders(in:)`: `GET drive/v3/files` with query items in this order: `q` =
    `'<parentID>' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
    `spaces=drive`, `fields=nextPageToken,files(id,name)`, `orderBy=name_natural`,
    `pageSize=1000`, plus `pageToken=<token>` after the first page. It follows `nextPageToken`
    for at most 10 pages, then stops. Entries whose `id` fails `DriveFolderName.folderID(from:) == id`
    are dropped. Decoding failures throw `.unexpectedResponse`, as the client's `decode` does.
  - `createFolder(named:in:)`: `POST drive/v3/files?fields=id,name` with JSON body
    `{"mimeType":"application/vnd.google-apps.folder","name":<name>,"parents":[<parentID>]}`
    (sorted keys, through the existing `encode`). It returns the decoded `DriveFolder`; an `id`
    that fails the same check throws `.unexpectedResponse`.
  - New recorded responses in `AppCore/Tests/Google/Fixtures/`: `drive-folders-page1.json` (two
    folders, `nextPageToken: "page-2"`), `drive-folders-page2.json` (one folder, plus one entry with
    id `"bad id"` that must be dropped), `drive-folder-created.json`
    (`{"id":"folder-created-01","name":"Q4 notes"}`). All names and IDs are made up.
- `GoogleDriveClient.folderID(named:)`'s query gains `and 'me' in owners`
  (`name = '…' and mimeType = '…' and trashed = false and 'me' in owners`). Under `drive.file` only
  Magenda's own folders were visible; under `drive` the lookup would also see a `Magenda` folder
  someone shared with the person and could upload into another owner's folder. The exact-query
  assertions in `GoogleDriveClientTests` are updated.
- `AppCore/Sources/Controller/DriveFolderListing.swift`, the picker's model:
  ```swift
  /// One level of the Drive folder picker: the folders inside `parent` (My Drive when nil).
  @MainActor @Observable
  public final class DriveFolderListing {
      /// What the level shows.
      public enum State: Equatable, Sendable {
          case loading
          case loaded([DriveFolder])
          case failed(String)
      }
      /// The folder this level lists; nil for My Drive.
      public let parent: DriveFolder?
      /// What the level shows now.
      public private(set) var state: State = .loading
      /// Why the last `createFolder` failed; nil after a success or before any.
      public private(set) var createError: String?
      /// A level listing `parent` through `browser`.
      public init(parent: DriveFolder?, browser: any DriveFolderBrowsing)
      /// Lists the folders: `.loading`, then `.loaded`, or `.failed` with the
      /// `GoogleAPIError`'s `userMessage` (`GoogleAPIError.unexpectedResponse`'s for any other error).
      public func load() async
      /// Creates a folder named `text` inside this level and returns it. When
      /// `DriveFolderName.validated(text)` is nil, sets `createError` to
      /// `DriveFolderName.invalidMessage` and returns nil without asking Drive. A Drive error
      /// sets `createError` as `load` phrases it and returns nil.
      public func createFolder(named text: String) async -> DriveFolder?
  }
  ```
  `parent?.id ?? DriveFolder.rootID` is what it asks for.
- `AppCore/Sources/Google/DriveFolderFixtures.swift`: `public actor FixtureDriveFolders:
  DriveFolderBrowsing` for UI tests and previews. My Drive holds `Magenda`
  (`fixture-folder-magenda`) and `Work` (`fixture-folder-work`), in that order. `Work` holds
  `Meeting notes` (`fixture-folder-notes`). Every other folder is empty. `createFolder` appends
  a folder with ID `fixture-folder-new-<n>` (n from 1) to its parent and returns it. `public
  init() {}`.
- `AgendaSettings.init(from:)`: when the decoded `driveFolderID` is non-nil, `driveFolderName` is
  the decoded name trimmed of whitespace and newlines if that is non-empty, else
  `DriveFolderName.default`. A picked Drive folder's name may contain `/`, which
  `DriveFolderName.validated` refuses. When `driveFolderID` is nil, decoding is as today.
  `driveFolderName`'s doc comment becomes "The name of the Drive folder finished days are uploaded
  to: the picked folder's name when `driveFolderID` is set, else the folder found or created by
  this name."

### D5. The folder picker (App)

- `AppServices` (`App/AppEnvironment.swift:5`) gains `let driveFolders: any DriveFolderBrowsing`.
  The live services pass `GoogleDriveClient(sender: session)` and the fixture services pass
  `FixtureDriveFolders()`. `App/MagendaApp.swift` adds `.environment(\.driveFolders,
  services.driveFolders)` next to `contactPicker`.
- `App/Screens/DriveFolderPickerView.swift` declares
  `extension EnvironmentValues { @Entry var driveFolders: (any DriveFolderBrowsing)? }`, written the
  way `App/Platform/ContactPicker.swift:82` declares `contactPicker`, and
  ```swift
  /// One level of the Drive folder picker, pushed inside the settings sheet.
  struct DriveFolderPickerView: View {
      init(parent: DriveFolder?, browser: any DriveFolderBrowsing,
           choose: @escaping (DriveFolder) -> Void)
  }
  ```
  holding `@State private var listing: DriveFolderListing`, created in `init`. Layout:
  - Navigation title: `parent?.name ?? "My Drive"`. `.task { await listing.load() }`.
  - A `Form` with identifier `driveFolderForm`. In the first section: `.loading` → `ProgressView()`
    (`driveFolderLoading`). `.failed(message)` → the message in red (`driveFolderError`) and
    `Button("Try again")` (`driveFolderRetry`). `.loaded([])` → `Text("No folders here.")`
    (`driveFolderEmpty`). `.loaded(folders)` → one
    `NavigationLink(value: SettingsView.Route.driveFolder(folder)) { Label(folder.name, systemImage: "folder") }`
    per folder, identifier `driveFolderRow.<n>`.
  - A second section: when `parent` is non-nil, `Button("Use “\(parent.name)”")`
    (`driveFolderUseButton`) calls `choose(parent)`. Always: `Button("New folder…")`
    (`driveFolderNewButton`) opens an `.alert("New folder", …)` holding
    `TextField("Name", text: $newName)` (`driveFolderNewName`), `Button("Create")` and
    `Button("Cancel", role: .cancel)`. Create runs
    `if let folder = await listing.createFolder(named: newName) { choose(folder) }`. When it
    returns nil, `listing.createError` shows in red below the buttons (`driveFolderCreateError`).
    My Drive itself cannot be chosen.
  - `ID` enum with all identifiers above; `driveFolderRow(_ n: Int) -> String`.
  - A `#Preview` with `FixtureDriveFolders()` inside a `NavigationStack`.
- `SettingsView`:
  - `@Environment(\.driveFolders) private var driveFolders`.
  - `Route.driveFolder(DriveFolder?)`. The destination is
    `DriveFolderPickerView(parent: folder, browser: driveFolders, choose: chooseFolder)` when
    `driveFolders` is non-nil, else `Text("Google Drive isn't available.")`.
  - `chooseFolder(_ folder: DriveFolder)`: `path = []`, then
    `Task { await controller.updateSettings { $0.driveFolderID = folder.id; $0.driveFolderName = folder.name } }`.
  - `driveSection` becomes: `NavigationLink(value: Route.driveFolder(nil)) { LabeledContent("Folder", value: controller.settings.driveFolderName) }`
    (`driveFolderLink`, with `.accessibilityElement(children: .combine)` on the `LabeledContent`). When `controller.settings.driveFolderID != nil`, it also shows
    `Button("Use the default “\(DriveFolderName.default)” folder")` (`driveFolderResetButton`),
    which sets `driveFolderID = nil` and `driveFolderName = DriveFolderName.default`. Footer
    (`driveFolderFooter`), when `driveFolderID` is nil: "Finished days upload to the
    “\(name)” folder in your Google Drive, which Magenda creates when it is missing. Choose
    another folder, or make a new one, under Folder; days already uploaded stay where they are."
    When it is set: "Finished days upload to the “\(name)” folder in your Google Drive. Choose
    another folder, or make a new one, under Folder; days already uploaded stay where they are."
  - Removed: `folderDraft`, `folderInvalid`, `folderLinkDraft`, `folderLinkInvalid`,
    `commitFolder`, `commitFolderLink`, their `.onAppear` lines, and the IDs `driveFolderField`,
    `driveFolderError`, `driveFolderLinkField`.
- `HandoffController` is unchanged. A picked folder arrives through `existingFolderID` and the
  default through `folderName`, exactly as today.

No new `-MagendaOpen` case is added (ADR 0044): the Calendars and Look rows are at the top of the
form, and the Drive tests open Settings and scroll to `driveFolderLink`.

### Rejected alternatives

- **`drive.metadata.readonly` next to `drive.file`.** It lists folders, but Drive refuses to file
  into a folder the app cannot write, so a picked folder Magenda did not create would fail at
  upload. The maintainer chose the full scope.
- **The Google Picker.** It has no iOS SDK; a web view of it is a second sign-in surface (ADR 0036
  already rejected it).
- **A flat, searchable list of all folders.** Same-named folders cannot be told apart, and
  creating one has no natural parent. The maintainer chose the tree.
- **Every summary title as a regex.** Existing titles like "Sync (temp)?" would change meaning
  silently. Wildcards (`*`, `#`) are easier but cannot express the maintainer's own example
  without a second syntax. The maintainer chose an opt-in regex.
- **Swift `Regex(_:)`.** It works too, but `NSRegularExpression` takes the case-insensitive option
  without building a `Regex<AnyRegexOutput>` per match and behaves the same on Linux and iOS.
- **A new people storage shape (`email → [names]`).** The existing `name → email` map already
  holds several names per email; only the screen changes, so no migration is needed.
- **SwiftUI `Menu`s for calendars and look.** A menu closes on each tap and cannot hold the hex
  fields; pushed screens match the existing Binder rules link.

## ADRs

- **ADR 0051: Drive folders are picked from the person's Drive with the full `drive` scope.**
  Settings browses My Drive and creates folders; the app asks for `drive` instead of `drive.file`.
  Amends ADR 0027 (the scope) and ADR 0036 (the typed folder name, and its rejection of picking an
  existing folder).
- **ADR 0052: Summary rules can match meeting titles with a regular expression.** Opt-in per rule,
  whole-title, case- and accent-insensitive, exact titles win, `NSRegularExpression`. Amends
  ADR 0038's title-equality matching (the binder rules side of it).

The Calendars/Look screens and the grouped People rows are UI changes and get no ADR.

## Manual steps

There is nothing to do before implementation: every phase builds against fakes and fixtures.
After the last merge, before the PR merges (see the
[step-by-step page](https://claude.ai/artifact/BLtZtEF5vPj6Ym8tWNq5jt)):

1. **ma1:** add the `drive` scope to the Google Cloud project's consent screen.
2. **ma2:** on an iPad: sign in again, browse, pick and create a Drive folder, and finish a day into
   it.
3. **ma3:** on an iPad: check the Calendars and Look screens, a title pattern, and a person with
   several names.

## Risks and open questions

- **`NSRegularExpression` on Linux.** It is in swift-corelibs-foundation. If `swift test` on Linux
  fails to compile `TitlePattern.swift` or behaves differently from the tests' expectations
  (for example `.caseInsensitive` ignored), stop with `status=blocked` and quote the failure; do
  not switch to `Regex` on your own.
- **`@Entry` and `@Observable` in `@State`.** p5 relies on `@State private var listing` created
  in `init` (`_listing = State(initialValue: …)`). If the app target warns (warnings are errors),
  stop with `status=blocked` and quote the warning.
- **Alert text fields in UI tests.** p5's test types through
  `app.alerts.firstMatch.textFields.firstMatch`. If the alert has no text field there, stop with
  `status=blocked`; do not drop the test.
- **Re-consent.** Changing the scope signs every user out once (this is intended, D4). If
  `GoogleSessionTests` or `AgendaControllerTests` assert the old message text or the
  `drive.file` string, update them to the new strings, and nothing else in them.
- **Shared files across phases.** `scripts/ui_shards.py` is touched by p1, p2, p3 and p5, and
  `RulesView.swift` by p2 and p3. The `depends_on` chain serialises them. A worker that finds one
  of these files changed in a way its brief does not expect should stop with `status=blocked`.

## Implementation manifest

```yaml
plan_slug: settings-ux
feature_branch: feature/settings-ux
max_parallel: 2
manual_steps_artifact: https://claude.ai/artifact/BLtZtEF5vPj6Ym8tWNq5jt
manual_steps_source: docs/settings-ux-plan-manual-steps.html
manual_before: []
manual_after:
  - id: ma1-add-drive-scope
    title: Add the https://www.googleapis.com/auth/drive scope to the Google Cloud project's consent screen
    why: The app now asks for the full drive scope; the consent screen of the person's own Google client must list it (CI has no Google account).
  - id: ma2-pick-and-create-folder-on-ipad
    title: On an iPad, sign in again, pick an existing Drive folder, create a new one, and finish a day into it
    why: Proves the re-consent, the live Drive listing and creation, and that an upload lands in a folder Magenda did not create, none of which CI can reach.
  - id: ma3-settings-screens-on-ipad
    title: On an iPad, check the Calendars and Look screens, a title pattern rule, and a person with several names
    why: How the new screens and rows read and feel on a real device, at a large Dynamic Type size.
verify_after_merge:
  - swift test --package-path AppCore
  - python3 -m unittest discover -s scripts/tests
  - python3 scripts/ui_shards.py --check
final_checks:
  - docs/settings-ux-plan.md and docs/settings-ux-plan-manual-steps.html are deleted and nothing links to them
  - docs/adr/0051-drive-folders-are-picked-with-the-full-drive-scope.md exists, is Accepted, and is in docs/adr/README.md
  - docs/adr/0052-summary-rules-can-match-titles-with-a-regular-expression.md exists, is Accepted, and is in docs/adr/README.md
  - CHANGELOG.md has [Unreleased] entries and no version heading
phases:
  - id: p1-calendars-and-look-screens
    title: Move the calendar checklist and the font and colour rows to screens of their own
    depends_on: []
    complexity: M
    touches:
      - App/Screens/SettingsView.swift
      - App/Screens/CalendarsView.swift
      - App/Screens/LookView.swift
      - AppCore/Sources/Settings/CalendarSelection.swift
      - AppCore/Tests/Settings/CalendarSelectionTests.swift
      - AppUITests/SettingsUITests.swift
      - scripts/ui_shards.py
    brief: |
      Implement Design D1 of docs/settings-ux-plan.md exactly.
      1. Create AppCore/Sources/Settings/CalendarSelection.swift with `public enum CalendarSelection`
         and `summary(selectedIDs:calendars:)` as specified in D1, with `///` docs on every public
         declaration.
      2. Create AppCore/Tests/Settings/CalendarSelectionTests.swift (Swift Testing, opening comment
         naming what it tests, one `@Suite("Calendar selection summary")`). Cover: empty selection
         -> "Primary calendar"; one -> its title; two -> "A, B" in `calendars` order, not selection
         order; three -> "A, B and 1 more"; four -> "A, B and 2 more"; unknown IDs ignored when at
         least one is known; only unknown IDs -> "2 selected". Use
         `GoogleCalendar(id:title:isPrimary:)`.
      3. Create App/Screens/CalendarsView.swift: move the calendar rows, `isSelected`,
         `toggleCalendar` and the footer from SettingsView's `calendarsSection`, as D1 says. Add the
         `ID` enum, `.navigationTitle("Calendars")`, `.navigationBarTitleDisplayMode(.inline)`, and a
         `#Preview` built like SettingsView's (AppEnvironment.previewServices, inside a
         NavigationStack).
      4. Create App/Screens/LookView.swift: move `ColorRole`, the hex state and helpers, the font
         rows, the colour rows and "Reset colors" from SettingsView, as D1 says ("Font" and
         "Colors" sections, `resetHexDrafts()` in `.onAppear`). Add the `ID` enum,
         `.navigationTitle("Look")`, `.navigationBarTitleDisplayMode(.inline)`, a `#Preview`.
      5. In App/Screens/SettingsView.swift: add `case calendars, look` to `Route`. Make
         `.navigationDestination(for: Route.self)` a `switch` (`.rules` -> RulesView(),
         `.calendars` -> CalendarsView(), `.look` -> LookView()). Replace `calendarsSection` and
         `lookSection` with the two NavigationLink rows of D1 (`calendarsLink`, `lookLink`; the
         calendars summary from `CalendarSelection.summary(selectedIDs: controller.settings.calendarIDs,
         calendars: controller.calendars)`). Remove the moved IDs, state, `ColorRole` and helpers,
         and the `resetHexDrafts()` call in `.onAppear`. Update the type's doc comment.
      6. AppUITests/SettingsUITests.swift: add a helper `openLook(_ app:)` that reveals and taps
         `lookLink` (retrying a dropped tap like `openSettings` does) and waits for `lookForm`. Add
         `lookForm(_ app:)` returning `app.element("lookForm")`. In
                  `testAnInvalidHexShowsAnErrorAndAValidOneClearsIt`, `testResetColorsRestoresTheDefaults` and
         `testChoosingAFontAndRenderingReachesThePreview`, call `openLook(app)` right after launch and
         reveal elements in `lookForm(app)` instead of `settingsForm(app)`. The private helper
         `enterHex` hard-codes `settingsForm(app)` and `belowNavigationBar(app)`, which reads the
         `settingsDone` button; that button is gone once Look is pushed. Give `enterHex` two
         parameters, `container: XCUIElement` and `top: CGFloat`; the Look tests pass
         `lookForm(app)` and `app.navigationBars["Look"].frame.maxY + 60`, and
         `testAFolderNameIsSavedAndAnInvalidOneShowsAnError` passes `settingsForm(app)` and
         `belowNavigationBar(app)` (p5 deletes it). Add a helper `goBack(_ app:, from title: String)`
         that taps `app.navigationBars[title].buttons.firstMatch` until `settingsDone` exists (the
         loop `RulesUITests.closeSettings` uses); never `app.navigationBars.buttons.firstMatch`,
         which can be an agenda button. In the font test, after tapping the option, call
         `goBack(app, from: "Look")` before `closeSettings(app)`. Add "the navigation back button"
         to the file header's list of elements found by text. Keep the method names. Add
         `testTheCalendarsScreenChoosesACalendar`: launch into settings, assert `calendarsLink`'s
         label contains "Primary calendar", tap it, wait for `calendarsForm`, tap `calendarRow.1`
         (the fixture's "Family"), `goBack(app, from: "Calendars")`, and wait until `calendarsLink`'s
         label contains "Family".
      7. scripts/ui_shards.py: add
         `"MagendaUITests/SettingsUITests/testTheCalendarsScreenChoosesACalendar": 60,` in
         alphabetical position among the SettingsUITests entries. Run
         `python3 scripts/ui_shards.py --check`.
      8. Run `swift test --package-path AppCore --filter CalendarSelectionTests`, `swift format lint
         --strict` over the paths in docs/coding-and-testing-guidelines.md, and dispatch tests.yml
         with `only: MagendaUITests/SettingsUITests,MagendaUITests/LaunchOptionsUITests` per
         .claude/skills/steward/SKILL.md; read its result.
      Do not touch CHANGELOG.md; the last phase writes it.
      Stop with status=blocked if the fixture calendar at index 1 is not "Family"
      (AppCore/Sources/Controller/GoogleFixtures.swift `calendars()`), or if any other UI test class
      references an identifier you moved.
    acceptance:
      - swift test --package-path AppCore --filter CalendarSelectionTests passes with at least 7 tests
      - grep -c 'calendarRow\|fontOption\|colorField\|resetColorsButton' App/Screens/SettingsView.swift prints 0
      - grep -q 'case calendars' App/Screens/SettingsView.swift && grep -q 'case look' App/Screens/SettingsView.swift
      - python3 scripts/ui_shards.py --check exits 0
      - swift format lint --strict --parallel --recursive App AppTests AppUITests AppCore/Package.swift AppCore/Sources AppCore/Tests exits 0
            - the dispatched tests.yml `ui (ipad, newest, only)` job for SettingsUITests and LaunchOptionsUITests is green

  - id: p4-drive-scope-and-folder-browsing
    title: Ask for the full drive scope and list and create Drive folders in AppCore
    depends_on: []
    complexity: M
    touches:
      - AppCore/Sources/Google/GoogleOAuth.swift
      - AppCore/Sources/Google/GoogleAPIError.swift
      - AppCore/Sources/Google/GoogleDriveClient.swift
      - AppCore/Sources/Google/DriveFolder.swift
      - AppCore/Sources/Google/DriveFolderFixtures.swift
      - AppCore/Sources/Controller/DriveFolderListing.swift
      - AppCore/Sources/Settings/AgendaSettings.swift
      - AppCore/Tests/Google/GoogleOAuthTests.swift
      - AppCore/Tests/Google/GoogleAPIErrorTests.swift
      - AppCore/Tests/Google/GoogleDriveClientTests.swift
      - AppCore/Tests/Google/DriveFolderFixturesTests.swift
      - AppCore/Tests/Google/Fixtures/drive-folders-page1.json
      - AppCore/Tests/Google/Fixtures/drive-folders-page2.json
      - AppCore/Tests/Google/Fixtures/drive-folder-created.json
      - AppCore/Tests/Controller/DriveFolderListingTests.swift
      - AppCore/Tests/Controller/AgendaControllerTests.swift
      - AppCore/Tests/Settings/AgendaSettingsTests.swift
      - AppCore/Tests/Support/FakeDriveFolders.swift
      - scripts/check_coverage_floor.py
      - README.md
      - docs/end-of-day-handoff.md
    brief: |
      Implement Design D4 of docs/settings-ux-plan.md exactly. AppCore only; no App/ file changes.
      1. GoogleOAuth.swift: replace the `drive.file` scope with
         "https://www.googleapis.com/auth/drive" in `GoogleOAuthConfiguration.scopes`.
         GoogleAPIError.swift: set `.missingScopes`' `userMessage` to the D4 string.
      2. Update the tests that pin the old strings: GoogleOAuthTests.swift (`driveScope` at the top
         and the test display name "The scopes are calendar, tasks and drive.file" -> "... and
         drive"). Run `grep -rnF 'auth/drive.file' AppCore/Tests` and `grep -rnF 'the files it creates in Google Drive'
         AppCore/Tests` and update every hit to the new scope or message, and nothing else in those
         tests (the hits are GoogleOAuthTests.swift:11 and :102, GoogleAPIErrorTests.swift:16 and
         AgendaControllerTests.swift:528; do not use a regex `drive.file`, it matches the fixture
         names `drive-files-list` and `drive-file-id`).
      3. Create AppCore/Sources/Google/DriveFolder.swift with `DriveFolder` and
         `DriveFolderBrowsing` as in D4.
      4. GoogleDriveClient.swift: add `extension GoogleDriveClient: DriveFolderBrowsing` with
         `folders(in:)` and `createFolder(named:in:)` exactly as D4 specifies (parent check,
         query items and their order, pagination limit of 10 pages, dropping bad IDs, POST body).
         Reuse `Self.filesURL`, `Self.folderType`, `Self.jsonType`, `GoogleAPI.withQuery`, `decode` and
         `encode`. Leave the `private` helpers and constants `private`: an extension in the same file
         sees them. The POST body is the file's existing private `Metadata` struct
         (`Metadata(mimeType: Self.folderType, name: name, parents: [parentID])`). Also add
         `and 'me' in owners` to `folderID(named:)`'s query and update its exact-query assertions
         in GoogleDriveClientTests.swift (D4).
      5. Add the three JSON fixtures named in D4 under AppCore/Tests/Google/Fixtures/ (copy the
         shape of drive-files-list.json; add `"name"` and, on page 1, `"nextPageToken": "page-2"`).
      6. Extend AppCore/Tests/Google/GoogleDriveClientTests.swift (FakeSender, `enqueue(fixture:)`):
         the exact listing request for the root (method, path, each query item); a second page
         request carries `pageToken=page-2`; folders from both pages in order, the bad ID dropped;
         a listing that keeps returning a `nextPageToken` stops after 10 requests; the POST create
         request (method, `fields=id,name`, Content-Type, exact JSON body) and its decoded result;
         a created folder with a bad ID throws `.unexpectedResponse`; a malformed parent ID (for example
         `"a' or 'b"`) throws `.notFound` and sends no request, for both methods. Keep the file at
         100 % line coverage (its floor in scripts/check_coverage_floor.py).
      7. Create AppCore/Sources/Google/DriveFolderFixtures.swift with `FixtureDriveFolders` as in
         D4, and AppCore/Tests/Google/DriveFolderFixturesTests.swift covering: the root's two
         folders, Work's one folder, an unknown parent's empty list, and a created folder that then
         appears in its parent's list with ID `fixture-folder-new-1`.
      8. Create AppCore/Tests/Support/FakeDriveFolders.swift: an `actor FakeDriveFolders:
         DriveFolderBrowsing` that records calls (`enum Call: Equatable { case folders(in: String);
         case createFolder(named: String, in: String) }`), and answers with a scripted list, created
         folder, or error per method, in the style of AppCore/Tests/Support/FakeDrive.swift.
      9. Create AppCore/Sources/Controller/DriveFolderListing.swift as in D4, and
         AppCore/Tests/Controller/DriveFolderListingTests.swift (`@MainActor` tests with
         FakeDriveFolders): it asks for `root` with no parent and for the parent's ID with one; a
         success becomes `.loaded`; a `GoogleAPIError.network` becomes `.failed` with its
         `userMessage`; a non-Google error becomes `.failed` with `.unexpectedResponse`'s message;
         `load()` after a failure can succeed; `createFolder` with "a/b" sets `createError` to
         `DriveFolderName.invalidMessage`, returns nil, and makes no call; a valid name is trimmed,
         sent with the parent ID, returned, and clears `createError`; a Drive error sets
         `createError` and returns nil.
      10. AgendaSettings.swift: change `init(from:)` and the `driveFolderName` doc comment as D4
          says. Extend AgendaSettingsTests.swift: a stored ID with the name "Q4/2026" decodes with
          that name; a stored ID with a blank name decodes as "Magenda"; no ID with "a/b" still
          decodes as "Magenda".
      11. scripts/check_coverage_floor.py: add 100.0 floors, each with a one-line comment in the
          style of the others, for AppCore/Sources/Google/DriveFolder.swift, AppCore/Sources/Google/DriveFolderFixtures.swift and
          AppCore/Sources/Controller/DriveFolderListing.swift.
      12. Docs: README.md "Google Cloud setup" step 3 lists
          `https://www.googleapis.com/auth/drive` instead of `drive.file`. Change the parenthesis to
          "(Magenda lists your Drive's folders so you can pick one, and writes only the day's PDF
          and Doc; ADR 0051). Google lists `drive` as a restricted scope: keep the client in Testing
          or Internal, as above, because an External client in production needs Google's
          verification". docs/end-of-day-handoff.md line "Magenda creates everything below
          with the `drive.file` scope, so it only ever sees files it made." becomes "Magenda files
          everything below with the `drive` scope (ADR 0051), and creates only the files and
          folders listed here." ADR 0051 is written by the last phase; the link may dangle until
          then.
      13. Run `swift test --package-path AppCore --enable-code-coverage`, then
          `python3 scripts/check_coverage_floor.py "$(swift test --package-path AppCore --show-codecov-path)"`,
          then swift format lint --strict and `python3 -m unittest discover -s scripts/tests`, and
          dispatch tests.yml with `only: MagendaUITests/LaunchOptionsUITests,MagendaUITests/HandoffUITests`
          (steward: any AppCore change runs a simulator).
      Do not touch CHANGELOG.md. Stop with status=blocked if HandoffController or the hand-off
      tests need any change: D4 says they don't.
    acceptance:
      - swift test --package-path AppCore passes
      - python3 scripts/check_coverage_floor.py "$(swift test --package-path AppCore --show-codecov-path)" exits 0
      - grep -rn 'auth/drive.file' AppCore README.md docs/end-of-day-handoff.md prints nothing
      - "grep -q 'extension GoogleDriveClient: DriveFolderBrowsing' AppCore/Sources/Google/GoogleDriveClient.swift"
      - grep -q "'me' in owners" AppCore/Sources/Google/GoogleDriveClient.swift
      - swift test --package-path AppCore --filter 'DriveFolderListingTests|DriveFolderFixturesTests|GoogleDriveClientTests' passes
            - python3 -m unittest discover -s scripts/tests passes
      - swift format lint --strict --parallel --recursive App AppTests AppUITests AppCore/Package.swift AppCore/Sources AppCore/Tests exits 0
      - the dispatched tests.yml `ui (ipad, newest, only)` job for LaunchOptionsUITests and HandoffUITests is green

  - id: p2-summary-title-patterns
    title: Let a summary rule match meeting titles with a regular expression
    depends_on: [p1-calendars-and-look-screens, p4-drive-scope-and-folder-browsing]
    complexity: M
    touches:
      - AppCore/Sources/Settings/TitlePattern.swift
      - AppCore/Sources/Settings/BinderRules.swift
      - AppCore/Sources/Settings/SummaryRoutine.swift
      - AppCore/Sources/Settings/AgendaSettings.swift
      - AppCore/Sources/Draft/AgendaDraft.swift
      - AppCore/Sources/Draft/AgendaBuilder.swift
      - AppCore/Sources/Draft/EventSelection.swift
      - AppCore/Tests/Settings/TitlePatternTests.swift
      - AppCore/Tests/Settings/SummaryRoutineTests.swift
      - AppCore/Tests/Settings/AgendaSettingsTests.swift
      - AppCore/Tests/Draft/AgendaDraftTests.swift
      - AppCore/Tests/Draft/AgendaBuilderTests.swift
      - AppCore/Tests/Draft/EventSelectionTests.swift
      - App/Screens/RulesView.swift
      - AppUITests/RulesUITests.swift
      - scripts/ui_shards.py
      - scripts/check_coverage_floor.py
    brief: |
      Implement Design D2 of docs/settings-ux-plan.md exactly.
      1. Create AppCore/Sources/Settings/TitlePattern.swift as in D2 (NSRegularExpression, the
         diacritic-only fold of the pattern, `validated` compiling the bare pattern, `matches`
         compiling `^(?:…)$` case-insensitively against `BinderText.fold(title)`).
      2. Create AppCore/Tests/Settings/TitlePatternTests.swift: `validated` trims, refuses "",
         "   ", a 201-character pattern, "delivery sync [0-9", "a)|(b"; accepts
         "delivery sync [0-9]+". `matches`: "delivery sync [0-9]+" matches "Delivery Sync 2026"
         and "delivery  sync 7" (whitespace folded in the title), not "Delivery Sync" nor
         "Delivery Sync 2026 prep" (whole title); "réunion .*" matches "Reunion lundi" and
         "RÉUNION lundi"; `\D+` matches "abc" and not "ab1" (the pattern is not lowercased);
         an invalid pattern matches nothing.
      3. BinderRules.swift: add `summaryRoutinePatterns` as D2 says (property with `///` doc, init
         parameter, `default`, CodingKeys, decoding). Add to AgendaSettingsTests.swift (where
         the BinderRules decoding tests live) that rules JSON without the key decodes to `[:]` and
         that a value round-trips.
      4. SummaryRoutine.swift: add the `patterns:` parameter to `SummaryRoutines.routineIDs` as D2
         says, and update its doc comment. Extend SummaryRoutineTests.swift: a pattern matches
         when no title rule does; a title rule wins over a matching pattern; with two matching
         patterns the one sorting first wins; a pattern can match the original title when the page
         title differs; duplicate IDs collapse. Keep SummaryRoutine.swift at 100 %.
      5. AgendaDraft.swift, AgendaBuilder.swift, EventSelection.swift: thread `summaryPatterns` /
         `patterns:` exactly as D2 says. Extend AgendaDraftTests.swift (`setTitle` to a title that
         only a pattern matches picks up the pattern's IDs), AgendaBuilderTests.swift
         (`draft.summaryPatterns` equals `rules.summaryRoutinePatterns`) and EventSelectionTests.swift
         (an event whose title only a pattern matches gets its IDs).
      6. AgendaSettings.swift: `removeSummaryRoutine(id:)` prunes `rules.summaryRoutinePatterns` too;
         extend its test in AgendaSettingsTests.swift.
      7. App/Screens/RulesView.swift: everything in D2's RulesView bullet (toggle, addSummary
         branch, pattern rows with delete, Reset rules keeping patterns, footer). Add
         `summaryPatternToggle` to `ID`.
      8. AppUITests/RulesUITests.swift: extend the private `addSummary` helper with a
         `pattern: Bool = false` parameter that turns `summaryPatternToggle` on (the same
         `tapSwitch` loop as the routine choice) before tapping Add. Add
         `testAddingATitlePatternShowsItsRow` (title "delivery sync [0-9]+", tick first routine,
         pattern on; `rulesRow.summaryPatterns.0` appears and its label contains "Client memo") and
         `testAnInvalidPatternShowsAnError` (title "delivery sync [0-9", tick first, pattern on;
         `summaryError` appears).
      9. scripts/ui_shards.py: add `"MagendaUITests/RulesUITests/testAddingATitlePatternShowsItsRow": 110,`
         and `"MagendaUITests/RulesUITests/testAnInvalidPatternShowsAnError": 70,` in alphabetical
         position. scripts/check_coverage_floor.py: add a 100.0 floor for
         AppCore/Sources/Settings/TitlePattern.swift with a one-line comment ("Matches meeting titles
         against summary-rule patterns; a wrong match starts the wrong routine.").
      10. Run the AppCore tests with coverage and the floor check, swift format lint --strict,
          `python3 scripts/ui_shards.py --check`, and dispatch tests.yml with
          `only: MagendaUITests/RulesUITests,MagendaUITests/LaunchOptionsUITests`.
      Do not touch CHANGELOG.md. Stop with status=blocked if NSRegularExpression is unavailable or
      behaves differently on Linux than the step-2 tests expect.
    acceptance:
      - swift test --package-path AppCore --filter 'TitlePatternTests|SummaryRoutineTests|AgendaDraftTests|EventSelectionTests|AgendaBuilderTests|AgendaSettingsTests' passes
      - python3 scripts/check_coverage_floor.py "$(swift test --package-path AppCore --enable-code-coverage --show-codecov-path)" exits 0 after a coverage run
            - grep -q 'summaryRoutinePatterns' AppCore/Sources/Settings/BinderRules.swift && grep -q 'summaryRoutinePatterns' App/Screens/RulesView.swift && grep -q 'summaryRoutinePatterns' AppCore/Sources/Settings/AgendaSettings.swift
      - grep -q 'summaryPatternToggle' App/Screens/RulesView.swift && grep -q 'summaryPatternToggle' AppUITests/RulesUITests.swift
      - python3 scripts/ui_shards.py --check exits 0
      - the dispatched tests.yml `ui (ipad, newest, only)` job for RulesUITests and LaunchOptionsUITests is green

  - id: p3-several-names-per-person
    title: Let one People entry hold several names for one email
    depends_on: [p2-summary-title-patterns]
    complexity: S
    touches:
      - AppCore/Sources/Settings/PersonAlias.swift
      - AppCore/Tests/Settings/PersonAliasTests.swift
      - App/Screens/RulesView.swift
      - AppUITests/RulesUITests.swift
      - scripts/ui_shards.py
      - scripts/check_coverage_floor.py
    brief: |
      Implement Design D3 of docs/settings-ux-plan.md exactly.
      1. AppCore/Sources/Settings/PersonAlias.swift: add `PersonGroup` and the
         `PersonAlias.aliases(names:email:)` and `PersonAlias.groups(_:)` statics as D3 says.
      2. AppCore/Tests/Settings/PersonAliasTests.swift: `aliases` splits "Bob, Robert ,bobby" into
         three aliases `bob`, `robert`, `bobby` with the email lowercased and trimmed; drops empty
         pieces (", Bob,,"); keeps "Bob, bob, BÓB" once (`bob`); returns [] for a blank email or
         for names ", ,". `groups` of `["bob": "r@x.com", "robert": "r@x.com", "nora": "n@x.com"]`
         is `[PersonGroup(email: "n@x.com", names: ["nora"]), PersonGroup(email: "r@x.com",
         names: ["bob", "robert"])]`; of `[:]` is [].
            2b. In the same file change `PickedContact.suggestedName`'s doc comment from "Name in tasks" to
         "Names in tasks".
      3. App/Screens/RulesView.swift `peopleSection`, `deletePeople` and `addPerson`: as D3 says
         (grouped rows, delete by email, "Names in tasks", save every alias, new footer).
      4. AppUITests/RulesUITests.swift: add `testAddingSeveralNamesForOneEmailShowsOneRow`: enter
         "Bob, Robert\n" in `peopleName` and "robert@example.com\n" in `peopleEmail`, tap
         `peopleAdd` with the same retry loop as `testAddingAPersonShowsTheAlias`, and wait until
         `rulesRow.people.0`'s label is "bob, robert → robert@example.com" and
         `rulesRow.people.1` does not exist.
      5. scripts/ui_shards.py: add
         `"MagendaUITests/RulesUITests/testAddingSeveralNamesForOneEmailShowsOneRow": 90,` in
         alphabetical position. scripts/check_coverage_floor.py: add a 100.0 floor for
         AppCore/Sources/Settings/PersonAlias.swift with the comment "Turns typed names into People
         rules and groups them by email; a wrong split matches a task to the wrong person." if
         `swift test --enable-code-coverage` shows it at 100 % after step 2; otherwise add the
         missing tests first.
      6. Run the AppCore tests with coverage and the floor check, swift format lint --strict,
         `python3 scripts/ui_shards.py --check`, and dispatch tests.yml with
         `only: MagendaUITests/RulesUITests,MagendaUITests/LaunchOptionsUITests`.
      Do not touch CHANGELOG.md. Stop with status=blocked if `testChoosingAContactFillsThePerson`
      fails: D3 says a single name keeps its row text.
    acceptance:
      - swift test --package-path AppCore --filter PersonAliasTests passes
      - grep -q 'PersonAlias.groups' App/Screens/RulesView.swift && grep -q 'PersonAlias.aliases' App/Screens/RulesView.swift
      - python3 scripts/ui_shards.py --check exits 0
      - python3 scripts/check_coverage_floor.py "$(swift test --package-path AppCore --enable-code-coverage --show-codecov-path)" exits 0 after a coverage run
      - the dispatched tests.yml `ui (ipad, newest, only)` job for RulesUITests and LaunchOptionsUITests is green

  - id: p5-drive-folder-picker
    title: Replace the folder name and link fields with a Drive folder picker
    depends_on: [p1-calendars-and-look-screens, p3-several-names-per-person, p4-drive-scope-and-folder-browsing]
    complexity: M
    touches:
      - App/AppEnvironment.swift
      - App/MagendaApp.swift
      - App/Screens/SettingsView.swift
      - App/Screens/DriveFolderPickerView.swift
      - AppUITests/SettingsUITests.swift
      - scripts/ui_shards.py
      - docs/end-of-day-handoff.md
      - README.md
    brief: |
      Implement Design D5 of docs/settings-ux-plan.md exactly. p4 already added DriveFolder,
      DriveFolderBrowsing, DriveFolderListing and FixtureDriveFolders to AppCore; use them as they
      are.
      1. App/AppEnvironment.swift: add `driveFolders` to `AppServices` and pass
         `FixtureDriveFolders()` in the fixture branch and `GoogleDriveClient(sender: session)` in
         the live branch. App/MagendaApp.swift: add `.environment(\.driveFolders,
         services.driveFolders)` after the `contactPicker` line.
      2. Create App/Screens/DriveFolderPickerView.swift with the `@Entry` and the view exactly as D5
         lays out (title, `.task`, the four states, rows, Use and New folder buttons, the alert,
         `createError`, the `ID` enum, `#Preview`). Every button has a label VoiceOver reads
         (the visible text is enough); the folder icon is decorative.
      3. App/Screens/SettingsView.swift: add `case driveFolder(DriveFolder?)` to `Route`, the
         destination, `chooseFolder`, the new `driveSection` with the two footers and the reset
         button, and remove the old fields, state, helpers and IDs, as D5 says. Add `driveFolderLink` and `driveFolderResetButton` to `ID`. Add
         `.environment(\.driveFolders, services.driveFolders)` to SettingsView's `#Preview`. The picker's
         own `#Preview` cannot push rows (no destination for `Route`); that is acceptable.
      4. AppUITests/SettingsUITests.swift: delete `testAFolderNameIsSavedAndAnInvalidOneShowsAnError`.
         Add `testChoosingADriveFolderShowsItInSettings`: reveal `driveFolderFooter` and assert it
         contains "“Magenda”"; reveal and tap `driveFolderLink`; wait for `driveFolderRow.1` (Work)
         and tap it; wait for `driveFolderUseButton` and tap it; wait until `driveFolderLink`'s label
         contains "Work" and `driveFolderResetButton` exists; tap the reset button and wait until
         the link's label contains "Magenda". Add `testCreatingADriveFolderUsesIt`: tap
         `driveFolderLink`, tap `driveFolderRow.1`, tap `driveFolderNewButton`, wait for
         `app.alerts.firstMatch.textFields.firstMatch` (the alert's field is first responder as soon
         as it shows; do not rely on the identifier), `app.typeText("Q4 notes")`, tap
         `app.alerts.buttons["Create"]`, and wait until `driveFolderLink`'s label contains
         "Q4 notes". Reuse the file's reveal/retry helpers; no sleeps.
      5. scripts/ui_shards.py: remove the
         `testAFolderNameIsSavedAndAnInvalidOneShowsAnError` entry and add
         `"MagendaUITests/SettingsUITests/testChoosingADriveFolderShowsItInSettings": 90,` and
         `"MagendaUITests/SettingsUITests/testCreatingADriveFolderUsesIt": 90,` in alphabetical
         position.
      6. Docs: docs/end-of-day-handoff.md Drive layout table, Folder row: "the folder picked under
         Settings → Google Drive → Folder, or `Magenda` when none is picked | anywhere in the
         person's Drive; `Magenda` is created in the root when missing". README.md line 77: "…
         folder in your Drive, `Magenda` unless you pick or create another under Settings →
         Google Drive → Folder (ADR 0051)."
      7. Run `swift format lint --strict`, `python3 scripts/ui_shards.py --check`,
         `python3 -m unittest discover -s scripts/tests`, and dispatch tests.yml with
         `only: MagendaUITests/SettingsUITests,MagendaUITests/LaunchOptionsUITests,MagendaUITests/HandoffUITests`.
      Do not touch CHANGELOG.md or anything under AppCore/. Stop with status=blocked if a
      HandoffUITests test depended on `driveFolderField`, or if the app target emits a warning
      about `@State` holding `DriveFolderListing`.
    acceptance:
      - grep -c 'driveFolderField\|driveFolderLinkField\|commitFolderLink' App/Screens/SettingsView.swift prints 0
      - grep -q 'case driveFolder(DriveFolder?)' App/Screens/SettingsView.swift
            - grep -q 'driveFolders' App/AppEnvironment.swift && grep -q 'driveFolders' App/MagendaApp.swift
      - python3 scripts/ui_shards.py --check exits 0
      - swift format lint --strict --parallel --recursive App AppTests AppUITests AppCore/Package.swift AppCore/Sources AppCore/Tests exits 0
      - the dispatched tests.yml `ui (ipad, newest, only)` job for SettingsUITests, LaunchOptionsUITests and HandoffUITests is green

  - id: p6-retire-plan
    title: Write ADRs 0051 and 0052, update docs and the changelog, delete the plan
    depends_on: [p5-drive-folder-picker]
    complexity: S
    touches:
      - docs/adr/0051-drive-folders-are-picked-with-the-full-drive-scope.md
      - docs/adr/0052-summary-rules-can-match-titles-with-a-regular-expression.md
      - docs/adr/0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md
      - docs/adr/0036-finished-days-upload-to-a-drive-folder-named-in-settings.md
      - docs/adr/0038-summaries-are-written-by-dedicated-summary-routines-that-magenda-starts.md
      - docs/adr/README.md
      - README.md
      - docs/end-of-day-handoff.md
      - docs/release-testing.md
      - CHANGELOG.md
      - docs/settings-ux-plan.md
      - docs/settings-ux-plan-manual-steps.html
    brief: |
      1. Check `ls docs/adr` for the next free numbers. If 0051 or 0052 is taken, use the next free
         ones, and use them everywhere below and in every `ADR 0051`/`ADR 0052` reference p4 and p5
         wrote (`grep -rn 'ADR 005[12]' README.md docs`).
      2. Write docs/adr/0051-drive-folders-are-picked-with-the-full-drive-scope.md from the
         template in docs/adr/README.md. Status "Accepted — <today>. Implemented.", plus
         "Amends [ADR 0027](…): the drive.file scope." and "Amends [ADR 0036](…): the folder is
         picked, not named." Context: drive.file hides folders Magenda did not create, so a pasted
         link failed at upload, and typing names was error-prone. Decision: D4's scope and
         D5's picker; the default `Magenda` folder when none is picked; HandoffController
         unchanged. Alternatives: the plan's "Rejected alternatives" bullets on
         drive.metadata.readonly, the Google Picker and the flat list. Consequences: everyone signs
         in again once; Magenda can now read the whole Drive, though it only lists folders and
         writes its own files; the by-name lookup can now find a `Magenda` folder the person made, and is limited to folders
         they own (`'me' in owners`) so a shared one is never used; `drive` is a restricted scope,
         so an External client in production would need Google's verification (Testing and Internal
         clients do not).
         Verification: the source and test files p4 and p5 created or changed.
      3. Write docs/adr/0052-summary-rules-can-match-titles-with-a-regular-expression.md: Status
         Accepted, "Amends [ADR 0038](…): rules match exact titles or patterns". Decision is D2:
         opt-in per rule, whole title, case- and accent-insensitive, exact title wins, first
         pattern by sort order, NSRegularExpression, stored in `summaryRoutinePatterns`.
         Alternatives: the plan's bullets on every title as a regex, wildcards, and Swift Regex.
      4. Add one Status line to ADR 0027, 0036 and 0038 each: "Amended by [ADR 0051](…): …" /
         "Amended by [ADR 0052](…): …" (Status section only; ADR rule 2). Add both ADRs to the
         index in docs/adr/README.md.
      5. README.md: in the binder rules bullets, mention that a summary rule can be a pattern (the
         Meeting summaries sentence near line 101) and that People takes several names separated
         by commas (near line 48). Check docs/release-testing.md for a manual Drive/sign-in check
         that mentions `drive.file` or the folder name field, and update it to the picker.
      6. CHANGELOG.md, under `## [Unreleased]`, `### Added` and `### Changed`, written for people
         who use the app:
         Added: "Binder rules → Meeting summaries: a rule can be a pattern (a regular expression,
         like `delivery sync [0-9]+`) that matches every meeting whose title fits it."
         Added: "Binder rules → People: one entry can hold several names for the same person,
         separated by commas."
         Changed: "Settings → Google Drive → Folder now opens your Drive: open folders, pick one, or
         make a new one. Magenda now asks for access to your Google Drive, so sign in again once
         after updating."
         Changed: "Settings is shorter: the calendars and the font and colours each have a screen
         of their own, reached from one row that shows the current choice."
      7. Delete docs/settings-ux-plan.md and docs/settings-ux-plan-manual-steps.html, and check
         `grep -rn 'settings-ux-plan' .` prints nothing.
            8. docs/end-of-day-handoff.md: add ADR 0051 to the decision links at the top, next to ADR 0036.
      9. Run `python3 -m unittest discover -s scripts/tests` (the no-project-history guard).
    acceptance:
      - test ! -e docs/settings-ux-plan.md && test ! -e docs/settings-ux-plan-manual-steps.html
      - grep -rn 'settings-ux-plan' . --exclude-dir=.git prints nothing
      - ls docs/adr/0051-*.md docs/adr/0052-*.md lists two files and both contain "Accepted"
      - grep -q '0051' docs/adr/README.md && grep -q '0052' docs/adr/README.md
            - sed -n '/## \[Unreleased\]/,/## \[0.2.0\]/p' CHANGELOG.md | grep -c 'delivery sync \[0-9\]+\|several names\|opens your Drive\|Settings is shorter' prints 4
      - python3 -m unittest discover -s scripts/tests passes
```
