// The settings sheet, driven through the accessibility tree against fixtures.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `SettingsView.ID`
// and `AgendaView.ID`, never by their visible text, except for menu options and dialog buttons,
// which have none.

import UIKit
import XCTest

final class SettingsUITests: XCTestCase {
    private static let fixtureClientID = "123456789012-fixture.apps.googleusercontent.com"

    /// What a render shows: the binder on iPad, the PDF preview on iPhone.
    @MainActor private static var previewID: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "binderView" : "pdfPreview"
    }

    @MainActor
    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MagendaFixture", "standard"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Waits for the list, then opens the settings sheet, retrying a dropped tap.
    @MainActor
    private func openSettings(_ app: XCUIApplication, listIsScrolled: Bool = false) {
        // A list scrolled down has no first row: it is lazy, and the row is off screen.
        let listRow = listIsScrolled ? "agendaScreen" : "eventRow.0"
        XCTAssertTrue(
            element(app, listRow).waitForExistence(timeout: 30), "the list never appeared")
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

    /// Drags the form by `distance` points (positive scrolls further down the form). The drag
    /// starts below the sheet's Done button, so it lands in the form on a phone and in the iPad's
    /// form sheet alike, and it holds at the end so the form does not fling past a row.
    @MainActor
    private func drag(_ app: XCUIApplication, by distance: CGFloat) {
        let done = app.buttons["settingsDone"].firstMatch
        let center = done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let anchor = center.withOffset(CGVector(dx: -150, dy: 275))
        let start = anchor.withOffset(CGVector(dx: 0, dy: distance / 2))
        let end = anchor.withOffset(CGVector(dx: 0, dy: -distance / 2))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 300, thenHoldForDuration: 0.3)
    }

    /// Scrolls the form in short drags until `target` can be tapped. A lazy row does not exist
    /// until it is scrolled near, so a missing target is looked for further down first and then
    /// back up. With `upperHalf`, the target also has to sit in the top half of the screen, clear
    /// of the keyboard that tapping a text field brings up.
    @MainActor
    private func reveal(_ app: XCUIApplication, _ target: XCUIElement, upperHalf: Bool = false) {
        let done = app.buttons["settingsDone"].firstMatch
        let bottom = upperHalf ? app.windows.firstMatch.frame.height / 2 : .greatestFiniteMagnitude
        var drags = 0
        while drags < 30 {
            if target.waitForExistence(timeout: 2) {
                let top = done.frame.maxY + 40
                let mid = target.frame.midY
                if mid < top {
                    drag(app, by: -150)
                } else if target.isHittable && mid <= bottom {
                    break
                } else {
                    drag(app, by: 150)
                }
            } else {
                drag(app, by: drags < 15 ? 150 : -150)
            }
            drags += 1
        }
        XCTAssertTrue(target.exists && target.isHittable, "\(target) was never scrolled into view")
    }

    /// Swipes the agenda list up until `target` exists (or, without one, `swipes` times). Rows are
    /// lazy, so a row below the fold does not exist until it is scrolled near; the iPad's list
    /// never reports a row hittable, so existence is what is waited for.
    @MainActor
    private func scrollList(_ app: XCUIApplication, until target: XCUIElement? = nil) {
        let list = element(app, "agendaScreen")
        XCTAssertTrue(list.waitForExistence(timeout: 30), "the list never appeared")
        var swipes = 0
        while swipes < 8 && !(target?.exists ?? false) {
            list.swipeUp()
            swipes += 1
        }
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

    /// Replaces the text of a color field and presses return. The keys go to whatever has focus
    /// rather than to the field, which an iPad's form sheet may briefly drop from the accessibility
    /// tree while it makes room for the keyboard.
    @MainActor
    private func enterHex(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        reveal(app, field, upperHalf: true)
        let current = field.value as? String ?? ""
        // A tap at the right edge puts the caret after the text, so the deletes clear all of it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
        app.typeText(deletes + text + "\n")
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

    /// Naming the Drive folder: a name with a slash shows the error, a valid one clears it and the
    /// footer names the new folder.
    @MainActor
    func testAFolderNameIsSavedAndAnInvalidOneShowsAnError() {
        let app = launch()
        openSettings(app)

        let footer = element(app, "driveFolderFooter")
        reveal(app, footer)
        XCTAssertTrue(footer.label.contains("“Magenda”"), "the footer did not name the default")

        let field = element(app, "driveFolderField")
        enterHex(app, field, "a/b")
        let error = element(app, "driveFolderError")
        XCTAssertTrue(error.waitForExistence(timeout: 30), "no error for a name with a slash")

        enterHex(app, field, "Work notes")
        let saved = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"), object: error),
                XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label CONTAINS %@", "“Work notes”"),
                    object: footer),
            ], timeout: 30)
        XCTAssertEqual(saved, .completed, "the folder name was not saved")
    }

    @MainActor
    func testResetColorsRestoresTheDefaults() {
        let app = launch()
        openSettings(app)

        let field = element(app, "colorField.heading")
        enterHex(app, field, "7C3AED")
        reveal(app, field)
        waitForValue(field, "7C3AED")

        let reset = app.buttons["resetColorsButton"].firstMatch
        reveal(app, reset)
        reset.tap()
        reveal(app, field)
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
            element(app, Self.previewID).waitForExistence(timeout: 30),
            "the preview never appeared")
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
        // A tap that lands while the form is still settling from the drag is dropped, so the
        // button is tapped again while the confirmation has not appeared.
        let confirm = app.buttons["Forget"].firstMatch
        var taps = 0
        while !confirm.exists && taps < 5 {
            forget.tap()
            taps += 1
            _ = confirm.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(confirm.exists, "no confirmation appeared after \(taps) taps")
        confirm.tap()
        XCTAssertTrue(
            element(app, "clientIDField").waitForExistence(timeout: 30),
            "the setup screen never appeared")
    }

    @MainActor
    func testChoosingNoDelegatedListRemovesTheDelegatedPage() {
        let app = launch()
        let row = element(app, "delegatedRow.0")
        XCTAssertTrue(
            element(app, "eventRow.0").waitForExistence(timeout: 30), "the list never appeared")
        scrollList(app, until: row)
        XCTAssertTrue(row.exists, "the fixture shows no delegated row to begin with")
        openSettings(app, listIsScrolled: true)

        let picker = app.buttons["delegatedListPicker"].firstMatch
        reveal(app, picker)
        picker.tap()
        let none = app.buttons["None"].firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 30), "the None option never appeared")
        none.tap()
        closeSettings(app)

        // The reload puts the list back at its top: wait for it, then look at the whole list.
        XCTAssertTrue(
            element(app, "eventRow.0").waitForExistence(timeout: 30),
            "the list never came back after the reload")
        scrollList(app)
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

    /// Types into a text field of the settings form: scrolls it clear of the keyboard, taps it,
    /// and types.
    @MainActor
    private func enterText(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        reveal(app, field, upperHalf: true)
        field.tap()
        app.typeText(text)
    }

    @MainActor
    func testAnInvalidRoutineShowsAnErrorAndAValidOneIsSaved() {
        let app = launch(["-MagendaNoRoutine"])
        openSettings(app)

        enterText(app, element(app, "routineURLField"), "https://example.com/fire")
        enterText(app, element(app, "routineTokenField"), "sk-ant-oat01-test")
        let save = app.buttons["saveRoutineButton"].firstMatch
        reveal(app, save, upperHalf: true)
        save.tap()
        XCTAssertTrue(
            element(app, "routineError").waitForExistence(timeout: 30),
            "no error for a bad fire URL")

        let urlField = element(app, "routineURLField")
        reveal(app, urlField, upperHalf: true)
        // A tap at the right edge puts the caret after the text, so the deletes clear all of it.
        let current = urlField.value as? String ?? ""
        urlField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
        app.typeText(deletes + "https://api.anthropic.com/v1/claude_code/routines/trig_ui/fire")
        reveal(app, save, upperHalf: true)
        save.tap()
        let status = element(app, "routineStatusLabel")
        XCTAssertTrue(status.waitForExistence(timeout: 30), "the routine was never saved")
        XCTAssertTrue(status.label.contains("trig_"), "the status named no trigger")
    }

    @MainActor
    func testForgettingTheRoutineBringsBackTheFields() {
        let app = launch()
        openSettings(app)

        let status = element(app, "routineStatusLabel")
        reveal(app, status)
        XCTAssertTrue(status.label.contains("trig_fixture"), "the fixture routine is not shown")

        let forget = app.buttons["forgetRoutineButton"].firstMatch
        reveal(app, forget)
        forget.tap()
        XCTAssertTrue(
            element(app, "routineURLField").waitForExistence(timeout: 30),
            "the fire URL field never came back")
    }
}
