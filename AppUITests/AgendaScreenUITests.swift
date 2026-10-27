// The agenda screen, driven through the accessibility tree against the fixtures.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `AgendaView.ID` and
// `RowID`, never by their visible text, except a row's context-menu item, which has none; text is
// otherwise only read to check what a row says.

import XCTest

final class AgendaScreenUITests: XCTestCase {
    /// What a render shows.
    private static let previewID = "binderView"

    /// Drags the list up until `element` exists, at most 40 times.
    @MainActor
    private func scrollToExist(_ element: XCUIElement, in list: XCUIElement) {
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        var attempts = 0
        while !element.exists && attempts < 40 {
            start.press(forDuration: 0.05, thenDragTo: end)
            attempts += 1
        }
    }

    @MainActor
    func testStandardDayListsEveryRowWithItsReason() {
        let app = XCUIApplication.launchMagenda()
        XCTAssertTrue(app.element("agendaScreen").waitForExistence(timeout: 30))

        // Rows are created lazily, so the list is scrolled down one row at a time.
        let checks: [(String, String?, String?)] = [
            ("eventRow.0", "eventReason.0", "Personal block"),
            ("eventRow.1", nil, nil),
            ("eventRow.2", nil, nil),
            ("eventRow.3", nil, nil),
            ("eventRow.4", nil, nil),
            ("eventRow.5", "eventReason.5", "Declined"),
            ("eventRow.6", nil, nil),
            ("eventRow.7", nil, nil),
            ("eventRow.8", "eventReason.8", "Duplicate"),
            ("eventRow.9", "eventReason.9", "Not on the schedule"),
            ("taskRow.0", nil, nil),
            ("taskRow.1", nil, nil),
            ("taskRow.2", "taskReason.2", "no meeting with Nora"),
            ("taskRow.3", nil, nil),
            ("taskRow.4", nil, nil),
            ("delegatedRow.0", "delegatedMarked.0", "Check-in due"),
            ("delegatedRow.1", nil, nil),
            ("delegatedRow.2", nil, nil),
        ]
        let list = app.element("agendaScreen")
        for (row, reason, text) in checks {
            scrollToExist(app.element(row), in: list)
            XCTAssertTrue(app.element(row).exists, "\(row) is missing")
            if let reason, let text {
                scrollToExist(app.element(reason), in: list)
                XCTAssertTrue(app.element(reason).exists, "\(reason) is missing")
                XCTAssertTrue(
                    app.element(reason).label.contains(text), "\(reason) doesn't say \(text)")
            }
        }
        XCTAssertFalse(app.element("delegatedMarked.1").exists)
    }

    @MainActor
    func testTurningAnEventOffRemovesItsNotesPageSwitch() {
        let app = XCUIApplication.launchMagenda()
        XCTAssertTrue(app.element("eventRow.1").waitForExistence(timeout: 30))
        XCTAssertTrue(app.element("eventPageToggle.1").exists)
        XCTAssertFalse(app.element("eventPageToggle.0").exists)

        // The event is turned off through the row's context menu: a switch in the split view's
        // sidebar rarely takes a synthesized touch (ADR 0046). Each attempt presses the row, waits
        // for the menu item to be hittable and taps it, while the event is still included (the
        // notes-page switch only exists then).
        let page = app.element("eventPageToggle.1")
        let leaveOut = app.buttons["Leave out"].firstMatch
        var attempts = 0
        while page.exists && attempts < 5 {
            app.element("eventRow.1").press(forDuration: 1.2)
            attempts += 1
            guard leaveOut.waitForExistence(timeout: 10) else { continue }
            if leaveOut.waitUntil(\.isHittable, is: true, timeout: 10) {
                leaveOut.tap()
            }
            _ = page.waitForNonExistence(timeout: 10)
        }
        XCTAssertFalse(page.exists, "the notes-page switch is still there after \(attempts) tries")
    }

    @MainActor
    func testNextDayChangesTheDatePicker() {
        let app = XCUIApplication.launchMagenda()
        let picker = app.datePickers["datePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 30), "the date picker never appeared")
        // The picker exists a moment before its button carries the date.
        let shown = expectation(
            for: NSPredicate { _, _ in !self.shownDate(picker).isEmpty }, evaluatedWith: nil)
        wait(for: [shown], timeout: 10)
        let before = shownDate(picker)
        XCTAssertFalse(before.isEmpty, "the date picker shows no date")

        app.buttons["nextDayButton"].tap()
        let changed = expectation(
            for: NSPredicate { _, _ in self.shownDate(picker) != before }, evaluatedWith: nil)
        wait(for: [changed], timeout: 10)
    }

    /// The date a compact date picker shows: the value of the button inside it, or its own.
    @MainActor
    private func shownDate(_ picker: XCUIElement) -> String {
        let button = picker.buttons.firstMatch
        return (button.exists ? button.value : picker.value) as? String ?? ""
    }

    @MainActor
    func testOutOfOfficeShowsANoticeAndTheNextWorkingDayButton() {
        let app = XCUIApplication.launchMagenda(fixture: "outOfOffice")
        XCTAssertTrue(app.element("notice.0").waitForExistence(timeout: 30), "no notice shown")
        XCTAssertTrue(app.element("nextWorkingDayButton").exists)
    }

    @MainActor
    func testRenderShowsThePreview() {
        let app = XCUIApplication.launchMagenda()
        let render = app.buttons["renderButton"]
        XCTAssertTrue(render.waitForExistence(timeout: 30), "the Render button never appeared")
        XCTAssertTrue(app.element("eventRow.0").waitForExistence(timeout: 30))
        render.tap()

        XCTAssertTrue(
            app.element(Self.previewID).waitForExistence(timeout: 30),
            "the preview never appeared")
        // The list's first row stands for the list: XCUITest never reports a List itself as
        // hittable once the centre of its frame lands on one of its rows, on any device.
        let row = app.element("eventRow.0")
        XCTAssertTrue(row.isHittable, "the list is hidden beside the preview on iPad")
    }
}
