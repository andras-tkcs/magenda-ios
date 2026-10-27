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

    /// Launches straight into the settings sheet and waits for its Done button.
    @MainActor
    private func launchIntoSettings(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.launchMagenda(["-MagendaOpen", "settings"] + extraArguments)
        XCTAssertTrue(
            app.buttons["settingsDone"].firstMatch.waitForExistence(timeout: 30),
            "the settings sheet never opened")
        return app
    }

    /// The settings form, which the scroll helpers drag.
    @MainActor
    private func settingsForm(_ app: XCUIApplication) -> XCUIElement {
        app.element("settingsForm")
    }

    /// The bottom limit for a field about to be typed into: the top half of the screen, clear of
    /// the keyboard.
    @MainActor
    private func upperHalf(_ app: XCUIApplication) -> CGFloat {
        app.windows.firstMatch.frame.height / 2
    }

    /// Waits for the list, then opens the settings sheet, retrying a dropped tap.
    @MainActor
    private func openSettings(_ app: XCUIApplication, listIsScrolled: Bool = false) {
        // A list scrolled down has no first row: it is lazy, and the row is off screen.
        let listRow = listIsScrolled ? "agendaScreen" : "eventRow.0"
        XCTAssertTrue(
            app.element(listRow).waitForExistence(timeout: 30), "the list never appeared")
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

    /// Swipes the agenda list up until `target` exists (or, without one, `swipes` times). Rows are
    /// lazy, so a row below the fold does not exist until it is scrolled near; the iPad's list
    /// never reports a row hittable, so existence is what is waited for.
    @MainActor
    private func scrollList(_ app: XCUIApplication, until target: XCUIElement? = nil) {
        let list = app.element("agendaScreen")
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
            _ = done.waitForNonExistence(timeout: 10)
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

    /// Waits until a text field is empty again. An empty field reports its placeholder, or nothing,
    /// as its value, depending on the runtime, so both count as cleared.
    @MainActor
    private func waitForClearedField(_ field: XCUIElement, placeholder: String) {
        let predicate = NSPredicate(
            format: "value == nil OR value == %@ OR value == %@", "", placeholder)
        let result = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: field)], timeout: 30)
        let shown = field.value as? String ?? ""
        XCTAssertEqual(result, .completed, "the field never cleared: \(shown)")
    }

    /// Replaces the text of a color field and presses return. The keys go to whatever has focus
    /// rather than to the field, which an iPad's form sheet may briefly drop from the accessibility
    /// tree while it makes room for the keyboard.
    @MainActor
    private func enterHex(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        field.reveal(in: settingsForm(app), bottom: upperHalf(app))
        let current = field.value as? String ?? ""
        // A tap at the right edge puts the caret after the text, so the deletes clear all of it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
        app.typeText(deletes + text + "\n")
    }

    @MainActor
    func testAnInvalidHexShowsAnErrorAndAValidOneClearsIt() {
        let app = launchIntoSettings()

        let field = app.element("colorField.heading")
        enterHex(app, field, "XYZ")
        let error = app.element("colorError")
        XCTAssertTrue(error.waitForExistence(timeout: 30), "no error for a bad hex")

        enterHex(app, field, "7C3AED")
        XCTAssertTrue(
            error.waitForNonExistence(timeout: 30), "the error stayed after a valid hex")
    }

    /// Naming the Drive folder: a name with a slash shows the error, a valid one clears it and the
    /// footer names the new folder.
    @MainActor
    func testAFolderNameIsSavedAndAnInvalidOneShowsAnError() {
        let app = launchIntoSettings()

        let footer = app.element("driveFolderFooter")
        footer.reveal(in: settingsForm(app))
        XCTAssertTrue(footer.label.contains("“Magenda”"), "the footer did not name the default")

        let field = app.element("driveFolderField")
        enterHex(app, field, "a/b")
        let error = app.element("driveFolderError")
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
        let app = launchIntoSettings()

        let field = app.element("colorField.heading")
        enterHex(app, field, "7C3AED")
        field.reveal(in: settingsForm(app))
        waitForValue(field, "7C3AED")

        let reset = app.buttons["resetColorsButton"].firstMatch
        reset.reveal(in: settingsForm(app))
        reset.tap()
        field.reveal(in: settingsForm(app))
        waitForValue(field, "215E99")
    }

    @MainActor
    func testChoosingAFontAndRenderingReachesThePreview() {
        let app = launchIntoSettings()

        let option = app.buttons["fontOption.jetbrains_mono"].firstMatch
        option.reveal(in: settingsForm(app))
        option.tap()
        closeSettings(app)

        let render = app.buttons["renderButton"].firstMatch
        XCTAssertTrue(render.waitForExistence(timeout: 30), "the Render button never appeared")
        render.tap()
        XCTAssertTrue(
            app.element(Self.previewID).waitForExistence(timeout: 30),
            "the preview never appeared")
    }

    @MainActor
    func testTheClientIDIsShownAndChangeOpensTheSetupSheet() {
        let app = launchIntoSettings()

        let label = app.element("clientIDLabel")
        label.reveal(in: settingsForm(app))
        XCTAssertEqual(label.label, Self.fixtureClientID)

        let change = app.buttons["changeClientButton"].firstMatch
        change.reveal(in: settingsForm(app))
        change.tap()
        XCTAssertTrue(
            app.element("clientIDField").waitForExistence(timeout: 30),
            "the client sheet never opened")
    }

    @MainActor
    func testForgettingTheClientReturnsToSetup() {
        let app = launchIntoSettings()

        let forget = app.buttons["forgetClientButton"].firstMatch
        forget.reveal(in: settingsForm(app))
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
            app.element("clientIDField").waitForExistence(timeout: 30),
            "the setup screen never appeared")
    }

    @MainActor
    func testChoosingNoDelegatedListRemovesTheDelegatedPage() {
        let app = XCUIApplication.launchMagenda()
        let row = app.element("delegatedRow.0")
        XCTAssertTrue(
            app.element("eventRow.0").waitForExistence(timeout: 30), "the list never appeared")
        scrollList(app, until: row)
        XCTAssertTrue(row.exists, "the fixture shows no delegated row to begin with")
        openSettings(app, listIsScrolled: true)

        let picker = app.buttons["delegatedListPicker"].firstMatch
        picker.reveal(in: settingsForm(app))
        picker.tap()
        let none = app.buttons["None"].firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 30), "the None option never appeared")
        none.tap()
        closeSettings(app)

        // The reload puts the list back at its top: wait for it, then look at the whole list.
        XCTAssertTrue(
            app.element("eventRow.0").waitForExistence(timeout: 30),
            "the list never came back after the reload")
        scrollList(app)
        XCTAssertTrue(
            row.waitForNonExistence(timeout: 30), "the delegated row stayed after choosing None")
    }

    @MainActor
    func testTheRulesLinkAndTheVersionAreThere() {
        let app = XCUIApplication.launchMagenda()
        openSettings(app)

        app.element("rulesLink").reveal(in: settingsForm(app))
        XCTAssertTrue(app.element("rulesLink").exists)
        app.element("version").reveal(in: settingsForm(app))
        XCTAssertTrue(app.element("version").exists)
    }

    @MainActor
    func testSigningOutReturnsToSignIn() {
        let app = launchIntoSettings()

        let signOut = app.buttons["signOutButton"].firstMatch
        signOut.reveal(in: settingsForm(app))
        signOut.tap()
        XCTAssertTrue(
            app.buttons["signInButton"].waitForExistence(timeout: 30),
            "the sign-in button never appeared")
    }

    /// Types into a text field of the settings form: scrolls it clear of the keyboard, taps it,
    /// and types.
    @MainActor
    private func enterText(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        field.reveal(in: settingsForm(app), bottom: upperHalf(app))
        field.tap()
        app.typeText(text)
    }

    @MainActor
    func testAnInvalidRoutineShowsAnErrorAndAValidOneIsSaved() {
        let app = launchIntoSettings(["-MagendaNoRoutine"])

        enterText(app, app.element("routineURLField"), "https://example.com/fire")
        enterText(app, app.element("routineTokenField"), "sk-ant-oat01-test")
        let save = app.buttons["saveRoutineButton"].firstMatch
        save.reveal(in: settingsForm(app), bottom: upperHalf(app))
        save.tap()
        XCTAssertTrue(
            app.element("routineError").waitForExistence(timeout: 30),
            "no error for a bad fire URL")

        let urlField = app.element("routineURLField")
        urlField.reveal(in: settingsForm(app), bottom: upperHalf(app))
        // A tap at the right edge puts the caret after the text, so the deletes clear all of it.
        let current = urlField.value as? String ?? ""
        urlField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
        app.typeText(deletes + "https://api.anthropic.com/v1/claude_code/routines/trig_ui/fire")
        save.reveal(in: settingsForm(app), bottom: upperHalf(app))
        save.tap()
        let status = app.element("routineStatusLabel")
        XCTAssertTrue(status.waitForExistence(timeout: 30), "the routine was never saved")
        XCTAssertTrue(status.label.contains("trig_"), "the status named no trigger")
    }

    @MainActor
    func testForgettingTheRoutineBringsBackTheFields() {
        let app = launchIntoSettings()

        let status = app.element("routineStatusLabel")
        status.reveal(in: settingsForm(app))
        XCTAssertTrue(status.label.contains("trig_fixture"), "the fixture routine is not shown")

        let forget = app.buttons["forgetRoutineButton"].firstMatch
        forget.reveal(in: settingsForm(app))
        forget.tap()
        XCTAssertTrue(
            app.element("routineURLField").waitForExistence(timeout: 30),
            "the fire URL field never came back")
    }

    private static let summaryFireURL =
        "https://api.anthropic.com/v1/claude_code/routines/trig_uisummary/fire"

    /// Fills the summary routine fields and taps Save.
    @MainActor
    private func saveSummaryRoutine(
        _ app: XCUIApplication, name: String, url: String, token: String
    ) {
        enterText(app, app.element("summaryRoutineNameField"), name)
        enterText(app, app.element("summaryRoutineURLField"), url)
        enterText(app, app.element("summaryRoutineTokenField"), token)
        let save = app.buttons["saveSummaryRoutineButton"].firstMatch
        save.reveal(in: settingsForm(app), bottom: upperHalf(app))
        save.tap()
    }

    @MainActor
    func testAddingASummaryRoutineShowsItsRowAndForgettingRemovesIt() {
        let app = launchIntoSettings()

        saveSummaryRoutine(
            app, name: "UI memo", url: Self.summaryFireURL, token: "sk-ant-oat01-test")
        // The fixture has two routines, so the new one is the third row.
        let row = app.element("summaryRoutineRow.2")
        row.reveal(in: settingsForm(app))
        XCTAssertEqual(row.label, "UI memo")

        let forget = app.buttons["forgetSummaryRoutineButton.2"].firstMatch
        forget.reveal(in: settingsForm(app))
        let confirm = app.buttons["Forget summary routine"].firstMatch
        var taps = 0
        while !confirm.exists && taps < 5 {
            forget.tap()
            taps += 1
            _ = confirm.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(confirm.exists, "no confirmation appeared after \(taps) taps")
        confirm.tap()
        XCTAssertTrue(
            row.waitForNonExistence(timeout: 30), "the summary routine row stayed after Forget")
    }

    @MainActor
    func testASummaryRoutineWithoutANameOrWithABadURLShowsAnError() {
        let app = launchIntoSettings()

        let save = app.buttons["saveSummaryRoutineButton"].firstMatch
        save.reveal(in: settingsForm(app), bottom: upperHalf(app))
        save.tap()
        let error = app.element("summaryRoutineError")
        XCTAssertTrue(error.waitForExistence(timeout: 30), "no error for an empty name")

        enterText(app, app.element("summaryRoutineNameField"), "UI memo")
        enterText(app, app.element("summaryRoutineURLField"), "https://example.com/fire")
        enterText(app, app.element("summaryRoutineTokenField"), "sk-ant-oat01-test")
        save.reveal(in: settingsForm(app), bottom: upperHalf(app))
        save.tap()
        XCTAssertTrue(
            app.element("summaryRoutineError").waitForExistence(timeout: 30),
            "no error for a bad fire URL")
        XCTAssertFalse(
            app.element("summaryRoutineRow.2").exists, "a routine was saved with a bad URL")
    }

    @MainActor
    func testSavingAnExistingSummaryRoutineNameKeepsOneRow() {
        let app = launchIntoSettings()

        saveSummaryRoutine(
            app, name: "Client memo", url: Self.summaryFireURL, token: "sk-ant-oat01-test")
        // The saved form clears its fields: wait for that, then look for a duplicate.
        let name = app.element("summaryRoutineNameField")
        name.reveal(in: settingsForm(app))
        waitForClearedField(name, placeholder: "Name")
        XCTAssertTrue(
            app.element("summaryRoutineRow.1").exists, "the fixture's second routine is gone")
        XCTAssertFalse(app.element("summaryRoutineRow.2").exists, "the routine was duplicated")
    }
}
