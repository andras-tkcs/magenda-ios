// The edit sheet and the Agenda menu's shortcuts, driven through the accessibility tree against
// the fixtures.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `EditTextSheet.ID`,
// `AgendaView.ID` and `RowID`, never by their visible text.

import XCTest

final class AgendaEditUITests: XCTestCase {
    /// What a render shows.
    private static let previewID = "binderView"

    /// Drags the list up until `row` can be tapped, at most 40 times.
    @MainActor
    private func scrollToHittable(_ row: XCUIElement, in list: XCUIElement) {
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        var attempts = 0
        while !(row.exists && row.isHittable) && attempts < 40 {
            start.press(forDuration: 0.05, thenDragTo: end)
            attempts += 1
        }
    }

    /// Opens the edit sheet for `row`. On an iPad simulator a synthesized tap in the split view's
    /// sidebar is sometimes dropped, so the row is tapped again while the sheet has not appeared.
    @MainActor
    private func openEditor(_ app: XCUIApplication, row identifier: String) -> XCUIElement {
        let list = app.element("agendaScreen")
        XCTAssertTrue(list.waitForExistence(timeout: 30), "the list never appeared")
        let row = app.buttons[identifier]
        // Rows are created lazily, so a row further down only exists once it is scrolled to.
        XCTAssertTrue(
            app.buttons["eventRow.0"].waitForExistence(timeout: 30), "the first row never appeared")
        scrollToHittable(row, in: list)
        XCTAssertTrue(row.exists && row.isHittable, "\(identifier) was never scrolled into view")
        let field = app.element("editField")
        var taps = 0
        while !field.exists && taps < 5 {
            row.tap()
            taps += 1
            _ = field.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(field.exists, "the edit sheet never opened after \(taps) taps")
        return field
    }

    /// Replaces the field's text with `text`. The keys go to whatever has focus rather than to the
    /// field, which the sheet may briefly drop from the accessibility tree while it makes room for
    /// the keyboard.
    @MainActor
    private func replaceText(_ app: XCUIApplication, _ field: XCUIElement, with text: String) {
        // A tap at the right edge puts the caret after the text, so the deletes clear all of it.
        field.focusForTyping(in: app, at: 0.98)
        let current = field.value as? String ?? ""
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
        app.typeText(deletes + text)
    }

    @MainActor
    func testDoneChangesTheTaskRow() {
        let app = XCUIApplication.launchMagenda()
        let field = openEditor(app, row: "taskRow.0")
        replaceText(app, field, with: "Call the plumber")
        app.buttons["editDone"].firstMatch.tap()

        XCTAssertEqual(
            waitForLabel(app.buttons["taskRow.0"], "Call the plumber"), "Call the plumber",
            "the task row still has its old text")
        XCTAssertFalse(app.element("editField").exists)
    }

    @MainActor
    func testCancelLeavesTheTaskRowUnchanged() {
        let app = XCUIApplication.launchMagenda()
        let field = openEditor(app, row: "taskRow.0")
        let before = app.buttons["taskRow.0"].label
        replaceText(app, field, with: "Something else")
        app.buttons["editCancel"].firstMatch.tap()

        XCTAssertTrue(
            app.element("editField").waitForNonExistence(timeout: 30), "the sheet stayed open")
        XCTAssertEqual(app.buttons["taskRow.0"].label, before)
    }

    @MainActor
    func testOnlyAnEventOffersToRememberItsName() {
        let app = XCUIApplication.launchMagenda()
        _ = openEditor(app, row: "eventRow.4")
        XCTAssertTrue(app.element("editRemember").exists, "an event has no remember switch")
        app.buttons["editCancel"].firstMatch.tap()
        XCTAssertTrue(app.element("editField").waitForNonExistence(timeout: 30))

        _ = openEditor(app, row: "taskRow.0")
        XCTAssertFalse(app.element("editRemember").exists, "a task has a remember switch")
    }

    @MainActor
    func testRememberingAnEventNameShowsItAsThePageTitle() {
        let app = XCUIApplication.launchMagenda()
        let field = openEditor(app, row: "eventRow.4")
        replaceText(app, field, with: "Office move")

        let remember = app.element("editRemember")
        let toggle = app.switches["editRemember"].exists ? app.switches["editRemember"] : remember
        let target = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        var taps = 0
        while (target.value as? String) != "1" && taps < 5 {
            target.tapSwitch(attempt: taps)
            taps += 1
        }
        XCTAssertEqual(target.value as? String, "1", "the remember switch did not turn on")
        app.buttons["editDone"].firstMatch.tap()

        let reason = app.element("eventReason.4")
        XCTAssertTrue(reason.waitForExistence(timeout: 30), "eventReason.4 never appeared")
        XCTAssertTrue(
            reason.label.contains("Page title: Office move"),
            "the reason says \(reason.label)")
    }

    /// The switch inside the toggle `identifier`, once the sheet is scrolled to it.
    @MainActor
    private func summarySwitch(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let toggle = app.element(identifier)
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), "\(identifier) never appeared")
        let form = app.collectionViews.firstMatch
        var swipes = 0
        while !toggle.isHittable && swipes < 5 {
            form.swipeUp()
            swipes += 1
        }
        return toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
    }

    @MainActor
    func testTickingASummaryRoutineIsKeptWhenTheSheetIsReopened() {
        let app = XCUIApplication.launchMagenda()
        _ = openEditor(app, row: "eventRow.1")
        XCTAssertTrue(app.element("editSummary.1").waitForExistence(timeout: 30))
        let first = summarySwitch(app, "editSummary.0")
        var taps = 0
        while (first.value as? String) != "1" && taps < 5 {
            first.tapSwitch(attempt: taps)
            taps += 1
        }
        XCTAssertEqual(first.value as? String, "1", "the first summary did not turn on")
        app.buttons["editDone"].firstMatch.tap()
        XCTAssertTrue(
            app.element("editField").waitForNonExistence(timeout: 30), "the sheet stayed open")

        _ = openEditor(app, row: "eventRow.1")
        XCTAssertEqual(
            summarySwitch(app, "editSummary.0").value as? String, "1",
            "the ticked summary was not kept")
        XCTAssertNotEqual(summarySwitch(app, "editSummary.1").value as? String, "1")
    }

    @MainActor
    func testWithoutSummaryRoutinesTheSheetHasNoSummaries() {
        let app = XCUIApplication.launchMagenda(["-MagendaNoSummaryRoutines"])
        _ = openEditor(app, row: "eventRow.1")
        XCTAssertFalse(app.element("editSummary.0").exists, "a summary toggle was offered")
    }

    @MainActor
    func testCommandRShowsThePreviewOnIPad() {
        let app = XCUIApplication.launchMagenda()
        XCTAssertTrue(app.element("eventRow.0").waitForExistence(timeout: 30))
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(
            app.element(Self.previewID).waitForExistence(timeout: 30),
            "⌘R did not render the agenda")
    }

    /// Waits up to 30 seconds for `element`'s label to become `label`; returns the final label.
    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String) -> String {
        element.waitUntil(\.label, is: label)
        return element.label
    }
}
