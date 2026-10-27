// Start over on iPad: it asks first, and confirming deletes the day's handwriting and renders it
// fresh. Layer 2 of docs/testing-policy.md; elements are found by identifier.

import XCTest

final class StartOverUITests: XCTestCase {
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

    /// Draws a vertical stroke down the middle of `page` with a finger.
    @MainActor
    private func draw(on page: XCUIElement) {
        let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let end = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    /// Waits up to 10 seconds for `element`'s value to become `value`; returns the final value.
    @MainActor
    private func waitForValue(_ element: XCUIElement, _ value: String) -> String? {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: element)
        _ = XCTWaiter().wait(for: [changed], timeout: 10)
        return element.value as? String
    }

    /// Taps the button `identifier` once it exists.
    @MainActor
    private func tapButton(_ app: XCUIApplication, _ identifier: String) {
        let button = app.element(identifier)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "\(identifier) never appeared")
        button.tap()
    }

    @MainActor
    func testStartOverIsOfferedOnlyOnceTheDayIsStarted() {
        let app = XCUIApplication.launchMagenda()
        XCTAssertTrue(
            app.buttons["renderButton"].firstMatch.waitForExistence(timeout: 30),
            "the Render button never appeared")
        XCTAssertTrue(
            app.element("eventRow.0").waitForExistence(timeout: 30), "the list never appeared")
        XCTAssertFalse(app.element("startOverButton").exists)

        render(app)
        XCTAssertTrue(
            app.element("startOverButton").waitForExistence(timeout: 30),
            "Start Over never appeared once the day was started")
    }

    @MainActor
    func testStartOverAsksAndThenDeletesTheHandwriting() {
        let app = XCUIApplication.launchMagenda(["-MagendaFingerDrawing"])
        render(app)

        let page = app.element("binderPage.0")
        XCTAssertTrue(page.waitForExistence(timeout: 30), "the first page never appeared")
        draw(on: page)
        XCTAssertEqual(waitForValue(page, "Handwritten"), "Handwritten", "the stroke was not saved")

        tapButton(app, "startOverButton")
        tapButton(app, "cancelStartOverButton")
        XCTAssertEqual(page.value as? String, "Handwritten", "cancelling still deleted the stroke")

        tapButton(app, "startOverButton")
        tapButton(app, "confirmStartOverButton")
        let fresh = app.element("binderPage.0")
        XCTAssertTrue(fresh.waitForExistence(timeout: 30), "the fresh binder never appeared")
        XCTAssertEqual(waitForValue(fresh, "Blank"), "Blank", "starting over kept the stroke")
    }
}
