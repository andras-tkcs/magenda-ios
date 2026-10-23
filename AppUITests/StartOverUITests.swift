// Start over on iPad: it asks first, and confirming deletes the day's handwriting and renders it
// fresh. Layer 2 of docs/testing-policy.md; elements are found by identifier.

import UIKit
import XCTest

final class StartOverUITests: XCTestCase {
    @MainActor
    private func launch(_ fixture: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MagendaFixture", fixture] + extra
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
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
        let button = element(app, identifier)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "\(identifier) never appeared")
        button.tap()
    }

    @MainActor
    func testStartOverIsOfferedOnlyOnceTheDayIsStarted() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard")
        XCTAssertTrue(
            app.buttons["renderButton"].firstMatch.waitForExistence(timeout: 30),
            "the Render button never appeared")
        XCTAssertTrue(
            element(app, "eventRow.0").waitForExistence(timeout: 30), "the list never appeared")
        XCTAssertFalse(element(app, "startOverButton").exists)

        render(app)
        XCTAssertTrue(
            element(app, "startOverButton").waitForExistence(timeout: 30),
            "Start Over never appeared once the day was started")
    }

    @MainActor
    func testStartOverAsksAndThenDeletesTheHandwriting() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard", extra: ["-MagendaFingerDrawing"])
        render(app)

        let page = element(app, "binderPage.0")
        XCTAssertTrue(page.waitForExistence(timeout: 30), "the first page never appeared")
        draw(on: page)
        XCTAssertEqual(waitForValue(page, "Handwritten"), "Handwritten", "the stroke was not saved")

        tapButton(app, "startOverButton")
        tapButton(app, "cancelStartOverButton")
        XCTAssertEqual(page.value as? String, "Handwritten", "cancelling still deleted the stroke")

        tapButton(app, "startOverButton")
        tapButton(app, "confirmStartOverButton")
        let fresh = element(app, "binderPage.0")
        XCTAssertTrue(fresh.waitForExistence(timeout: 30), "the fresh binder never appeared")
        XCTAssertEqual(waitForValue(fresh, "Blank"), "Blank", "starting over kept the stroke")
    }
}
