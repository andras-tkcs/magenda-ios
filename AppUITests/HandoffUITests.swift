// Finish Day in the binder and the Review list of finished days on iPad. Layer 2 of
// docs/testing-policy.md; elements are found by identifier, and the fixtures answer for Drive and
// the routine.

import UIKit
import XCTest

final class HandoffUITests: XCTestCase {
    @MainActor
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MagendaFixture", "standard", "-MagendaFingerDrawing"] + extra
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
}
