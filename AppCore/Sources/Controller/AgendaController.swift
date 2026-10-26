import Foundation
import Observation

/// A PDF that has been written, with what the person should know about it.
public struct RenderedAgenda: Equatable, Sendable {
    /// Where the PDF is.
    public let url: URL
    /// How many pages it has.
    public let pageCount: Int
    /// The to-dos that did not fit on the overview page.
    public let omittedTasks: [String]

    /// Creates a description of a written PDF.
    public init(url: URL, pageCount: Int, omittedTasks: [String]) {
        self.url = url
        self.pageCount = pageCount
        self.omittedTasks = omittedTasks
    }
}

/// Draws a `RenderPlan` into a PDF file.
public protocol AgendaRendering: Sendable {
    /// Writes the PDF for `plan` to a file called `fileName` and returns where it is. `ink[i]` is
    /// the PencilKit data written on page `i`; a missing index means none.
    func render(_ plan: RenderPlan, ink: [Data?], fileName: String) async throws -> URL
}

extension AgendaRendering {
    /// Writes the PDF for `plan` without handwriting.
    public func render(_ plan: RenderPlan, fileName: String) async throws -> URL {
        try await render(plan, ink: [], fileName: fileName)
    }
}

/// Everything the screens show and do: sign-in, loading a day, reviewing and editing its draft,
/// and rendering the PDF.
@MainActor @Observable
public final class AgendaController {
    /// Where the controller is in its life.
    public enum Status: Equatable {
        /// `start()` has not finished.
        case starting
        /// No Google client has been entered.
        case needsSetup
        /// A client is set but nobody is signed in.
        case signedOut
        /// The sign-in sheet is open.
        case signingIn
        /// Google data for the day is being read.
        case loading
        /// The draft is ready to review.
        case ready
        /// The PDF is being written.
        case rendering
        /// Loading failed; the text says why.
        case failed(String)
    }

    /// Where the controller is in its life.
    public private(set) var status: Status = .starting
    /// The day the agenda is for.
    public private(set) var day: CalendarDay
    /// What was selected for `day`, with the person's edits.
    public private(set) var draft: AgendaDraft?
    /// The binder settings.
    public private(set) var settings: AgendaSettings
    /// The person's calendars, for the settings screen.
    public private(set) var calendars: [GoogleCalendar] = []
    /// The person's task lists, for the settings screen.
    public private(set) var taskLists: [GoogleTaskList] = []
    /// The PDF for the current draft, until the draft or settings change.
    public private(set) var rendered: RenderedAgenda?
    /// The open binder of `day`, when one was started or is stored on this device.
    public private(set) var binder: BinderSession?
    /// The PDF of the binder with its handwriting, until it is shared or cleared.
    public private(set) var binderExport: URL?
    /// The last error or notice for the current screen.
    public private(set) var message: String?
    /// The client ID that was entered, for the settings screen; `nil` before setup.
    public private(set) var clientID: String?

    @ObservationIgnored private let account: any GoogleAccount
    @ObservationIgnored private let data: any GoogleDataSource
    @ObservationIgnored private let settingsStore: any SettingsStore
    @ObservationIgnored private let credentials: any ClientCredentialsStore
    @ObservationIgnored private let measurer: any TextMeasuring
    @ObservationIgnored private let renderer: any AgendaRendering
    @ObservationIgnored private let binderStore: any BinderStore
    @ObservationIgnored private let binderLayout: BinderLayout
    @ObservationIgnored private let makeID: @Sendable () -> String
    @ObservationIgnored private let manifest: TemplateManifest
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var renderGeneration = 0
    @ObservationIgnored private var hasStarted = false

    /// Whether the draft carries a weekend or out-of-office notice, so the screen offers the next
    /// working day.
    public var showsNextWorkingDay: Bool {
        draft?.notices.contains {
            $0.hasSuffix("is a weekend.") || $0.hasPrefix("You're out of office")
        } ?? false
    }

    /// Creates a controller; call `start()` before showing it. `day` begins at the first working
    /// day after `today`.
    public init(
        account: any GoogleAccount, data: any GoogleDataSource, settingsStore: any SettingsStore,
        credentials: any ClientCredentialsStore, measurer: any TextMeasuring,
        renderer: any AgendaRendering, binderStore: any BinderStore, manifest: TemplateManifest,
        timeZone: TimeZone, today: CalendarDay,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.account = account
        self.data = data
        self.settingsStore = settingsStore
        self.credentials = credentials
        self.measurer = measurer
        self.renderer = renderer
        self.binderStore = binderStore
        binderLayout = BinderLayout(manifest: manifest, measurer: measurer)
        self.makeID = makeID
        self.manifest = manifest
        self.timeZone = timeZone
        day = today.nextWeekday()
        settings = settingsStore.load()
    }

    /// Reads the stored client, and loads the day when someone is signed in. Only the first call
    /// does anything, so a second window showing the controller keeps its draft and PDF.
    public func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        let configuration = (try? credentials.load())?.configuration
        await account.configure(configuration)
        clientID = configuration?.clientID
        if configuration == nil {
            status = .needsSetup
        } else {
            await resumeSession()
        }
    }

    /// Validates and stores the Google client; returns whether it was accepted, with `message`
    /// saying what was wrong otherwise.
    public func saveClientCredentials(clientID: String, clientSecret: String) async -> Bool {
        guard
            let configuration = GoogleOAuthConfiguration(
                clientID: clientID, clientSecret: clientSecret)
        else {
            message =
                GoogleOAuthConfiguration(clientID: clientID) == nil
                ? "That isn't a Google client ID. It looks like 123456789012-abc….apps.googleusercontent.com."
                : "The client secret can't contain spaces."
            return false
        }
        do {
            try credentials.save(
                GoogleClientCredentials(
                    clientID: configuration.clientID, clientSecret: configuration.clientSecret))
        } catch {
            message = "Couldn't save the client in the Keychain. Try again."
            return false
        }
        await account.configure(configuration)
        self.clientID = configuration.clientID
        clearLoadedState()
        message = nil
        await resumeSession()
        return true
    }

    /// Signs out and forgets the Google client.
    public func forgetClientCredentials() async {
        await signOut()
        try? credentials.delete()
        await account.configure(nil)
        clientID = nil
        status = .needsSetup
    }

    /// Signs in with `authenticate`, which shows Google's page, and loads the day.
    public func signIn(
        authenticate: @escaping @Sendable (URL, String) async throws -> URL
    ) async {
        status = .signingIn
        do {
            try await account.signIn(authenticate: authenticate)
            await load()
        } catch {
            let failure = Self.apiError(error)
            status = .signedOut
            message = failure == .authorizationCancelled ? nil : failure.userMessage
        }
    }

    /// Signs out and clears everything read from Google.
    public func signOut() async {
        loadGeneration += 1
        await account.signOut()
        clearLoadedState()
        message = nil
        status = .signedOut
    }

    /// Reads the day's events and tasks and builds the draft. A load started later wins over one
    /// still running.
    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        status = .loading
        message = nil
        if binder?.date != day {
            openStoredBinder()
        }
        invalidateRendered()
        let outcome: Result<Loaded, any Error>
        do {
            outcome = .success(try await fetch())
        } catch {
            outcome = .failure(error)
        }
        guard generation == loadGeneration else {
            return
        }
        switch outcome {
        case .success(let loaded):
            calendars = loaded.calendars
            taskLists = loaded.taskLists
            draft = loaded.draft
            status = .ready
        case .failure(let error):
            let failure = Self.apiError(error)
            if failure == .signedOut || failure == .missingScopes {
                status = .signedOut
                message = failure.userMessage
            } else {
                status = .failed(failure.userMessage)
            }
        }
    }

    /// Switches to `day` and loads it.
    public func setDay(_ day: CalendarDay) async {
        self.day = day
        await load()
    }

    /// Switches to the first working day after the current one.
    public func goToNextWorkingDay() async {
        await setDay(day.nextWeekday())
    }

    /// Applies `change` to the settings and saves them; reloads when it changed what is read from
    /// Google or how it is selected.
    public func updateSettings(_ change: (inout AgendaSettings) -> Void) async {
        let before = settings
        var after = before
        change(&after)
        settings = after
        settingsStore.save(after)
        invalidateRendered()
        let readsDifferently =
            after.calendarIDs != before.calendarIDs
            || after.todoListTitle != before.todoListTitle
            || after.delegatedListTitle != before.delegatedListTitle
            || after.rules != before.rules
        if readsDifferently {
            await load()
        }
    }

    /// Applies `change` to the draft.
    public func updateDraft(_ change: (inout AgendaDraft) -> Void) {
        if var edited = draft {
            change(&edited)
            draft = edited
        }
        invalidateRendered()
    }

    /// Saves `title` as the short name of the meeting that event `id` belongs to, and applies it
    /// to the draft without reloading. A blank `title` removes the short name.
    public func saveShortName(_ title: String, forEvent id: String) {
        guard let key = draft?.events.first(where: { $0.id == id })?.shortNameKey else {
            return
        }
        let name = TextFitter.normalized(title)
        settings.rules.shortNames[key] = name.isEmpty ? nil : name
        settingsStore.save(settings)
        draft?.applyShortName(name, key: key)
        invalidateRendered()
    }

    /// Lays out the draft and writes the PDF. A load, sign-out or edit while it runs makes the
    /// PDF stale, so it is then dropped and the status left to whatever changed it.
    public func render() async {
        guard let draft else {
            return
        }
        renderGeneration += 1
        let generation = renderGeneration
        let fileName = day.isoString + ".pdf"
        status = .rendering
        message = nil
        let theme = settings.theme
        let layout = AgendaLayout(manifest: manifest, measurer: measurer, theme: theme)
        let binderLayout = binderLayout
        let content = draft.content()
        let base = binder?.date == day ? binder?.day : nil
        let inked = binder?.inkedKeys ?? []
        let laidOut = await Task.detached {
            let binderDay = Self.binderDay(
                binderLayout, base: base, content: content, theme: theme, inked: inked)
            return LaidOut(
                plan: layout.plan(for: content), binderDay: binderDay,
                binderPlan: binderLayout.plan(for: binderDay))
        }.value
        let plan = laidOut.plan
        let outcome: Result<URL, any Error>
        do {
            outcome = .success(try await renderer.render(plan, fileName: fileName))
        } catch {
            outcome = .failure(error)
        }
        guard generation == renderGeneration else {
            return
        }
        saveBinder(laidOut, base: base, inked: inked, content: content, theme: theme)
        switch outcome {
        case .success(let url):
            rendered = RenderedAgenda(
                url: url, pageCount: plan.pages.count,
                omittedTasks: plan.omittedTodoItems.map(\.text))
        case .failure:
            message = "Couldn't create the PDF. Try again."
        }
        status = .ready
    }

    /// Whether the day can be started over: no page of it was sent to Claude.
    public var canStartOver: Bool { binder?.day.locked.isEmpty ?? true }

    /// Deletes the day's handwriting and added pages and renders the day fresh, as if it had never
    /// been started.
    public func startOver() async {
        guard canStartOver else {
            message =
                "A meeting on this day was already sent to Claude, so it can't be started over. Reset its hand-off first."
            return
        }
        guard let draft else {
            return
        }
        do {
            for key in try binderStore.ink(on: day).keys {
                try binderStore.saveInk(Data(), for: key, on: day)
            }
            try binderStore.saveDay(BinderDay(content: draft.content(), theme: settings.theme))
        } catch {
            // Some ink may already be gone, so the binder is reopened to show what is stored.
            openStoredBinder()
            message =
                "Couldn't delete this day's handwriting. Free some space on this device and try again."
            return
        }
        binder = nil
        binderExport = nil
        await render()
    }

    /// Writes the PDF of the open binder, with its handwriting on each page, and keeps it in
    /// `binderExport`.
    public func exportBinder() async {
        guard let binder else {
            return
        }
        let ink = binder.plan.pages.map { binder.ink[$0.key] }
        do {
            binderExport = try await renderer.render(
                binder.plan, ink: ink, fileName: binder.date.isoString + ".pdf")
        } catch {
            message = "Couldn't create the PDF. Try again."
        }
    }

    /// Forgets the exported PDF, once it has been shared or dismissed.
    public func clearBinderExport() {
        binderExport = nil
    }

    private struct LaidOut: Sendable {
        let plan: RenderPlan
        let binderDay: BinderDay
        let binderPlan: RenderPlan
    }

    private struct Loaded {
        let calendars: [GoogleCalendar]
        let taskLists: [GoogleTaskList]
        let draft: AgendaDraft
    }

    private static func apiError(_ error: any Error) -> GoogleAPIError {
        error as? GoogleAPIError ?? .unexpectedResponse
    }

    nonisolated private static func binderDay(
        _ layout: BinderLayout, base: BinderDay?, content: AgendaContent, theme: Theme,
        inked: Set<PageKey>
    ) -> BinderDay {
        base.map { layout.rebased($0, onto: content, theme: theme, inkedKeys: inked) }
            ?? BinderDay(content: content, theme: theme)
    }

    // Opens what is stored for `day`, so a started day shows before (or without) the fetch.
    private func openStoredBinder() {
        do {
            if let stored = try binderStore.day(day) {
                binder = BinderSession(
                    day: stored, plan: binderLayout.plan(for: stored),
                    ink: try binderStore.ink(on: day), store: binderStore, layout: binderLayout,
                    makeID: makeID)
            } else {
                binder = nil
            }
        } catch {
            binder = nil
            message = "Couldn't read the saved binder for this day."
        }
    }

    // A page added or handwriting written while the render ran is in the open session but not in
    // `base` or `inked`, so the day is rebased again from the session before it is saved.
    private func saveBinder(
        _ laidOut: LaidOut, base: BinderDay?, inked: Set<PageKey>, content: AgendaContent,
        theme: Theme
    ) {
        var binderDay = laidOut.binderDay
        var binderPlan = laidOut.binderPlan
        if let session = binder, session.day != base || session.inkedKeys != inked {
            binderDay = Self.binderDay(
                binderLayout, base: session.day, content: content, theme: theme,
                inked: session.inkedKeys)
            binderPlan = binderLayout.plan(for: binderDay)
        }
        do {
            try binderStore.saveDay(binderDay)
            if let session = binder {
                session.replace(day: binderDay, plan: binderPlan)
            } else {
                binder = BinderSession(
                    day: binderDay, plan: binderPlan,
                    ink: (try? binderStore.ink(on: day)) ?? [:], store: binderStore,
                    layout: binderLayout, makeID: makeID)
            }
        } catch {
            message = "Couldn't save the binder. Free some space on this device and try again."
        }
    }

    // Also drops a load still running, so it cannot bring back what was cleared.
    private func clearLoadedState() {
        loadGeneration += 1
        binder = nil
        binderExport = nil
        draft = nil
        calendars = []
        taskLists = []
        invalidateRendered()
    }

    // Forgets the PDF and makes a render still running drop its result. An edit during a render
    // leaves nothing being written, so the draft is ready again.
    private func invalidateRendered() {
        renderGeneration += 1
        rendered = nil
        if status == .rendering {
            status = .ready
        }
    }

    private func resumeSession() async {
        if await account.isSignedIn() {
            await load()
        } else {
            status = .signedOut
        }
    }

    private func fetch() async throws -> Loaded {
        let day = day
        let settings = settings
        let calendars = try await data.calendars()
        let taskLists = try await data.taskLists()
        let known = settings.calendarIDs.filter { id in calendars.contains { $0.id == id } }
        let calendarIDs = known.isEmpty ? ["primary"] : known
        let todoList = taskLists.first {
            BinderText.fold($0.title) == BinderText.fold(settings.todoListTitle)
        }
        let delegatedTitle = BinderText.fold(settings.delegatedListTitle)
        let delegatedList =
            delegatedTitle.isEmpty
            ? nil
            : taskLists.first {
                $0.id != todoList?.id && BinderText.fold($0.title) == delegatedTitle
            }
        var events: [GoogleEvent] = []
        for id in calendarIDs {
            events += try await data.events(calendarID: id, on: day, timeZone: timeZone)
        }
        let tasks = try await openTasks(in: todoList)
        let delegated = try await openTasks(in: delegatedList)
        var draft = AgendaBuilder(timeZone: timeZone, rules: settings.rules).draft(
            for: day, events: events, tasks: tasks, delegated: delegated)
        if todoList == nil {
            draft.notices.append(
                "No Google Tasks list named “\(settings.todoListTitle)”. Create it in Google Tasks or pick another list in Settings."
            )
        }
        if !delegatedTitle.isEmpty && delegatedList == nil {
            draft.notices.append(
                "No Google Tasks list named “\(settings.delegatedListTitle)”, so there is no delegated page."
            )
        }
        return Loaded(calendars: calendars, taskLists: taskLists, draft: draft)
    }

    private func openTasks(in list: GoogleTaskList?) async throws -> [GoogleTask] {
        guard let list else {
            return []
        }
        return try await data.openTasks(listID: list.id)
    }
}
