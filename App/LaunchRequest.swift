import AppCore
import SwiftUI

/// The screen a fixture launch asked to open on, handed out once, so a view that is rebuilt after
/// setup or sign-in does not open it again.
@MainActor
final class LaunchRequest {
    private var screen: LaunchOptions.Screen?

    init(_ options: LaunchOptions) {
        screen = options.screen
    }

    /// The requested screen the first time it is asked for, then `nil`.
    func take() -> LaunchOptions.Screen? {
        defer { screen = nil }
        return screen
    }
}

extension EnvironmentValues {
    @Entry var launchRequest: LaunchRequest?
}
