import AppCore
import SwiftUI

/// The main screen: a name field, the greeting for it, and the version the build stamped in.
///
/// Views hold layout and state only; what the screen shows is computed in AppCore (ADR 0007).
/// Every element a UI test reads has an accessibility identifier from `ContentView.ID`.
struct ContentView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let nameField = "nameField"
        static let greeting = "greeting"
        static let version = "version"
    }

    let appInfo: AppInfo

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.givenName)
                        .accessibilityIdentifier(ID.nameField)
                    Text(Greeting.message(for: name))
                        .accessibilityIdentifier(ID.greeting)
                }
                Section("About") {
                    LabeledContent("Version", value: appInfo.displayVersion)
                        .accessibilityIdentifier(ID.version)
                }
            }
            .navigationTitle(appInfo.name)
        }
    }
}

#Preview {
    ContentView(appInfo: AppInfo(name: "Preview", version: "1.0.0", build: "1"))
}
