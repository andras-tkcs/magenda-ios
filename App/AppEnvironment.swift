import AppCore
import Foundation

/// Builds the one `AgendaController` the app runs on: live Google services, or fixtures when the
/// launch arguments ask for them.
enum AppEnvironment {
    /// The day fixtures pretend it is, so the first day shown is the next weekday after it.
    private static let fixtureToday = "2026-09-29"

    /// Creates the controller. Template and font errors propagate.
    @MainActor
    static func makeController(arguments: [String], bundle: Bundle) throws -> AgendaController {
        let manifest = try TemplateManifest.bundled()
        let library = try FontLibrary(bundle: bundle)
        let measurer = CoreTextMeasurer(library: library)
        let renderer = try PDFAgendaRenderer(library: library, bundle: bundle)
        let timeZone = TimeZone.current

        if let fixture = GoogleFixture(launchArguments: arguments) {
            let credentials: GoogleClientCredentials? =
                arguments.contains("-MagendaNeedsSetup")
                ? nil
                : GoogleClientCredentials(
                    clientID: "123456789012-fixture.apps.googleusercontent.com",
                    clientSecret: nil)
            return AgendaController(
                account: FixtureGoogleAccount(signedIn: !arguments.contains("-MagendaSignedOut")),
                data: FixtureGoogleDataSource(fixture),
                settingsStore: InMemorySettingsStore(AgendaSettings()),
                credentials: InMemoryClientCredentialsStore(credentials),
                measurer: measurer, renderer: renderer, binderStore: InMemoryBinderStore(),
                manifest: manifest, timeZone: timeZone,
                today: CalendarDay(isoString: fixtureToday)
                    ?? CalendarDay.today(in: timeZone, now: Date()))
        }

        let session = GoogleSession(
            configuration: nil, http: URLSessionHTTPClient(), tokens: KeychainTokenStore(),
            hasher: CryptoKitHasher(), now: { Date() })
        return AgendaController(
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
    }

    /// A fixture-backed controller for SwiftUI previews; `nil` when the bundle lacks the template.
    @MainActor
    static func previewController(_ extraArguments: [String] = []) -> AgendaController? {
        try? makeController(
            arguments: ["-MagendaFixture", "standard"] + extraArguments, bundle: .main)
    }
}
