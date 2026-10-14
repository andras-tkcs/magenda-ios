// The edit sheet and the Agenda menu's shortcuts, driven through the accessibility tree against
// the fixtures.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `EditTextSheet.ID`,
// `AgendaView.ID` and `RowID`, never by their visible text.

import UIKit
import XCTest

final class AgendaEditUITests: XCTestCase {
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
        let list = element(app, "agendaScreen")
        XCTAssertTrue(list.waitForExistence(timeout: 30), "the list never appeared")
        let row = app.buttons[identifier]
        _ = row.waitForExistence(timeout: 30)
        scrollToHittable(row, in: list)
        let field = element(app, "editField")
        var taps = 0
        while !field.exists && taps < 5 {
            row.tap()
            taps += 1
            _ = field.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(field.exists, "the edit sheet never opened after \(taps) taps")
        return field
    }

    /// Replaces the field's text with `text`.
    @MainActor
    private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = field.value as? String ?? ""
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
        field.typeText(deletes + text)
    }

    @MainActor
    func testDoneChangesTheTaskRow() {
        let app = launch()
        let field = openEditor(app, row: "taskRow.0")
        replaceText(field, with: "Call the plumber")
        app.buttons["editDone"].firstMatch.tap()

        XCTAssertEqual(
            waitForLabel(app.buttons["taskRow.0"], "Call the plumber"), "Call the plumber",
            "the task row still has its old text")
        XCTAssertFalse(element(app, "editField").exists)
    }

    @MainActor
    func testCancelLeavesTheTaskRowUnchanged() {
        let app = launch()
        let field = openEditor(app, row: "taskRow.0")
        let before = app.buttons["taskRow.0"].label
        replaceText(field, with: "Something else")
        app.buttons["editCancel"].firstMatch.tap()

        XCTAssertTrue(
            element(app, "editField").waitForNonExistence(timeout: 30), "the sheet stayed open")
        XCTAssertEqual(app.buttons["taskRow.0"].label, before)
    }

    @MainActor
    func testOnlyAnEventOffersToRememberItsName() {
        let app = launch()
        _ = openEditor(app, row: "eventRow.4")
        XCTAssertTrue(element(app, "editRemember").exists, "an event has no remember switch")
        app.buttons["editCancel"].firstMatch.tap()
        XCTAssertTrue(element(app, "editField").waitForNonExistence(timeout: 30))

        _ = openEditor(app, row: "taskRow.0")
        XCTAssertFalse(element(app, "editRemember").exists, "a task has a remember switch")
    }

    @MainActor
    func testRememberingAnEventNameShowsItAsThePageTitle() {
        let app = launch()
        let field = openEditor(app, row: "eventRow.4")
        replaceText(field, with: "Office move")

        let remember = element(app, "editRemember")
        let toggle = app.switches["editRemember"].exists ? app.switches["editRemember"] : remember
        let target = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        var taps = 0
        while (target.value as? String) != "1" && taps < 5 {
            target.tap()
            taps += 1
        }
        XCTAssertEqual(target.value as? String, "1", "the remember switch did not turn on")
        app.buttons["editDone"].firstMatch.tap()

        let reason = element(app, "eventReason.4")
        XCTAssertTrue(reason.waitForExistence(timeout: 30), "eventReason.4 never appeared")
        XCTAssertTrue(
            reason.label.contains("Page title: Office move"),
            "the reason says \(reason.label)")
    }

    @MainActor
    func testCommandRShowsThePreviewOnIPad() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad, "keyboard shortcuts are an iPad feature")
        let app = launch()
        XCTAssertTrue(element(app, "eventRow.0").waitForExistence(timeout: 30))
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(
            element(app, "pdfPreview").waitForExistence(timeout: 30),
            "⌘R did not render the agenda")
    }

    /// Waits up to 30 seconds for `element`'s label to become `label`; returns the final label.
    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String) -> String {
        let changed = expectation(
            for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        _ = XCTWaiter().wait(for: [changed], timeout: 30)
        return element.label
    }
}
