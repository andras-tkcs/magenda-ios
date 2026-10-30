import AppCore
import SwiftUI
import UIKit

/// The app's entry point: one agenda controller shared by every window.
@main
struct MagendaApp: App {
    private let appInfo = AppInfo(infoDictionary: Bundle.main.infoDictionary)

    /// `nil` when the bundled template or fonts could not be loaded.
    @State private var services: AppServices?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let services = try? AppEnvironment.makeServices(
            arguments: ProcessInfo.processInfo.arguments, bundle: .main)
        _services = State(initialValue: services)
        if services?.animates == false {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let services {
                RootView(appInfo: appInfo)
                    .environment(services.controller)
                    .environment(services.handoff)
                    .environment(\.pageDrawer, services.pageDrawer)
                    .environment(\.allowsFingerDrawing, services.allowsFingerDrawing)
                    .environment(\.contactPicker, services.contactPicker)
                    .environment(\.driveFolders, services.driveFolders)
                    .environment(\.launchRequest, services.launchRequest)
                    .task {
                        await services.controller.start()
                        services.handoff.start()
                        // The scene is already active on a cold launch, before the agenda is
                        // ready, so the scenePhase refresh below has not run yet.
                        if services.controller.status == .ready {
                            await services.handoff.refresh(excluding: services.controller.day)
                        }
                    }
                    .onChange(of: scenePhase) { _, phase in
                        // Only once the agenda is ready, so its own load meets a scope problem
                        // first and shows its message.
                        guard phase == .active, services.controller.status == .ready else {
                            return
                        }
                        Task { await services.handoff.refresh(excluding: services.controller.day) }
                    }
            } else {
                Text("Couldn't load the agenda template. Reinstall Magenda.")
                    .accessibilityIdentifier("templateError")
            }
        }
        .commands { AgendaCommands(controller: services?.controller) }
    }
}
