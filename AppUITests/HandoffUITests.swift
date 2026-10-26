// Finish Day in the binder and the Review list of finished days on iPad. Layer 2 of
// docs/testing-policy.md; elements are found by identifier, and the fixtures answer for Drive and
// the routine.

import UIKit
import XCTest

final class HandoffUITests: XCTestCase {
    @MainActor
    private func launch(fingerDrawing: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // With finger drawing on, a swipe on the binder is a stroke and does not turn the page.
        var arguments = ["-MagendaFixture", "standard"]
        if fingerDrawing {
            arguments.append("-MagendaFingerDrawing")
        }
        app.launchArguments = arguments + extra
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Taps the button `identifier` once it exists.
    @MainActor
    private func tapButton(_ app: XCUIApplication, _ identifier: String) {
        let button = element(app, identifier)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "\(identifier) never appeared")
        button.tap()
    }

    /// Taps Render once the first row is there, and waits for the binder.
    @MainActor
    private func render(_ app: XCUIApplication) {
        let button = app.buttons["renderButton"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30), "the Render button never appeared")
        XCTAssertTrue(
            element(app, "eventRow.0").waitForExistence(timeout: 30), "the list never appeared")
        button.tap()
        XCTAssertTrue(
            element(app, "binderView").waitForExistence(timeout: 30), "the binder never appeared")
    }

    /// Renders, finishes the day, and waits until the hand-off notice shows.
    @MainActor
    private func finishDay(_ app: XCUIApplication) {
        render(app)
        tapButton(app, "finishDayButton")
        XCTAssertTrue(
            element(app, "handoffMessage").waitForExistence(timeout: 30),
            "no hand-off notice appeared")
    }

    /// Opens Review and waits for the first row's status.
    @MainActor
    private func openReview(_ app: XCUIApplication) -> XCUIElement {
        tapButton(app, "reviewButton")
        let status = element(app, "reviewStatus.0")
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

    /// Swipes the binder to a page whose Send Meeting button is enabled, sends that meeting and
    /// waits for the hand-off notice. Cancelling the alert once first must leave the button as it
    /// was.
    @MainActor
    private func sendFirstMeeting(_ app: XCUIApplication) {
        let binder = element(app, "binderView")
        let indicator = element(app, "binderPageIndicator")
        let send = element(app, "sendMeetingButton")
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
                let page = element(app, "binderPage.\(index)")
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
            element(app, "handoffMessage").waitForExistence(timeout: 30),
            "no hand-off notice appeared")
    }

    /// Waits up to 30 seconds for `element` to become (not) enabled.
    @MainActor
    private func waitForEnabled(_ element: XCUIElement, _ enabled: Bool) -> Bool {
        let matches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == %@", NSNumber(value: enabled)),
            object: element)
        return XCTWaiter().wait(for: [matches], timeout: 30) == .completed
    }

    @MainActor
    func testFinishedDayIsReadyForReview() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch()
        finishDay(app)

        let status = openReview(app)
        XCTAssertTrue(
            waitForLabel(status, beginningWith: "Notes ready for review"),
            "Notes never became ready for review")
        XCTAssertTrue(
            element(app, "reviewOpenDoc.0").waitForExistence(timeout: 30),
            "Open Doc never appeared")
    }

    @MainActor
    func testApprovingTheNotesClosesTheDay() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch()
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
    func testWithoutARoutineTheDayWaitsToBeSent() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch(extra: ["-MagendaNoRoutine"])
        finishDay(app)

        let status = openReview(app)
        XCTAssertEqual(status.label, "Uploaded, not yet sent to Claude")
        XCTAssertTrue(
            element(app, "reviewError.0").waitForExistence(timeout: 30),
            "the not-configured error never showed")
        let action = element(app, "reviewAction.0")
        XCTAssertTrue(action.waitForExistence(timeout: 30), "Try again never appeared")
        XCTAssertTrue(action.label.hasPrefix("Try again"), "the button is \"\(action.label)\"")
    }

    @MainActor
    func testFinishDayIsDisabledOnceTheDayWasSent() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch()
        finishDay(app)

        let finish = element(app, "finishDayButton")
        let disabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == false"), object: finish)
        XCTAssertEqual(
            XCTWaiter().wait(for: [disabled], timeout: 30), .completed,
            "Finish Day stayed enabled after the day was sent")
    }

    @MainActor
    func testResetHandoffAsksAndThenLetsTheDayBeFinishedAgain() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch()
        render(app)
        XCTAssertFalse(element(app, "resetHandoffButton").exists)
        tapButton(app, "finishDayButton")
        let finish = element(app, "finishDayButton")
        let disabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == false"), object: finish)
        XCTAssertEqual(XCTWaiter().wait(for: [disabled], timeout: 30), .completed)

        tapButton(app, "resetHandoffButton")
        tapButton(app, "cancelResetHandoffButton")
        XCTAssertFalse(finish.isEnabled, "cancelling the reset enabled Finish Day")

        tapButton(app, "resetHandoffButton")
        tapButton(app, "confirmResetHandoffButton")
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"), object: finish)
        XCTAssertEqual(
            XCTWaiter().wait(for: [enabled], timeout: 30), .completed,
            "Finish Day stayed disabled after the hand-off was reset")
    }

    @MainActor
    func testSendingAMeetingLocksItAndGivesItItsOwnReviewRow() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch(fingerDrawing: false)
        render(app)
        sendFirstMeeting(app)

        XCTAssertTrue(
            element(app, "sentBadge").waitForExistence(timeout: 30), "the sent badge never showed")
        let sentPages = app.descendants(matching: .any).matching(
            NSPredicate(format: "value == %@", "Sent to Claude"))
        XCTAssertGreaterThan(sentPages.count, 0, "no page reads Sent to Claude")
        XCTAssertTrue(
            waitForEnabled(element(app, "sendMeetingButton"), false),
            "Send Meeting stayed enabled on the sent meeting")
        XCTAssertFalse(
            element(app, "startOverButton").isEnabled, "Start Over stayed enabled")

        // A tap on the overview button must still move pages from a locked page.
        let indicator = element(app, "binderPageIndicator")
        tapButton(app, "binderOverviewButton")
        let atOverview = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "Page 1 of"), object: indicator)
        XCTAssertEqual(
            XCTWaiter().wait(for: [atOverview], timeout: 10), .completed,
            "the page indicator says \(indicator.label) after Overview")

        // Back to a meeting page: the sent meeting stays in the day's PDF.
        element(app, "binderView").swipeLeft(velocity: .fast)
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "NOT (label BEGINSWITH %@)", "Page 1 of"),
            object: indicator)
        XCTAssertEqual(
            XCTWaiter().wait(for: [moved], timeout: 10), .completed,
            "a swipe did not leave the overview: \(indicator.label)")

        let finish = element(app, "finishDayButton")
        tapButton(app, "finishDayButton")
        XCTAssertTrue(waitForEnabled(finish, false), "Finish Day stayed enabled")

        let first = openReview(app)
        XCTAssertTrue(
            waitForLabel(first, beginningWith: "Notes ready for review"),
            "the first row never became ready for review")
        let second = element(app, "reviewStatus.1")
        XCTAssertTrue(second.waitForExistence(timeout: 30), "the second row never showed")
        XCTAssertTrue(
            waitForLabel(second, beginningWith: "Notes ready for review"),
            "the second row never became ready for review")
        XCTAssertTrue(element(app, "reviewRow.1").exists)
    }

    @MainActor
    func testResetHandoffUnlocksASentMeeting() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch(fingerDrawing: false)
        render(app)
        sendFirstMeeting(app)
        XCTAssertTrue(
            element(app, "sentBadge").waitForExistence(timeout: 30), "the sent badge never showed")

        tapButton(app, "resetHandoffButton")
        tapButton(app, "confirmResetHandoffButton")
        let badge = element(app, "sentBadge")
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: badge)
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 30), .completed, "the sent badge stayed")
        XCTAssertTrue(
            waitForEnabled(element(app, "sendMeetingButton"), true),
            "Send Meeting stayed disabled after the reset")
    }
}
