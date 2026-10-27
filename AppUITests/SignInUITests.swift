// Signing in, driven through the accessibility tree against the fixture account.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `SignInView.ID` and
// `AgendaView.ID`, never by their visible text.

import XCTest

final class SignInUITests: XCTestCase {
    @MainActor
    func testSignedOutShowsSignInAndSigningInReachesTheAgenda() {
        let app = XCUIApplication.launchMagenda(["-MagendaSignedOut"])

        let button = app.buttons["signInButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "the sign-in button never appeared")
        button.tap()

        let agenda = app.element("agendaScreen")
        XCTAssertTrue(agenda.waitForExistence(timeout: 10), "the agenda never appeared")
    }

    @MainActor
    func testSignedInGoesStraightToTheAgenda() {
        let app = XCUIApplication.launchMagenda()

        let agenda = app.element("agendaScreen")
        XCTAssertTrue(agenda.waitForExistence(timeout: 10), "the agenda never appeared")
        XCTAssertFalse(app.buttons["signInButton"].exists, "the sign-in button was shown")
    }
}
