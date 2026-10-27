// Fixture launch options: a UI test can open on a screen directly.

import XCTest

final class LaunchOptionsUITests: XCTestCase {
    @MainActor
    func testOpeningOnSettingsShowsTheSettingsSheet() {
        let app = XCUIApplication.launchMagenda(["-MagendaOpen", "settings"])
        XCTAssertTrue(
            app.buttons["settingsDone"].waitForExistence(timeout: 30),
            "the settings sheet never appeared")
    }

    @MainActor
    func testOpeningOnRulesShowsTheRules() {
        let app = XCUIApplication.launchMagenda(["-MagendaOpen", "rules"])
        let row = app.element("rulesRow.personalBlocks.0")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the rules never appeared")
    }

    @MainActor
    func testClosingTheOpenedSettingsDoesNotReopenThem() {
        let app = XCUIApplication.launchMagenda(["-MagendaOpen", "settings"])
        let done = app.buttons["settingsDone"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 30), "the settings sheet never appeared")
        var taps = 0
        while done.exists && taps < 5 {
            done.tap()
            taps += 1
            _ = done.waitForNonExistence(timeout: 10)
        }
        XCTAssertFalse(done.exists, "the settings sheet never closed")
        _ = XCTWaiter().wait(for: [], timeout: 3)
        XCTAssertFalse(done.exists, "the settings sheet opened again")
    }

    @MainActor
    func testWithoutAnimationsTheAppStillRenders() {
        let app = XCUIApplication.launchMagenda()
        let render = app.buttons["renderButton"].firstMatch
        XCTAssertTrue(render.waitForExistence(timeout: 30), "the Render button never appeared")
        render.tap()
        XCTAssertTrue(
            app.element("binderView").waitForExistence(timeout: 30),
            "the binder never appeared")
    }
}
