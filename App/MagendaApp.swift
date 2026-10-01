import AppCore
import SwiftUI

/// The app's entry point: one window showing `ContentView`.
@main
struct MagendaApp: App {
    private let appInfo = AppInfo(infoDictionary: Bundle.main.infoDictionary)

    var body: some Scene {
        WindowGroup {
            ContentView(appInfo: appInfo)
        }
    }
}
