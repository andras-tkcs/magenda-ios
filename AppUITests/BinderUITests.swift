// The binder on iPad: its pages, the page indicator, handwriting kept with its day and across a
// relaunch, and the omitted-tasks banner.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `AgendaView.ID` and
// `BinderView.ID`, never by their visible text; a page's value says whether it carries ink.

import UIKit
import XCTest

final class BinderUITests: XCTestCase {
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

    /// Draws a horizontal stroke across the middle of `page` with a finger.
    @MainActor
    private func draw(on page: XCUIElement) {
        let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
        let end = page.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6))
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

    @MainActor
    func testRenderShowsTheBinderWithAPageIndicator() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard")
        render(app)

        XCTAssertTrue(element(app, "binderView").exists)
        let indicator = element(app, "binderPageIndicator")
        XCTAssertTrue(indicator.waitForExistence(timeout: 30), "the page indicator never appeared")
        let label = indicator.label
        XCTAssertNotNil(
            label.range(of: #"^Page 1 of [0-9]+$"#, options: .regularExpression),
            "the page indicator says \(label)")
    }

    @MainActor
    func testHandwritingStaysWithTheDay() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard", extra: ["-MagendaFingerDrawing"])
        render(app)

        let page = element(app, "binderPage.0")
        XCTAssertTrue(page.waitForExistence(timeout: 30), "the first page never appeared")
        XCTAssertEqual(page.value as? String, "Blank")
        draw(on: page)
        XCTAssertEqual(waitForValue(page, "Handwritten"), "Handwritten", "the stroke was not saved")

        let placeholder = element(app, "previewPlaceholder")
        let next = app.buttons["nextDayButton"].firstMatch
        // The iPad simulator sometimes drops a tap in the sidebar column.
        var taps = 0
        while !placeholder.exists && taps < 5 {
            if next.waitForExistence(timeout: 30) {
                next.tap()
            }
            taps += 1
            _ = placeholder.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(placeholder.exists, "the next day still shows a binder after \(taps) taps")

        let binder = element(app, "binderView")
        let previous = app.buttons["previousDayButton"].firstMatch
        taps = 0
        while !binder.exists && taps < 5 {
            if previous.waitForExistence(timeout: 30) {
                previous.tap()
            }
            taps += 1
            _ = binder.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(binder.exists, "the binder never came back after \(taps) taps")
        XCTAssertTrue(page.waitForExistence(timeout: 30), "the first page never came back")
        XCTAssertEqual(page.value as? String, "Handwritten")
    }

    @MainActor
    func testOverflowShowsTheOmittedTasksBannerOverTheBinder() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("overflow")
        render(app)

        XCTAssertTrue(
            element(app, "omittedTasksBanner").waitForExistence(timeout: 30),
            "the banner never appeared")
    }

    @MainActor
    func testAFingerScrollsTheBinder() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("overflow")
        render(app)

        let binder = element(app, "binderView")
        let indicator = element(app, "binderPageIndicator")
        XCTAssertTrue(indicator.waitForExistence(timeout: 30), "the page indicator never appeared")
        var swipes = 0
        while indicator.label.hasPrefix("Page 1 of ") && swipes < 3 {
            binder.swipeUp()
            swipes += 1
        }
        XCTAssertFalse(
            indicator.label.hasPrefix("Page 1 of "),
            "a finger did not scroll the binder: the indicator still says \(indicator.label)")
    }

    @MainActor
    func testHandwritingSurvivesARelaunch() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let arguments = ["-MagendaFingerDrawing", "-MagendaBinderStoreFile", UUID().uuidString]
        let app = launch("standard", extra: arguments)
        render(app)

        let page = element(app, "binderPage.0")
        XCTAssertTrue(page.waitForExistence(timeout: 30), "the first page never appeared")
        draw(on: page)
        XCTAssertEqual(waitForValue(page, "Handwritten"), "Handwritten", "the stroke was not saved")
        app.terminate()

        let relaunched = launch("standard", extra: arguments)
        XCTAssertTrue(
            element(relaunched, "binderView").waitForExistence(timeout: 30),
            "the stored binder did not open on relaunch")
        let relaunchedPage = element(relaunched, "binderPage.0")
        XCTAssertTrue(
            relaunchedPage.waitForExistence(timeout: 30), "the first page never appeared")
        XCTAssertEqual(relaunchedPage.value as? String, "Handwritten")
    }
}
