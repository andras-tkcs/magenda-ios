import AppCore
import Foundation

/// What the app runs on: the controllers and the services the binder's pages are drawn with.
struct AppServices {
    let controller: AgendaController
    let handoff: HandoffController
    let pageDrawer: PageDrawer
    let allowsFingerDrawing: Bool
    let contactPicker: any ContactPicking
    let animates: Bool
    let launchRequest: LaunchRequest
}

/// Builds the app's services: live Google services, or fixtures when the launch arguments ask for
/// them.
enum AppEnvironment {
    /// The day fixtures pretend it is, so the first day shown is the next weekday after it.
    private static let fixtureToday = "2026-09-29"

    /// The routine the fixtures pretend was entered, unless `-MagendaNoRoutine` is given.
    private static let fixtureRoutine = RoutineCredentials(
        fireURL: "https://api.anthropic.com/v1/claude_code/routines/trig_fixture/fire",
        token: "sk-ant-oat01-fixture")

    /// The summary routines the fixtures pretend were set up, unless `-MagendaNoSummaryRoutines`
    /// is given, each with credentials in the fixture store.
    private static let fixtureSummaryRoutines = [
        SummaryRoutine(id: "11111111-1111-4111-8111-111111111111", name: "Client memo"),
        SummaryRoutine(id: "22222222-2222-4222-8222-222222222222", name: "Decision log"),
    ]

    private static let fixtureSummaryCredentials: [String: RoutineCredentials] = {
        let triggers = ["trig_fixturememo", "trig_fixturelog"]
        let pairs = zip(fixtureSummaryRoutines, triggers).compactMap { routine, trigger in
            RoutineCredentials(
                fireURL: "https://api.anthropic.com/v1/claude_code/routines/\(trigger)/fire",
                token: "sk-ant-oat01-fixture"
            ).map { (routine.id, $0) }
        }
        return Dictionary(uniqueKeysWithValues: pairs)
    }()

    /// Reads the rendered PDF back for the hand-off.
    private static let readFile: @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }

    /// Deletes the rendered PDF once it has been read.
    private static let removeFile: @Sendable (URL) -> Void = {
        try? FileManager.default.removeItem(at: $0)
    }

    /// Creates the services. Template and font errors propagate.
    @MainActor
    static func makeServices(arguments: [String], bundle: Bundle) throws -> AppServices {
        let manifest = try TemplateManifest.bundled()
        let library = try FontLibrary(bundle: bundle)
        let measurer = CoreTextMeasurer(library: library)
        let drawer = try PageDrawer(library: library, bundle: bundle)
        let renderer = PDFAgendaRenderer(drawer: drawer)
        let timeZone = TimeZone.current
        let allowsFingerDrawing = arguments.contains("-MagendaFingerDrawing")

        if let fixture = GoogleFixture(launchArguments: arguments) {
            let launch = LaunchOptions(launchArguments: arguments)
            let credentials: GoogleClientCredentials? =
                arguments.contains("-MagendaNeedsSetup")
                ? nil
                : GoogleClientCredentials(
                    clientID: "123456789012-fixture.apps.googleusercontent.com",
                    clientSecret: nil)
            let binderStore = fixtureBinderStore(arguments: arguments)
            let fixtureDay =
                CalendarDay(isoString: fixtureToday) ?? CalendarDay.today(in: timeZone, now: Date())
            let controller = AgendaController(
                account: FixtureGoogleAccount(signedIn: !arguments.contains("-MagendaSignedOut")),
                data: FixtureGoogleDataSource(fixture),
                settingsStore: InMemorySettingsStore(
                    AgendaSettings(
                        summaryRoutines: arguments.contains("-MagendaNoSummaryRoutines")
                            ? [] : fixtureSummaryRoutines)),
                credentials: InMemoryClientCredentialsStore(credentials),
                measurer: measurer, renderer: renderer,
                binderStore: binderStore,
                manifest: manifest, timeZone: timeZone, today: fixtureDay)
            let routine = InMemoryRoutineCredentialsStore(
                arguments.contains("-MagendaNoRoutine") ? nil : fixtureRoutine)
            let summaryCredentials = InMemorySummaryRoutineCredentialsStore(
                fixtureSummaryCredentials)
            let endOfDay = FixtureEndOfDay()
            let handoff = HandoffController(
                store: InMemoryHandoffStore(), binderStore: binderStore,
                drive: FixtureDrive(state: endOfDay),
                trigger: FixtureRoutineTrigger(state: endOfDay, credentials: routine),
                routineCredentials: routine,
                summaryTrigger: FixtureSummaryTrigger(
                    state: endOfDay, credentials: summaryCredentials),
                summaryCredentials: summaryCredentials, renderer: renderer,
                hasher: CryptoKitHasher(),
                today: { fixtureDay }, readFile: readFile, removeFile: removeFile,
                folderName: { controller.settings.driveFolderName })
            return AppServices(
                controller: controller, handoff: handoff, pageDrawer: drawer,
                allowsFingerDrawing: allowsFingerDrawing, contactPicker: FixtureContactPicker(),
                animates: launch.animates, launchRequest: LaunchRequest(launch))
        }

        let session = GoogleSession(
            configuration: nil, http: URLSessionHTTPClient(), tokens: KeychainTokenStore(),
            hasher: CryptoKitHasher(), now: { Date() })
        let binderStore = FileBinderStore(
            directory: URL.applicationSupportDirectory.appending(path: "Binder"),
            protection: FileProtection.writingOptions)
        let controller = AgendaController(
            account: session,
            data: LiveGoogleDataSource(
                calendar: GoogleCalendarClient(sender: session),
                tasks: GoogleTasksClient(sender: session)),
            settingsStore: UserDefaultsSettingsStore(defaults: .standard),
            credentials: KeychainClientCredentialsStore(),
            measurer: measurer, renderer: renderer,
            binderStore: binderStore,
            manifest: manifest, timeZone: timeZone,
            today: CalendarDay.today(in: timeZone, now: Date()))
        let routine = KeychainRoutineCredentialsStore()
        let summaryCredentials = KeychainSummaryRoutineCredentialsStore()
        let handoff = HandoffController(
            store: FileHandoffStore(
                directory: URL.applicationSupportDirectory.appending(path: "Handoff"),
                protection: FileProtection.writingOptions),
            binderStore: binderStore, drive: GoogleDriveClient(sender: session),
            trigger: RoutineTriggerClient(http: URLSessionHTTPClient(), credentials: routine),
            routineCredentials: routine,
            summaryTrigger: SummaryRoutineTriggerClient(
                http: URLSessionHTTPClient(), credentials: summaryCredentials),
            summaryCredentials: summaryCredentials, renderer: renderer,
            hasher: CryptoKitHasher(),
            today: { CalendarDay.today(in: timeZone, now: Date()) },
            readFile: readFile, removeFile: removeFile,
            folderName: { controller.settings.driveFolderName })
        return AppServices(
            controller: controller, handoff: handoff, pageDrawer: drawer,
            allowsFingerDrawing: allowsFingerDrawing, contactPicker: SystemContactPicker(),
            animates: true, launchRequest: LaunchRequest(.standard))
    }

    /// The binder store of a fixture launch: in memory, or with `-MagendaBinderStoreFile <name>`
    /// a file store in the temporary directory, so a UI test can relaunch onto the same store.
    private static func fixtureBinderStore(arguments: [String]) -> any BinderStore {
        let rest = arguments.drop { $0 != "-MagendaBinderStoreFile" }.dropFirst()
        guard let name = rest.first else {
            return InMemoryBinderStore()
        }
        return FileBinderStore(
            directory: FileManager.default.temporaryDirectory.appending(path: name),
            protection: FileProtection.writingOptions)
    }

    /// Fixture-backed services for SwiftUI previews; `nil` when the bundle lacks the template.
    @MainActor
    static func previewServices(_ extraArguments: [String] = []) -> AppServices? {
        try? makeServices(
            arguments: ["-MagendaFixture", "standard"] + extraArguments, bundle: .main)
    }

    /// A fixture-backed controller for SwiftUI previews; `nil` when the bundle lacks the template.
    @MainActor
    static func previewController(_ extraArguments: [String] = []) -> AgendaController? {
        previewServices(extraArguments)?.controller
    }
}
