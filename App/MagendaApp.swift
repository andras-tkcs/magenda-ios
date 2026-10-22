import AppCore
import SwiftUI

/// The app's entry point: one agenda controller shared by every window.
@main
struct MagendaApp: App {
    private let appInfo = AppInfo(infoDictionary: Bundle.main.infoDictionary)

    /// `nil` when the bundled template or fonts could not be loaded.
    @State private var services: AppServices?

    init() {
        _services = State(
            initialValue: try? AppEnvironment.makeServices(
                arguments: ProcessInfo.processInfo.arguments, bundle: .main))
    }

    var body: some Scene {
        WindowGroup {
            if let services {
                RootView(appInfo: appInfo)
                    .environment(services.controller)
                    .environment(\.pageDrawer, services.pageDrawer)
                    .environment(\.allowsFingerDrawing, services.allowsFingerDrawing)
                    .task { await services.controller.start() }
            } else {
                Text("Couldn't load the agenda template. Reinstall Magenda.")
                    .accessibilityIdentifier("templateError")
            }
        }
        .commands { AgendaCommands(controller: services?.controller) }
    }
}
