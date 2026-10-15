// The PDF preview beside the list: the share button and the omitted-tasks banner.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `AgendaView.ID` and
// `PreviewView.ID`, never by their visible text.

import UIKit
import XCTest

final class PreviewUITests: XCTestCase {
    private static let largestSize = "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"

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

    /// Taps Render once the first row is there, and waits for the preview.
    @MainActor
    private func render(_ app: XCUIApplication) {
        let button = app.buttons["renderButton"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30), "the Render button never appeared")
        XCTAssertTrue(
            element(app, "eventRow.0").waitForExistence(timeout: 30), "the list never appeared")
        button.tap()
        XCTAssertTrue(
            element(app, "pdfPreview").waitForExistence(timeout: 30), "the preview never appeared")
    }

    @MainActor
    func testRenderShowsThePreviewWithAShareButtonAndNoBanner() {
        let app = launch("standard")
        render(app)

        let share = app.buttons["shareButton"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 30), "the share button never appeared")
        XCTAssertTrue(share.isHittable, "the share button can't be tapped")
        XCTAssertFalse(element(app, "omittedTasksBanner").exists)
    }

    @MainActor
    func testChangingTheDayBringsBackThePlaceholderOnIPad() throws {
        // On iPhone the list is behind the pushed preview, so there is no day button to tap.
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard")
        render(app)

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
        XCTAssertTrue(placeholder.exists, "the placeholder never came back after \(taps) taps")
    }

    @MainActor
    func testRenderingAgainAfterGoingBackShowsThePreviewAgainOnIPhone() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone only")
        let app = launch("standard")
        render(app)

        // Back to the list: the Render button is on its navigation bar, not on the preview's.
        let renderButton = app.buttons["renderButton"].firstMatch
        let back = app.navigationBars.buttons.firstMatch
        var taps = 0
        while !renderButton.exists && taps < 5 {
            if back.waitForExistence(timeout: 30) {
                back.tap()
            }
            taps += 1
            _ = renderButton.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(renderButton.exists, "the list never came back after \(taps) taps")

        // Nothing changed, so the second render equals the first; the preview must still return.
        let preview = element(app, "pdfPreview")
        taps = 0
        while !preview.exists && taps < 5 {
            if renderButton.waitForExistence(timeout: 30) {
                renderButton.tap()
            }
            taps += 1
            _ = preview.waitForExistence(timeout: 30)
        }
        XCTAssertTrue(preview.exists, "the preview never came back after \(taps) taps")
    }

    @MainActor
    func testOverflowShowsTheOmittedTasksBanner() {
        let app = launch("overflow")
        render(app)

        let banner = element(app, "omittedTasksBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 30), "the banner never appeared")
        let label = banner.label
        XCTAssertNotNil(
            label.range(of: #"^[0-9]+ tasks?"#, options: .regularExpression),
            "the banner label doesn't start with a count: \(label)")
    }

    @MainActor
    func testShareButtonCanBeTappedAtTheLargestTextSize() {
        let app = launch(
            "longText", extra: ["-UIPreferredContentSizeCategoryName", Self.largestSize])
        render(app)

        let share = app.buttons["shareButton"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 30), "the share button never appeared")
        XCTAssertTrue(share.isHittable, "the share button can't be tapped")
    }
}
