import Foundation

/// What a fixture launch asks of the app beyond its fixture: a screen to open on, and whether to
/// animate. UI tests use it to start where they test and to skip animation waits.
public struct LaunchOptions: Equatable, Sendable {
    /// A screen a launch can open on.
    public enum Screen: String, Equatable, Sendable {
        /// The settings sheet.
        case settings
        /// The binder rules, pushed inside the settings sheet.
        case rules
    }

    /// The screen to open on, or `nil` for the agenda.
    public let screen: Screen?
    /// `false` when the launch asked for no animations.
    public let animates: Bool

    /// Reads `-MagendaOpen <settings|rules>` and `-MagendaNoAnimations`. An unknown screen name, or
    /// `-MagendaOpen` with nothing after it, opens nothing.
    public init(launchArguments: [String]) {
        screen = launchArguments.drop(while: { $0 != "-MagendaOpen" }).dropFirst().first
            .flatMap(Screen.init(rawValue:))
        animates = !launchArguments.contains("-MagendaNoAnimations")
    }

    private init(screen: Screen?, animates: Bool) {
        self.screen = screen
        self.animates = animates
    }

    /// What a launch with neither argument gets.
    public static let standard = LaunchOptions(screen: nil, animates: true)
}
