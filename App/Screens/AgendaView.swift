import AppCore
import SwiftUI

/// The agenda screen: the chosen day, with the controller's state behind it.
struct AgendaView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let agendaScreen = "agendaScreen"
    }

    let appInfo: AppInfo

    @Environment(AgendaController.self) private var controller

    var body: some View {
        List {
            Text(controller.day.isoString)
        }
        .accessibilityIdentifier(ID.agendaScreen)
    }
}

#Preview {
    if let controller = AppEnvironment.previewController() {
        AgendaView(appInfo: AppInfo(name: "Preview", version: "1.0.0", build: "1"))
            .environment(controller)
    }
}
