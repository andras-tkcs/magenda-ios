import AppCore
import Foundation

/// What the app runs on: the controller and the services the binder's pages are drawn with.
struct AppServices {
    let controller: AgendaController
    let pageDrawer: PageDrawer
    let allowsFingerDrawing: Bool
}

/// Builds the app's services: live Google services, or fixtures when the launch arguments ask for
/// them.
enum AppEnvironment {
    /// The day fixtures pretend it is, so the first day shown is the next weekday after it.
    private static let fixtureToday = "2026-09-29"

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
            let credentials: GoogleClientCredentials? =
                arguments.contains("-MagendaNeedsSetup")
                ? nil
                : GoogleClientCredentials(
                    clientID: "123456789012-fixture.apps.googleusercontent.com",
                    clientSecret: nil)
            let controller = AgendaController(
                account: FixtureGoogleAccount(signedIn: !arguments.contains("-MagendaSignedOut")),
                data: FixtureGoogleDataSource(fixture),
                settingsStore: InMemorySettingsStore(AgendaSettings()),
                credentials: InMemoryClientCredentialsStore(credentials),
                measurer: measurer, renderer: renderer, binderStore: InMemoryBinderStore(),
                manifest: manifest, timeZone: timeZone,
                today: CalendarDay(isoString: fixtureToday)
                    ?? CalendarDay.today(in: timeZone, now: Date()))
            return AppServices(
                controller: controller, pageDrawer: drawer,
                allowsFingerDrawing: allowsFingerDrawing)
        }

        let session = GoogleSession(
            configuration: nil, http: URLSessionHTTPClient(), tokens: KeychainTokenStore(),
            hasher: CryptoKitHasher(), now: { Date() })
        let controller = AgendaController(
            account: session,
            data: LiveGoogleDataSource(
                calendar: GoogleCalendarClient(sender: session),
                tasks: GoogleTasksClient(sender: session)),
            settingsStore: UserDefaultsSettingsStore(defaults: .standard),
            credentials: KeychainClientCredentialsStore(),
            measurer: measurer, renderer: renderer,
            binderStore: FileBinderStore(
                directory: URL.applicationSupportDirectory.appending(path: "Binder")),
            manifest: manifest, timeZone: timeZone,
            today: CalendarDay.today(in: timeZone, now: Date()))
        return AppServices(
            controller: controller, pageDrawer: drawer, allowsFingerDrawing: allowsFingerDrawing)
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
