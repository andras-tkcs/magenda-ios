// Finish Day in the binder and the Review list of finished days on iPad. Layer 2 of
// docs/testing-policy.md; elements are found by identifier, and the fixtures answer for Drive and
// the routine.

import XCTest

final class HandoffUITests: XCTestCase {
    /// Taps the button `identifier` once it exists.
    @MainActor
    private func tapButton(_ app: XCUIApplication, _ identifier: String) {
        let button = app.element(identifier)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "\(identifier) never appeared")
        button.tap()
    }

    /// Taps Render once the first row is there, and waits for the binder.
    @MainActor
    private func render(_ app: XCUIApplication) {
        let button = app.buttons["renderButton"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30), "the Render button never appeared")
        XCTAssertTrue(
            app.element("eventRow.0").waitForExistence(timeout: 30), "the list never appeared")
        button.tap()
        XCTAssertTrue(
            app.element("binderView").waitForExistence(timeout: 30), "the binder never appeared")
    }

    /// Renders, finishes the day, and waits until the hand-off notice shows.
    @MainActor
    private func finishDay(_ app: XCUIApplication) {
        render(app)
        tapButton(app, "finishDayButton")
        XCTAssertTrue(
            app.element("handoffMessage").waitForExistence(timeout: 30),
            "no hand-off notice appeared")
    }

    /// Opens Review and waits for the first row's status.
    @MainActor
    private func openReview(_ app: XCUIApplication) -> XCUIElement {
        tapButton(app, "reviewButton")
        let status = app.element("reviewStatus.0")
        XCTAssertTrue(status.waitForExistence(timeout: 30), "the first finished day never showed")
        return status
    }

    /// Waits up to 30 seconds for `element`'s label to begin with `prefix`.
    @MainActor
    private func waitForLabel(_ element: XCUIElement, beginningWith prefix: String) -> Bool {
        let matches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", prefix), object: element)
        return XCTWaiter().wait(for: [matches], timeout: 30) == .completed
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

    /// Opens the edit sheet for `row`. A synthesized tap in the split view's sidebar is sometimes
    /// dropped, so the row is tapped again while the sheet has not appeared.
    @MainActor
    private func openEditor(_ app: XCUIApplication, row identifier: String) {
        let list = app.element("agendaScreen")
        XCTAssertTrue(list.waitForExistence(timeout: 30), "the list never appeared")
        let row = app.buttons[identifier]
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
    }

    /// Swipes the binder to a page whose Send Meeting button is enabled, sends that meeting and
    /// waits for the hand-off notice. Cancelling the alert once first must leave the button as it
    /// was.
    @MainActor
    private func sendFirstMeeting(_ app: XCUIApplication) {
        let binder = app.element("binderView")
        let indicator = app.element("binderPageIndicator")
        let send = app.element("sendMeetingButton")
        XCTAssertTrue(indicator.waitForExistence(timeout: 30), "the page indicator never appeared")
        XCTAssertTrue(send.waitForExistence(timeout: 30), "the Send Meeting button never appeared")
        var seen: [String] = []
        var swipes = 0
        while !send.isEnabled && swipes < 6 {
            let before = indicator.label
            binder.swipeLeft(velocity: .fast)
            swipes += 1
            let moved = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label != %@", before), object: indicator)
            _ = XCTWaiter().wait(for: [moved], timeout: 10)
            for index in 0..<8 {
                let page = app.element("binderPage.\(index)")
                if page.exists { seen.append("\(index): \(page.label)") }
            }
        }
        XCTAssertTrue(
            send.isEnabled,
            "no page enabled Send Meeting after \(swipes) swipes; pages seen: \(seen)")
        XCTAssertTrue(send.isHittable, "the Send Meeting button is scrolled out of the toolbar")
        send.tap()
        tapButton(app, "cancelSendMeetingButton")
        XCTAssertTrue(send.isEnabled, "cancelling disabled Send Meeting")
        send.tap()
        tapButton(app, "confirmSendMeetingButton")
        XCTAssertTrue(
            app.element("handoffMessage").waitForExistence(timeout: 30),
            "no hand-off notice appeared")
    }

    /// Waits up to 30 seconds for `element` to become (not) enabled.
    @MainActor
    private func waitForEnabled(_ element: XCUIElement, _ enabled: Bool) -> Bool {
        element.waitUntil(\.isEnabled, is: enabled)
    }

    @MainActor
    func testFinishedDayIsReadyForReview() {
        let app = XCUIApplication.launchMagenda(["-MagendaFingerDrawing"])
        finishDay(app)

        let status = openReview(app)
        XCTAssertTrue(
            waitForLabel(status, beginningWith: "Notes ready for review"),
            "Notes never became ready for review")
        XCTAssertTrue(
            app.element("reviewOpenDoc.0").waitForExistence(timeout: 30),
            "Open Doc never appeared")
    }

    @MainActor
    func testApprovingTheNotesClosesTheDay() {
        let app = XCUIApplication.launchMagenda(["-MagendaFingerDrawing"])
        finishDay(app)

        let status = openReview(app)
        XCTAssertTrue(
            waitForLabel(status, beginningWith: "Notes ready for review"),
            "Notes never became ready for review")
        tapButton(app, "reviewAction.0")
        XCTAssertTrue(
            waitForLabel(status, beginningWith: "Closed. Handwriting is deleted on"),
            "the day never closed; the status is \"\(status.label)\"")
    }

    @MainActor
    func testSummariesAreRequestedAfterTheNotesAreApproved() {
        let app = XCUIApplication.launchMagenda(["-MagendaFingerDrawing"])
        openEditor(app, row: "eventRow.1")
        let toggle = app.element("editSummary.0")
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), "editSummary.0 never appeared")
        let target = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        var taps = 0
        while (target.value as? String) != "1" && taps < 5 {
            target.tapSwitch(attempt: taps)
            taps += 1
        }
        XCTAssertEqual(target.value as? String, "1", "the summary did not turn on")
        app.buttons["editDone"].firstMatch.tap()
        XCTAssertTrue(
            app.element("editField").waitForNonExistence(timeout: 30), "the sheet stayed open")

        finishDay(app)
        let status = openReview(app)
        XCTAssertTrue(
            waitForLabel(status, beginningWith: "Notes ready for review"),
            "Notes never became ready for review")
        tapButton(app, "reviewAction.0")
        XCTAssertTrue(
            waitForLabel(status, beginningWith: "Summaries ready for review"),
            "the summaries never became ready; the status is \"\(status.label)\"")
        tapButton(app, "reviewAction.0")
        XCTAssertTrue(
            waitForLabel(status, beginningWith: "Closed"),
            "the day never closed; the status is \"\(status.label)\"")
    }

    @MainActor
    func testWithoutARoutineTheDayWaitsToBeSent() {
        let app = XCUIApplication.launchMagenda(["-MagendaFingerDrawing", "-MagendaNoRoutine"])
        finishDay(app)

        let status = openReview(app)
        XCTAssertEqual(status.label, "Uploaded, not yet sent to Claude")
        XCTAssertTrue(
            app.element("reviewError.0").waitForExistence(timeout: 30),
            "the not-configured error never showed")
        let action = app.element("reviewAction.0")
        XCTAssertTrue(action.waitForExistence(timeout: 30), "Try again never appeared")
        XCTAssertTrue(action.label.hasPrefix("Try again"), "the button is \"\(action.label)\"")
    }

    @MainActor
    func testFinishDayIsDisabledOnceTheDayWasSent() {
        let app = XCUIApplication.launchMagenda(["-MagendaFingerDrawing"])
        finishDay(app)

        let finish = app.element("finishDayButton")
        XCTAssertTrue(
            finish.waitUntil(\.isEnabled, is: false),
            "Finish Day stayed enabled after the day was sent")
    }

    @MainActor
    func testResetHandoffAsksAndThenLetsTheDayBeFinishedAgain() {
        let app = XCUIApplication.launchMagenda(["-MagendaFingerDrawing"])
        render(app)
        XCTAssertFalse(app.element("resetHandoffButton").exists)
        tapButton(app, "finishDayButton")
        let finish = app.element("finishDayButton")
        XCTAssertTrue(finish.waitUntil(\.isEnabled, is: false))

        tapButton(app, "resetHandoffButton")
        tapButton(app, "cancelResetHandoffButton")
        XCTAssertFalse(finish.isEnabled, "cancelling the reset enabled Finish Day")

        tapButton(app, "resetHandoffButton")
        tapButton(app, "confirmResetHandoffButton")
        XCTAssertTrue(
            finish.waitUntil(\.isEnabled, is: true),
            "Finish Day stayed disabled after the hand-off was reset")
    }

    @MainActor
    func testSendingAMeetingLocksItAndGivesItItsOwnReviewRow() {
        let app = XCUIApplication.launchMagenda()
        render(app)
        sendFirstMeeting(app)

        XCTAssertTrue(
            app.element("sentBadge").waitForExistence(timeout: 30), "the sent badge never showed")
        let sentPages = app.descendants(matching: .any).matching(
            NSPredicate(format: "value == %@", "Sent to Claude"))
        XCTAssertGreaterThan(sentPages.count, 0, "no page reads Sent to Claude")
        XCTAssertTrue(
            waitForEnabled(app.element("sendMeetingButton"), false),
            "Send Meeting stayed enabled on the sent meeting")
        XCTAssertFalse(
            app.element("startOverButton").isEnabled, "Start Over stayed enabled")

        // A tap on the overview button must still move pages from a locked page.
        let indicator = app.element("binderPageIndicator")
        tapButton(app, "binderOverviewButton")
        let atOverview = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "Page 1 of"), object: indicator)
        XCTAssertEqual(
            XCTWaiter().wait(for: [atOverview], timeout: 10), .completed,
            "the page indicator says \(indicator.label) after Overview")

        // Back to a meeting page: the sent meeting stays in the day's PDF.
        app.element("binderView").swipeLeft(velocity: .fast)
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "NOT (label BEGINSWITH %@)", "Page 1 of"),
            object: indicator)
        XCTAssertEqual(
            XCTWaiter().wait(for: [moved], timeout: 10), .completed,
            "a swipe did not leave the overview: \(indicator.label)")

        let finish = app.element("finishDayButton")
        tapButton(app, "finishDayButton")
        XCTAssertTrue(waitForEnabled(finish, false), "Finish Day stayed enabled")

        let first = openReview(app)
        XCTAssertTrue(
            waitForLabel(first, beginningWith: "Notes ready for review"),
            "the first row never became ready for review")
        let second = app.element("reviewStatus.1")
        XCTAssertTrue(second.waitForExistence(timeout: 30), "the second row never showed")
        XCTAssertTrue(
            waitForLabel(second, beginningWith: "Notes ready for review"),
            "the second row never became ready for review")
        XCTAssertTrue(app.element("reviewRow.1").exists)
    }

    @MainActor
    func testResetHandoffUnlocksASentMeeting() {
        let app = XCUIApplication.launchMagenda()
        render(app)
        sendFirstMeeting(app)
        XCTAssertTrue(
            app.element("sentBadge").waitForExistence(timeout: 30), "the sent badge never showed")

        tapButton(app, "resetHandoffButton")
        tapButton(app, "confirmResetHandoffButton")
        let badge = app.element("sentBadge")
        XCTAssertTrue(badge.waitForNonExistence(timeout: 30), "the sent badge stayed")
        XCTAssertTrue(
            waitForEnabled(app.element("sendMeetingButton"), true),
            "Send Meeting stayed disabled after the reset")
    }
}
