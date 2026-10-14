// The agenda screen, driven through the accessibility tree against the fixtures.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `AgendaView.ID` and
// `RowID`, never by their visible text; text is only read to check what a row says.

import UIKit
import XCTest

final class AgendaScreenUITests: XCTestCase {
    @MainActor
    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MagendaFixture", fixture]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

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
        let app = launch("standard")
        XCTAssertTrue(element(app, "agendaScreen").waitForExistence(timeout: 10))

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
        let list = element(app, "agendaScreen")
        for (row, reason, text) in checks {
            scrollToExist(element(app, row), in: list)
            XCTAssertTrue(element(app, row).exists, "\(row) is missing")
            if let reason, let text {
                scrollToExist(element(app, reason), in: list)
                XCTAssertTrue(element(app, reason).exists, "\(reason) is missing")
                XCTAssertTrue(
                    element(app, reason).label.contains(text), "\(reason) doesn't say \(text)")
            }
        }
        XCTAssertFalse(element(app, "delegatedMarked.1").exists)
    }

    @MainActor
    func testTurningAnEventOffRemovesItsNotesPageSwitch() {
        let app = launch("standard")
        XCTAssertTrue(element(app, "eventRow.1").waitForExistence(timeout: 30))
        XCTAssertTrue(element(app, "eventPageToggle.1").exists)
        XCTAssertFalse(element(app, "eventPageToggle.0").exists)

        // The tap goes to the system switch inside the toggle, not to the toggle's own frame.
        element(app, "eventToggle.1").switches.firstMatch.tap()
        let gone = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: element(app, "eventPageToggle.1"))
        wait(for: [gone], timeout: 10)
    }

    @MainActor
    func testNextDayChangesTheDatePicker() {
        let app = launch("standard")
        let picker = app.datePickers["datePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "the date picker never appeared")
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
        let app = launch("outOfOffice")
        XCTAssertTrue(element(app, "notice.0").waitForExistence(timeout: 30), "no notice shown")
        XCTAssertTrue(element(app, "nextWorkingDayButton").exists)
    }

    @MainActor
    func testRenderShowsThePreview() {
        let app = launch("standard")
        let render = app.buttons["renderButton"]
        XCTAssertTrue(render.waitForExistence(timeout: 10), "the Render button never appeared")
        XCTAssertTrue(element(app, "eventRow.0").waitForExistence(timeout: 10))
        render.tap()

        XCTAssertTrue(
            element(app, "pdfPreview").waitForExistence(timeout: 30), "the preview never appeared")
        let list = element(app, "agendaScreen")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(list.isHittable, "the list is hidden beside the preview on iPad")
        } else {
            XCTAssertFalse(list.isHittable, "the list is still in front of the preview on iPhone")
        }
    }

    // PROBE: temporary, prints how each way of tapping a row's switch behaves; never fails.
    @MainActor
    private func probe(
        _ name: String, _ fixture: String = "standard", extra: [String] = [],
        until goneID: String = "eventPageToggle.1", _ action: (XCUIApplication) -> Void
    ) {
        let app = XCUIApplication()
        app.launchArguments = ["-MagendaFixture", fixture] + extra
        app.launch()
        guard element(app, goneID).waitForExistence(timeout: 30) else {
            print("PROBE \(name): \(goneID) never appeared")
            return
        }
        action(app)
        let gone = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: element(app, goneID))
        let result = XCTWaiter().wait(for: [gone], timeout: 8)
        let include = app.switches["eventToggle.1"]
        let value = include.exists ? String(describing: include.value) : "-"
        print("PROBE \(name): \(result == .completed ? "WORKED" : "STUCK") include=\(value)")
    }

    @MainActor
    private func tapSwitch(_ app: XCUIApplication, at dx: CGFloat) {
        let toggle = element(app, "eventToggle.1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
    }

    @MainActor
    private func tapInner(_ app: XCUIApplication) {
        element(app, "eventToggle.1").switches.firstMatch.tap()
    }

    @MainActor
    func testProbeSwitchTaps() {
        let variants = [
            "label", "-ProbeHoverButton", "-ProbeHoverHighlight", "-ProbeHoverLift",
            "-ProbeHoverNone",
        ]
        for variant in variants {
            for attempt in 1...2 {
                let extra = variant.hasPrefix("-") ? [variant] : []
                probe("\(variant) inner \(attempt)", extra: extra) { app in self.tapInner(app) }
            }
        }
        probe("label centre", extra: []) { app in self.element(app, "eventToggle.1").tap() }
        probe("label right", extra: []) { app in self.tapSwitch(app, at: 0.9) }
    }
}
