// Fixture launch options: a UI test can open on a screen directly.

import XCTest

final class LaunchOptionsUITests: XCTestCase {
    @MainActor
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MagendaFixture", "standard"] + extra
        app.launch()
        return app
    }

    @MainActor
    func testOpeningOnSettingsShowsTheSettingsSheet() {
        let app = launch(["-MagendaOpen", "settings"])
        XCTAssertTrue(
            app.buttons["settingsDone"].waitForExistence(timeout: 30),
            "the settings sheet never appeared")
    }

    @MainActor
    func testOpeningOnRulesShowsTheRules() {
        let app = launch(["-MagendaOpen", "rules"])
        let row = app.descendants(matching: .any)["rulesRow.personalBlocks.0"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the rules never appeared")
    }

    @MainActor
    func testClosingTheOpenedSettingsDoesNotReopenThem() {
        let app = launch(["-MagendaOpen", "settings"])
        let done = app.buttons["settingsDone"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 30), "the settings sheet never appeared")
        var taps = 0
        while done.exists && taps < 5 {
            done.tap()
            taps += 1
            _ = XCTWaiter().wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "exists == false"), object: done)
                ], timeout: 10)
        }
        XCTAssertFalse(done.exists, "the settings sheet never closed")
        _ = XCTWaiter().wait(for: [], timeout: 3)
        XCTAssertFalse(done.exists, "the settings sheet opened again")
    }

    @MainActor
    func testWithoutAnimationsTheAppStillRenders() {
        let app = launch(["-MagendaNoAnimations"])
        let render = app.buttons["renderButton"].firstMatch
        XCTAssertTrue(render.waitForExistence(timeout: 30), "the Render button never appeared")
        render.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["binderView"].waitForExistence(timeout: 30),
            "the binder never appeared")
    }
}
