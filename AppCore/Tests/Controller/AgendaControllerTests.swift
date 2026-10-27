// AppCore's agenda controller: client setup, sign-in, loading a day from Google data, list lookup,
// notices, settings and draft edits, short names and rendering.

import Foundation
import Testing

@testable import AppCore

private let budapest = TimeZone(identifier: "Europe/Budapest") ?? .gmt
let validClientID = "123456789012-abc123.apps.googleusercontent.com"
let validCredentials = GoogleClientCredentials(clientID: validClientID, clientSecret: nil)

func date(_ iso: String) -> CalendarDay {
    CalendarDay(isoString: iso) ?? .today(in: .gmt, now: Date(timeIntervalSince1970: 0))
}

let tuesday = date("2026-09-29")
let wednesday = date("2026-09-30")

struct Failure: Error {}

private struct FailingCredentialsStore: ClientCredentialsStore {
    var stored: GoogleClientCredentials?
    var failsToLoad = false

    func load() throws -> GoogleClientCredentials? {
        if failsToLoad {
            throw Failure()
        }
        return stored
    }

    func save(_ credentials: GoogleClientCredentials) throws {
        throw Failure()
    }

    func delete() throws {
        throw Failure()
    }
}

private actor ThrowingAccount: GoogleAccount {
    let error: any Error

    init(_ error: any Error) {
        self.error = error
    }

    func configure(_ configuration: GoogleOAuthConfiguration?) {}

    func isConfigured() -> Bool {
        true
    }

    func isSignedIn() -> Bool {
        false
    }

    func signIn(authenticate: @escaping @Sendable (URL, String) async throws -> URL) async throws {
        throw error
    }

    func signOut() {}
}

struct FailingDataSource: GoogleDataSource {
    let error: any Error

    func calendars() async throws -> [GoogleCalendar] {
        throw error
    }

    func events(calendarID: String, on day: CalendarDay, timeZone: TimeZone) async throws
        -> [GoogleEvent]
    {
        []
    }

    func taskLists() async throws -> [GoogleTaskList] {
        []
    }

    func openTasks(listID: String) async throws -> [GoogleTask] {
        []
    }
}

private actor CountingDataSource: GoogleDataSource {
    private let base: any GoogleDataSource
    private(set) var loads = 0

    init(_ base: any GoogleDataSource) {
        self.base = base
    }

    func calendars() async throws -> [GoogleCalendar] {
        loads += 1
        return try await base.calendars()
    }

    func events(calendarID: String, on day: CalendarDay, timeZone: TimeZone) async throws
        -> [GoogleEvent]
    {
        try await base.events(calendarID: calendarID, on: day, timeZone: timeZone)
    }

    func taskLists() async throws -> [GoogleTaskList] {
        try await base.taskLists()
    }

    func openTasks(listID: String) async throws -> [GoogleTask] {
        try await base.openTasks(listID: listID)
    }
}

@MainActor
struct Context {
    let controller: AgendaController
    let account: any GoogleAccount
    let settingsStore: InMemorySettingsStore
    let credentials: any ClientCredentialsStore
    let renderer: FakeRenderer
    let binderStore: any BinderStore
}

@MainActor
func make(
    data: any GoogleDataSource = FixtureGoogleDataSource(.standard),
    account: any GoogleAccount = FixtureGoogleAccount(signedIn: true),
    credentials: any ClientCredentialsStore = InMemoryClientCredentialsStore(validCredentials),
    settings: AgendaSettings = AgendaSettings(),
    renderer: FakeRenderer = FakeRenderer(),
    rendering: (any AgendaRendering)? = nil,
    binderStore: any BinderStore = InMemoryBinderStore(),
    today: CalendarDay = tuesday
) throws -> Context {
    let store = InMemorySettingsStore(settings)
    let controller = AgendaController(
        account: account, data: data, settingsStore: store, credentials: credentials,
        measurer: FakeTextMeasurer(), renderer: rendering ?? renderer,
        binderStore: binderStore, manifest: try TemplateManifest.bundled(), timeZone: budapest,
        today: today, makeID: CountingIDs().next)
    return Context(
        controller: controller, account: account, settingsStore: store, credentials: credentials,
        renderer: renderer, binderStore: binderStore)
}

@MainActor
func started(_ fixture: GoogleFixture, settings: AgendaSettings = AgendaSettings())
    async throws -> Context
{
    let context = try make(data: FixtureGoogleDataSource(fixture), settings: settings)
    await context.controller.start()
    return context
}

@MainActor
private func eventIDs(_ context: Context, titled title: String) -> [String] {
    context.controller.draft?.events.filter { $0.originalTitle == title }.map(\.id) ?? []
}

@MainActor
@Suite("Agenda controller")
struct AgendaControllerTests {
    @Test("the day starts at the next working day")
    func initialDay() throws {
        #expect(try make().controller.day == wednesday)
        #expect(try make(today: date("2026-10-02")).controller.day == date("2026-10-05"))
        #expect(try make().controller.status == .starting)
        #expect(try make().controller.showsNextWorkingDay == false)
    }

    @Test("start without a stored client needs setup and clears the account's client")
    func startNeedsSetup() async throws {
        let account = FixtureGoogleAccount(signedIn: true)
        await account.configure(GoogleOAuthConfiguration(clientID: validClientID))
        let context = try make(account: account, credentials: InMemoryClientCredentialsStore())
        await context.controller.start()
        #expect(context.controller.status == .needsSetup)
        #expect(context.controller.clientID == nil)
        #expect(await account.isConfigured() == false)
    }

    @Test("a stored client that cannot be read or is malformed counts as none")
    func startUnusableCredentials() async throws {
        let unreadable = FailingCredentialsStore(stored: validCredentials, failsToLoad: true)
        let first = try make(credentials: unreadable)
        await first.controller.start()
        #expect(first.controller.status == .needsSetup)
        let malformed = FailingCredentialsStore(
            stored: GoogleClientCredentials(clientID: "bad", clientSecret: nil))
        let second = try make(credentials: malformed)
        await second.controller.start()
        #expect(second.controller.status == .needsSetup)
        #expect(second.controller.clientID == nil)
    }

    @Test("start loads the day when signed in and waits for sign-in otherwise")
    func startSignedInAndOut() async throws {
        let signedIn = try make()
        await signedIn.controller.start()
        #expect(signedIn.controller.status == .ready)
        #expect(signedIn.controller.clientID == validClientID)
        #expect(signedIn.controller.draft?.date == wednesday)
        let signedOut = try make(account: FixtureGoogleAccount(signedIn: false))
        await signedOut.controller.start()
        #expect(signedOut.controller.status == .signedOut)
        #expect(signedOut.controller.draft == nil)
    }

    @Test("a second start, as from a second window, keeps the draft and the PDF")
    func startTwice() async throws {
        let counting = CountingDataSource(FixtureGoogleDataSource(.standard))
        let context = try make(data: counting)
        await context.controller.start()
        let taskID = try #require(context.controller.draft?.tasks.first?.id)
        context.controller.updateDraft { $0.setIncluded(false, forTask: taskID) }
        await context.controller.render()
        let rendered = try #require(context.controller.rendered)
        let draft = context.controller.draft
        await context.controller.start()
        #expect(await counting.loads == 1)
        #expect(context.controller.status == .ready)
        #expect(context.controller.draft == draft)
        #expect(context.controller.rendered == rendered)
    }

    @Test("a client ID that is not one is refused with the client-ID message")
    func saveBadClientID() async throws {
        let context = try make(credentials: InMemoryClientCredentialsStore())
        let saved = await context.controller.saveClientCredentials(
            clientID: "not-an-id", clientSecret: "")
        #expect(!saved)
        #expect(
            context.controller.message
                == "That isn't a Google client ID. It looks like 123456789012-abc….apps.googleusercontent.com."
        )
        #expect(context.controller.status == .starting)
    }

    @Test("a secret with a space is refused with the secret message")
    func saveBadSecret() async throws {
        let context = try make(credentials: InMemoryClientCredentialsStore())
        let saved = await context.controller.saveClientCredentials(
            clientID: validClientID, clientSecret: "a b")
        #expect(!saved)
        #expect(context.controller.message == "The client secret can't contain spaces.")
    }

    @Test("a valid client is stored, configures the account and waits for sign-in")
    func saveValid() async throws {
        let account = FixtureGoogleAccount(signedIn: false)
        let store = InMemoryClientCredentialsStore()
        let context = try make(account: account, credentials: store)
        let saved = await context.controller.saveClientCredentials(
            clientID: " " + validClientID + " ", clientSecret: "  secret ")
        #expect(saved)
        #expect(
            store.load() == GoogleClientCredentials(clientID: validClientID, clientSecret: "secret")
        )
        #expect(await account.isConfigured())
        #expect(context.controller.clientID == validClientID)
        #expect(context.controller.status == .signedOut)
        #expect(context.controller.message == nil)
    }

    @Test("saving a client while signed in reloads the day")
    func saveValidSignedIn() async throws {
        let context = try await started(.standard)
        #expect(context.controller.status == .ready)
        let saved = await context.controller.saveClientCredentials(
            clientID: validClientID, clientSecret: "")
        #expect(saved)
        #expect(context.controller.status == .ready)
        #expect(context.controller.draft?.date == wednesday)
    }

    @Test("saving a client drops a load that was still running for the previous one")
    func saveClientDropsRunningLoad() async throws {
        let gated = GatedDataSource(FixtureGoogleDataSource(.standard))
        let context = try make(data: gated, account: FixtureGoogleAccount(signedIn: false))
        await context.controller.start()
        let loading = Task { await context.controller.setDay(date("2026-10-01")) }
        await gated.waitUntilBlocked()
        let saved = await context.controller.saveClientCredentials(
            clientID: validClientID, clientSecret: "")
        #expect(saved)
        await gated.release()
        await loading.value
        #expect(context.controller.status == .signedOut)
        #expect(context.controller.draft == nil)
        #expect(context.controller.calendars.isEmpty)
    }

    @Test("a store that cannot save gives the Keychain message")
    func saveFails() async throws {
        let context = try make(credentials: FailingCredentialsStore())
        let saved = await context.controller.saveClientCredentials(
            clientID: validClientID, clientSecret: "")
        #expect(!saved)
        let keychainMessage = "Couldn't save the client in the Keychain. Try again."
        #expect(context.controller.message == keychainMessage)
        #expect(context.controller.clientID == nil)
    }

    @Test("forgetting the client signs out, empties the store and needs setup")
    func forget() async throws {
        let store = InMemoryClientCredentialsStore(validCredentials)
        let account = FixtureGoogleAccount(signedIn: true)
        let context = try make(account: account, credentials: store)
        await context.controller.start()
        await context.controller.forgetClientCredentials()
        #expect(context.controller.status == .needsSetup)
        #expect(context.controller.clientID == nil)
        #expect(context.controller.draft == nil)
        #expect(store.load() == nil)
        #expect(await account.isConfigured() == false)
        #expect(await account.isSignedIn() == false)
    }

    @Test("forgetting the client ignores a store that cannot delete")
    func forgetIgnoresDeleteError() async throws {
        let context = try make(credentials: FailingCredentialsStore(stored: validCredentials))
        await context.controller.start()
        await context.controller.forgetClientCredentials()
        #expect(context.controller.status == .needsSetup)
    }

    @Test("signing in loads the day")
    func signInSuccess() async throws {
        let context = try make(account: FixtureGoogleAccount(signedIn: false))
        await context.controller.start()
        await context.controller.signIn { _, _ in throw Failure() }
        #expect(context.controller.status == .ready)
        #expect(context.controller.draft?.events.count == 10)
    }

    @Test("cancelling the sign-in leaves no message")
    func signInCancelled() async throws {
        let context = try make(account: ThrowingAccount(GoogleAPIError.authorizationCancelled))
        await context.controller.signIn { url, _ in url }
        #expect(context.controller.status == .signedOut)
        #expect(context.controller.message == nil)
    }

    @Test("a failed sign-in shows its message, and an unknown error the generic one")
    func signInFailed() async throws {
        let failed = try make(account: ThrowingAccount(GoogleAPIError.authorizationFailed))
        await failed.controller.signIn { url, _ in url }
        #expect(failed.controller.status == .signedOut)
        #expect(failed.controller.message == GoogleAPIError.authorizationFailed.userMessage)
        let unknown = try make(account: ThrowingAccount(Failure()))
        await unknown.controller.signIn { url, _ in url }
        #expect(unknown.controller.message == GoogleAPIError.unexpectedResponse.userMessage)
    }

    @Test("signing out clears everything read from Google")
    func signOut() async throws {
        let context = try await started(.standard)
        await context.controller.render()
        #expect(context.controller.rendered != nil)
        await context.controller.signOut()
        #expect(context.controller.status == .signedOut)
        #expect(context.controller.draft == nil)
        #expect(context.controller.calendars.isEmpty)
        #expect(context.controller.taskLists.isEmpty)
        #expect(context.controller.rendered == nil)
        #expect(await context.account.isSignedIn() == false)
    }

    @Test("the primary calendar is read when none is chosen or the chosen one is gone")
    func calendarSelection() async throws {
        let empty = try await started(.standard)
        #expect(empty.controller.draft?.events.count == 10)
        #expect(empty.controller.calendars.map(\.id) == ["primary", "family"])
        #expect(empty.controller.taskLists.map(\.id) == ["todo", "delegated", "other"])
        var stale = AgendaSettings()
        stale.calendarIDs = ["deleted"]
        let gone = try await started(.standard, settings: stale)
        #expect(gone.controller.draft?.events.count == 10)
        var family = AgendaSettings()
        family.calendarIDs = ["deleted", "family"]
        let chosen = try await started(.standard, settings: family)
        #expect(chosen.controller.draft?.events.isEmpty == true)
    }

    @Test("lists are found by title ignoring case and accents, and other lists never appear")
    func listLookup() async throws {
        var settings = AgendaSettings()
        settings.todoListTitle = "CLÁUDE"
        settings.delegatedListTitle = "claude delegations"
        let context = try await started(.standard, settings: settings)
        let draft = try #require(context.controller.draft)
        #expect(draft.tasks.count == 5)
        #expect(draft.delegated.count == 3)
        #expect(!draft.tasks.contains { $0.text == "Wrong list" })
        #expect(draft.notices.isEmpty)
    }

    @Test("a missing to-do list gives no tasks and a notice")
    func missingTodoList() async throws {
        var settings = AgendaSettings()
        settings.todoListTitle = "Nope"
        let context = try await started(.standard, settings: settings)
        let draft = try #require(context.controller.draft)
        #expect(draft.tasks.isEmpty)
        #expect(draft.delegated.count == 3)
        #expect(
            draft.notices == [
                "No Google Tasks list named “Nope”. Create it in Google Tasks or pick another list in Settings."
            ])
    }

    @Test("an empty delegated title means no delegated page and no notice")
    func noDelegatedList() async throws {
        var settings = AgendaSettings()
        settings.delegatedListTitle = ""
        let context = try await started(.standard, settings: settings)
        let draft = try #require(context.controller.draft)
        #expect(draft.delegated.isEmpty)
        #expect(draft.tasks.count == 5)
        #expect(draft.notices.isEmpty)
    }

    @Test("the to-do list never doubles as the delegated list")
    func delegatedTitleOfTodoList() async throws {
        var settings = AgendaSettings()
        settings.delegatedListTitle = "Claude"
        let context = try await started(.standard, settings: settings)
        let draft = try #require(context.controller.draft)
        #expect(draft.delegated.isEmpty)
        #expect(
            draft.notices == [
                "No Google Tasks list named “Claude”, so there is no delegated page."
            ])
    }

    @Test("the standard fixture's draft is the specified one")
    func standardDraft() async throws {
        let context = try await started(.standard)
        let draft = try #require(context.controller.draft)
        #expect(context.controller.status == .ready)
        #expect(draft.date == wednesday)
        #expect(draft.notices.isEmpty)
        #expect(
            draft.events.map(\.originalTitle) == [
                "Start the day", "Team sync", "1:1 with Peter", "Lunch",
                "REMINDER // Decision about the office move", "Server upgrade", "Week preparation",
                "Quarterly Summit", "Quarterly Summit", "Dinner with partners",
            ])
        let exclusions: [EventExclusion?] = [
            .personalBlock, nil, nil, .personalBlock, nil, .declined, nil, nil, .duplicate, nil,
        ]
        #expect(draft.events.map(\.exclusion) == exclusions)
        #expect(
            draft.tasks.map(\.text) == [
                "Send the slides", "Call the bank", "Nora - to be discussed",
                "Peter – to be discussed", "Book flights",
            ])
        let buckets: [TaskBucket] = [.overdue, .today, .upcoming, .upcoming, .upcoming]
        #expect(draft.tasks.map(\.bucket) == buckets)
        #expect(draft.tasks.map(\.isIncluded) == [true, true, false, true, true])
        #expect(
            draft.delegated.map(\.text) == [
                "Hire a designer", "Renew the office lease", "Fix the printer",
            ])
        let content = draft.content()
        #expect(
            content.meetings == [
                "Team sync", "1:1 with Peter", "Decision about the office move",
                "Quarterly Summit", "Dinner with partners",
            ])
        #expect(content.todoItems.count == 4)
        #expect(content.schedule.map(\.slot) == [2, 5, 10, 14, 16])
    }

    @Test("an out-of-office day shows the notice and offers the next working day")
    func outOfOffice() async throws {
        let context = try await started(.outOfOffice)
        let draft = try #require(context.controller.draft)
        #expect(draft.notices == ["You're out of office on this day (“Vacation”)."])
        #expect(context.controller.showsNextWorkingDay)
    }

    @Test("a weekend shows the notice, and the next working day is the Monday")
    func weekend() async throws {
        let context = try await started(.empty)
        #expect(context.controller.showsNextWorkingDay == false)
        await context.controller.setDay(date("2026-10-03"))
        #expect(context.controller.draft?.notices == ["Saturday, 3 October is a weekend."])
        #expect(context.controller.showsNextWorkingDay)
        await context.controller.goToNextWorkingDay()
        #expect(context.controller.day == date("2026-10-05"))
        #expect(context.controller.draft?.date == date("2026-10-05"))
        #expect(context.controller.showsNextWorkingDay == false)
    }

    @Test("a newer load wins over one that is still waiting for Google")
    func newerLoadWins() async throws {
        let gated = GatedDataSource(FixtureGoogleDataSource(.standard))
        let context = try make(data: gated, account: FixtureGoogleAccount(signedIn: false))
        await context.controller.start()
        let first = Task { await context.controller.setDay(date("2026-10-01")) }
        await gated.waitUntilBlocked()
        await context.controller.setDay(date("2026-10-02"))
        await gated.release()
        await first.value
        #expect(context.controller.day == date("2026-10-02"))
        #expect(context.controller.draft?.date == date("2026-10-02"))
        #expect(context.controller.status == .ready)
    }

    @Test("a signed-out error moves to signed out with its message")
    func loadSignedOut() async throws {
        let context = try make(data: FailingDataSource(error: GoogleAPIError.signedOut))
        await context.controller.start()
        #expect(context.controller.status == .signedOut)
        #expect(context.controller.message == GoogleAPIError.signedOut.userMessage)
    }

    @Test("Missing scopes sign the person out with the scope message")
    func loadMissingScopes() async throws {
        let context = try make(data: FailingDataSource(error: GoogleAPIError.missingScopes))
        await context.controller.start()
        #expect(context.controller.status == .signedOut)
        #expect(
            context.controller.message
                == "Magenda needs your calendars, your tasks and the files it creates in Google Drive. Sign in again and allow all three."
        )
    }

    @Test("other errors fail the load with a message")
    func loadFailed() async throws {
        let network = try make(data: FailingDataSource(error: GoogleAPIError.network))
        await network.controller.start()
        #expect(network.controller.status == .failed(GoogleAPIError.network.userMessage))
        let unknown = try make(data: FailingDataSource(error: Failure()))
        await unknown.controller.start()
        let unexpected = GoogleAPIError.unexpectedResponse.userMessage
        #expect(unknown.controller.status == .failed(unexpected))
    }

    @Test("settings are saved, and the day reloads only when what is read changed")
    func updateSettings() async throws {
        let counting = CountingDataSource(FixtureGoogleDataSource(.standard))
        let context = try make(data: counting)
        await context.controller.start()
        #expect(await counting.loads == 1)
        await context.controller.updateSettings { $0.fontPack = .roboto }
        #expect(await counting.loads == 1)
        #expect(context.settingsStore.load().fontPack == .roboto)
        #expect(context.controller.settings.fontPack == .roboto)
        await context.controller.updateSettings { $0.calendarIDs = ["family"] }
        #expect(await counting.loads == 2)
        await context.controller.updateSettings { $0.todoListTitle = "Nope" }
        #expect(await counting.loads == 3)
        await context.controller.updateSettings { $0.delegatedListTitle = "" }
        #expect(await counting.loads == 4)
        await context.controller.updateSettings { $0.rules.lookAheadDays = 0 }
        #expect(await counting.loads == 5)
        #expect(context.settingsStore.load().rules.lookAheadDays == 0)
    }

    @Test("a changed rule changes the draft")
    func rulesChangeDraft() async throws {
        let context = try await started(.standard)
        await context.controller.updateSettings { $0.rules.lookAheadDays = 0 }
        let texts = context.controller.draft?.tasks.map(\.text)
        #expect(texts == ["Send the slides", "Call the bank"])
    }

    @Test("a routine added in settings reloads the day and reaches the draft's events")
    func summaryRoutinesReachDraft() async throws {
        let id = "0f8fad5b-d9cb-469f-a165-70867728950e"
        let routine = SummaryRoutine(id: id, name: "Notes")
        var settings = AgendaSettings()
        settings.rules.summaryRoutines = ["Team sync": [id]]
        let counting = CountingDataSource(FixtureGoogleDataSource(.standard))
        let context = try make(data: counting, settings: settings)
        await context.controller.start()
        #expect(await counting.loads == 1)
        #expect(context.controller.draft?.summaryRoutines == [])

        await context.controller.updateSettings { $0.summaryRoutines = [routine] }
        #expect(await counting.loads == 2)
        #expect(context.controller.draft?.summaryRoutines == [routine])
        #expect(
            context.controller.draft?.events.first { $0.originalTitle == "Team sync" }?
                .summaryRoutineIDs == [id])

        await context.controller.updateSettings { $0.removeSummaryRoutine(id: id) }
        #expect(await counting.loads == 3)
        #expect(context.controller.draft?.summaryRoutines == [])
        #expect(
            context.controller.draft?.events.first { $0.originalTitle == "Team sync" }?
                .summaryRoutineIDs == [])
    }

    @Test("a short name retitles every event sharing the key, without reloading")
    func shortName() async throws {
        let counting = CountingDataSource(FixtureGoogleDataSource(.standard))
        let context = try make(data: counting)
        await context.controller.start()
        let ids = eventIDs(context, titled: "Quarterly Summit")
        #expect(ids.count == 2)
        context.controller.saveShortName("  Summit  ", forEvent: ids[0])
        #expect(await counting.loads == 1)
        let key = MeetingTitle.key(originalTitle: "Quarterly Summit", recurringEventID: nil)
        #expect(context.controller.settings.rules.shortNames[key] == "Summit")
        #expect(context.settingsStore.load().rules.shortNames[key] == "Summit")
        let titles = context.controller.draft?.events.filter { ids.contains($0.id) }.map(\.title)
        #expect(titles == ["Summit", "Summit"])
        context.controller.saveShortName(" ", forEvent: ids[1])
        #expect(context.controller.settings.rules.shortNames[key] == nil)
        let restored = context.controller.draft?.events.filter { ids.contains($0.id) }.map(\.title)
        #expect(restored == ["Quarterly Summit", "Quarterly Summit"])
    }

    @Test("a short name for an unknown event, or with no draft, changes nothing")
    func shortNameIgnored() async throws {
        let empty = try make()
        empty.controller.saveShortName("Summit", forEvent: "primary|e1")
        #expect(empty.controller.settings.rules.shortNames.isEmpty)
        let context = try await started(.standard)
        context.controller.saveShortName("Summit", forEvent: "primary|nope")
        #expect(context.controller.settings.rules.shortNames.isEmpty)
        #expect(context.settingsStore.load().rules.shortNames.isEmpty)
    }

    @Test("changing only the Drive folder keeps the rendered PDF")
    func driveFolderKeepsRendered() async throws {
        let context = try await started(.standard)
        await context.controller.render()
        await context.controller.updateSettings { $0.driveFolderName = "Work notes" }
        #expect(context.controller.rendered != nil)
        #expect(context.settingsStore.load().driveFolderName == "Work notes")
    }

    @Test("edits to the draft and the settings clear the rendered PDF")
    func editsClearRendered() async throws {
        let context = try await started(.standard)
        await context.controller.render()
        #expect(context.controller.rendered != nil)
        let taskID = try #require(context.controller.draft?.tasks.first?.id)
        context.controller.updateDraft { $0.setIncluded(false, forTask: taskID) }
        #expect(context.controller.rendered == nil)
        #expect(context.controller.draft?.tasks.first?.isIncluded == false)
        await context.controller.render()
        #expect(context.controller.rendered != nil)
        await context.controller.updateSettings { $0.fontPack = .jetbrainsMono }
        #expect(context.controller.rendered == nil)
        await context.controller.render()
        let firstEvent = try #require(context.controller.draft?.events.first?.id)
        context.controller.saveShortName("Short", forEvent: firstEvent)
        #expect(context.controller.rendered == nil)
    }

    @Test("editing without a draft does nothing")
    func updateDraftWithoutDraft() throws {
        let context = try make()
        context.controller.updateDraft { $0.notices = ["x"] }
        #expect(context.controller.draft == nil)
    }

    @Test("render writes the day's file and describes it")
    func render() async throws {
        let context = try await started(.standard)
        await context.controller.render()
        let rendered = try #require(context.controller.rendered)
        #expect(context.controller.status == .ready)
        #expect(context.renderer.fileNames == ["2026-09-30.pdf"])
        #expect(rendered.url == context.renderer.url)
        #expect(rendered.pageCount == context.renderer.plans[0].pages.count)
        #expect(rendered.omittedTasks.isEmpty)
    }

    @Test("render reports the tasks that did not fit")
    func renderOverflow() async throws {
        let context = try await started(.overflow)
        await context.controller.render()
        let rendered = try #require(context.controller.rendered)
        #expect(!rendered.omittedTasks.isEmpty)
    }

    @Test("a renderer error leaves the draft ready with a message")
    func renderFails() async throws {
        let renderer = FakeRenderer(fails: true)
        let context = try make(renderer: renderer)
        await context.controller.start()
        await context.controller.render()
        #expect(context.controller.status == .ready)
        #expect(context.controller.rendered == nil)
        #expect(context.controller.message == "Couldn't create the PDF. Try again.")
    }

    @Test("a load during a render wins, and the stale PDF is dropped")
    func loadDuringRender() async throws {
        let gated = GatedRenderer()
        let context = try make(rendering: gated)
        await context.controller.start()
        let rendering = Task { await context.controller.render() }
        await gated.waitUntilBlocked()
        #expect(context.controller.status == .rendering)
        await context.controller.goToNextWorkingDay()
        await gated.release()
        await rendering.value
        #expect(gated.base.fileNames == ["2026-09-30.pdf"])
        #expect(context.controller.day == date("2026-10-01"))
        #expect(context.controller.draft?.date == date("2026-10-01"))
        #expect(context.controller.status == .ready)
        #expect(context.controller.rendered == nil)
    }

    @Test("a sign-out during a render stays signed out with nothing rendered")
    func signOutDuringRender() async throws {
        let gated = GatedRenderer()
        let context = try make(rendering: gated)
        await context.controller.start()
        let rendering = Task { await context.controller.render() }
        await gated.waitUntilBlocked()
        await context.controller.signOut()
        await gated.release()
        await rendering.value
        #expect(context.controller.status == .signedOut)
        #expect(context.controller.draft == nil)
        #expect(context.controller.rendered == nil)
    }

    @Test("an edit during a render makes the draft ready again and drops the stale PDF")
    func editDuringRender() async throws {
        let gated = GatedRenderer(FakeRenderer(fails: true))
        let context = try make(rendering: gated)
        await context.controller.start()
        let rendering = Task { await context.controller.render() }
        await gated.waitUntilBlocked()
        let taskID = try #require(context.controller.draft?.tasks.first?.id)
        context.controller.updateDraft { $0.setIncluded(false, forTask: taskID) }
        #expect(context.controller.status == .ready)
        await gated.release()
        await rendering.value
        #expect(context.controller.status == .ready)
        #expect(context.controller.rendered == nil)
        #expect(context.controller.message == nil)
        #expect(context.controller.draft?.tasks.first?.isIncluded == false)
    }

    @Test("render without a draft does nothing")
    func renderWithoutDraft() async throws {
        let context = try make()
        await context.controller.render()
        #expect(context.controller.status == .starting)
        #expect(context.renderer.plans.isEmpty)
    }
}
