import AppCore
import SwiftUI

/// Chooses the screen for the controller's status.
struct RootView: View {
    let appInfo: AppInfo

    @Environment(AgendaController.self) private var controller

    var body: some View {
        switch controller.status {
        case .starting:
            ProgressView()
        case .needsSetup:
            SetupView(isSheet: false)
        case .signedOut, .signingIn:
            SignInView()
        default:
            AgendaView(appInfo: appInfo)
        }
    }
}

#Preview {
    if let controller = AppEnvironment.previewController() {
        RootView(appInfo: AppInfo(name: "Preview", version: "1.0.0", build: "1"))
            .environment(controller)
            .task { await controller.start() }
    }
}
