import AppCore
import SwiftUI

/// The app's entry point: one agenda controller shared by every window.
@main
struct MagendaApp: App {
    private let appInfo = AppInfo(infoDictionary: Bundle.main.infoDictionary)

    /// `nil` when the bundled template or fonts could not be loaded.
    @State private var controller: AgendaController?

    init() {
        _controller = State(
            initialValue: try? AppEnvironment.makeController(
                arguments: ProcessInfo.processInfo.arguments, bundle: .main))
    }

    var body: some Scene {
        WindowGroup {
            if let controller {
                RootView(appInfo: appInfo)
                    .environment(controller)
                    .task { await controller.start() }
            } else {
                Text("Couldn't load the agenda template. Reinstall Magenda.")
                    .accessibilityIdentifier("templateError")
            }
        }
        .commands { AgendaCommands(controller: controller) }
    }
}
