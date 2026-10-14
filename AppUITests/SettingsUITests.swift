// The settings sheet, driven through the accessibility tree against fixtures.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `SettingsView.ID`
// and `AgendaView.ID`, never by their visible text, except for menu options and dialog buttons,
// which have none.

import XCTest

final class SettingsUITests: XCTestCase {
    private static let fixtureClientID = "123456789012-fixture.apps.googleusercontent.com"

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MagendaFixture", "standard"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Waits for the list, then opens the settings sheet, retrying a dropped tap.
    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(
            element(app, "eventRow.0").waitForExistence(timeout: 30), "the list never appeared")
        let button = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30), "the settings button never appeared")
        let done = app.buttons["settingsDone"].firstMatch
        var taps = 0
        while !done.exists && taps < 5 {
            button.tap()
            taps += 1
            _ = done.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(done.exists, "the settings sheet never opened after \(taps) taps")
    }

    /// Scrolls the form until `target` exists and can be tapped. A lazy row does not exist until
    /// it is scrolled near, so existence is polled briefly between swipes.
    @MainActor
    private func reveal(_ app: XCUIApplication, _ target: XCUIElement) {
        var swipes = 0
        while !(target.exists && target.isHittable) && swipes < 10 {
            if target.waitForExistence(timeout: 3) && target.isHittable { break }
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(target.waitForExistence(timeout: 30), "\(target) never appeared")
    }

    @MainActor
    private func closeSettings(_ app: XCUIApplication) {
        let done = app.buttons["settingsDone"].firstMatch
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
    }

    @MainActor
    private func waitForValue(_ field: XCUIElement, _ expected: String) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let result = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: field)], timeout: 30)
        let shown = field.value as? String ?? ""
        XCTAssertEqual(result, .completed, "the field never showed \(expected): \(shown)")
    }

    /// Replaces the text of a color field and presses return.
    @MainActor
    private func enterHex(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        reveal(app, field)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text + "\n")
    }

    @MainActor
    func testAnInvalidHexShowsAnErrorAndAValidOneClearsIt() {
        let app = launch()
        openSettings(app)

        let field = element(app, "colorField.heading")
        enterHex(app, field, "XYZ")
        let error = element(app, "colorError")
        XCTAssertTrue(error.waitForExistence(timeout: 30), "no error for a bad hex")

        enterHex(app, field, "7C3AED")
        let gone = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"), object: error)
            ], timeout: 30)
        XCTAssertEqual(gone, .completed, "the error stayed after a valid hex")
    }

    @MainActor
    func testResetColorsRestoresTheDefaults() {
        let app = launch()
        openSettings(app)

        let field = element(app, "colorField.heading")
        enterHex(app, field, "7C3AED")
        waitForValue(field, "7C3AED")

        let reset = app.buttons["resetColorsButton"].firstMatch
        reveal(app, reset)
        reset.tap()
        waitForValue(field, "215E99")
    }

    @MainActor
    func testChoosingAFontAndRenderingReachesThePreview() {
        let app = launch()
        openSettings(app)

        let option = app.buttons["fontOption.jetbrains_mono"].firstMatch
        reveal(app, option)
        option.tap()
        closeSettings(app)

        let render = app.buttons["renderButton"].firstMatch
        XCTAssertTrue(render.waitForExistence(timeout: 30), "the Render button never appeared")
        render.tap()
        XCTAssertTrue(
            element(app, "pdfPreview").waitForExistence(timeout: 30), "the preview never appeared")
    }

    @MainActor
    func testTheClientIDIsShownAndChangeOpensTheSetupSheet() {
        let app = launch()
        openSettings(app)

        let label = element(app, "clientIDLabel")
        reveal(app, label)
        XCTAssertEqual(label.label, Self.fixtureClientID)

        let change = app.buttons["changeClientButton"].firstMatch
        reveal(app, change)
        change.tap()
        XCTAssertTrue(
            element(app, "clientIDField").waitForExistence(timeout: 30),
            "the client sheet never opened")
    }

    @MainActor
    func testForgettingTheClientReturnsToSetup() {
        let app = launch()
        openSettings(app)

        let forget = app.buttons["forgetClientButton"].firstMatch
        reveal(app, forget)
        forget.tap()
        let confirm = app.buttons["Forget"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "no confirmation appeared")
        confirm.tap()
        XCTAssertTrue(
            element(app, "clientIDField").waitForExistence(timeout: 30),
            "the setup screen never appeared")
    }

    @MainActor
    func testChoosingNoDelegatedListRemovesTheDelegatedPage() {
        let app = launch()
        openSettings(app)

        let picker = app.buttons["delegatedListPicker"].firstMatch
        reveal(app, picker)
        picker.tap()
        let none = app.buttons["None"].firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 30), "the None option never appeared")
        none.tap()
        closeSettings(app)

        let row = element(app, "delegatedRow.0")
        let gone = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"), object: row)
            ], timeout: 30)
        XCTAssertEqual(gone, .completed, "the delegated row stayed after choosing None")
    }

    @MainActor
    func testTheRulesLinkAndTheVersionAreThere() {
        let app = launch()
        openSettings(app)

        reveal(app, element(app, "rulesLink"))
        XCTAssertTrue(element(app, "rulesLink").exists)
        reveal(app, element(app, "version"))
        XCTAssertTrue(element(app, "version").exists)
    }

    @MainActor
    func testSigningOutReturnsToSignIn() {
        let app = launch()
        openSettings(app)

        let signOut = app.buttons["signOutButton"].firstMatch
        reveal(app, signOut)
        signOut.tap()
        XCTAssertTrue(
            app.buttons["signInButton"].waitForExistence(timeout: 30),
            "the sign-in button never appeared")
    }
}
