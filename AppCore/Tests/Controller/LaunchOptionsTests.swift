// AppCore's fixture launch options: the screen to open on and the no-animations flag.

import Testing

@testable import AppCore

@Suite("Launch options")
struct LaunchOptionsTests {
    @Test("no arguments is the standard launch")
    func standardLaunch() {
        let options = LaunchOptions(launchArguments: [])
        #expect(options == .standard)
        #expect(options.screen == nil)
        #expect(options.animates)
    }

    @Test(
        "-MagendaOpen names the screen",
        arguments: [("settings", LaunchOptions.Screen.settings), ("rules", .rules)])
    func opensNamedScreen(name: String, screen: LaunchOptions.Screen) {
        #expect(LaunchOptions(launchArguments: ["-MagendaOpen", name]).screen == screen)
    }

    @Test(
        "an unknown or missing screen opens nothing",
        arguments: [["-MagendaOpen", "bogus"], ["-MagendaFixture", "standard", "-MagendaOpen"]])
    func opensNothing(arguments: [String]) {
        #expect(LaunchOptions(launchArguments: arguments).screen == nil)
    }

    @Test("-MagendaNoAnimations turns animation off")
    func noAnimations() {
        let options = LaunchOptions(launchArguments: ["-MagendaNoAnimations"])
        #expect(!options.animates)
        #expect(options.screen == nil)
    }

    @Test(
        "both arguments work in either order",
        arguments: [
            ["-MagendaFixture", "standard", "-MagendaOpen", "rules", "-MagendaNoAnimations"],
            ["-MagendaNoAnimations", "-MagendaFixture", "standard", "-MagendaOpen", "rules"],
        ])
    func both(arguments: [String]) {
        let options = LaunchOptions(launchArguments: arguments)
        #expect(options.screen == .rules)
        #expect(!options.animates)
    }
}
