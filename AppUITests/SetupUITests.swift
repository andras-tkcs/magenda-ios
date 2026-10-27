// Entering the Google client, driven through the accessibility tree against fixtures.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `SetupView.ID` and
// `SignInView.ID`, never by their visible text.

import XCTest

final class SetupUITests: XCTestCase {
    @MainActor
    func testBadClientIDShowsAMessageAndAValidOneReachesSignIn() {
        let app = XCUIApplication.launchMagenda(["-MagendaNeedsSetup", "-MagendaSignedOut"])

        let field = app.textFields["clientIDField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the client ID field never appeared")
        let save = app.buttons["saveClientButton"]
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled, "Save was enabled with an empty client ID")

        field.focusForTyping(in: app)
        app.typeText("not-an-id")
        save.tap()
        let message = app.element("setupMessage")
        XCTAssertTrue(message.waitForExistence(timeout: 10), "no message for a bad client ID")

        field.focusForTyping(in: app)
        field.clearText()
        app.typeText("123456789012-test.apps.googleusercontent.com")
        save.tap()
        XCTAssertTrue(
            app.buttons["signInButton"].waitForExistence(timeout: 10),
            "the sign-in button never appeared after saving")
    }
}

extension XCUIElement {
    /// Deletes the text of a text field one character at a time.
    fileprivate func clearText() {
        guard let text = value as? String else { return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
    }
}
