// The binder beside the list: the share button and the omitted-tasks banner.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `AgendaView.ID`,
// `BinderView.ID` and `OmittedTasksBanner.ID`, never by their visible text.

import XCTest

final class PreviewUITests: XCTestCase {
    private static let largestSize = "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"

    /// What a render shows.
    private static let previewID = "binderView"

    /// The share button of what a render shows.
    private static let shareID = "binderShareButton"

    /// Taps Render once the first row is there, and waits for the preview.
    @MainActor
    private func render(_ app: XCUIApplication) {
        let button = app.buttons["renderButton"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30), "the Render button never appeared")
        XCTAssertTrue(
            app.element("eventRow.0").waitForExistence(timeout: 30), "the list never appeared")
        button.tap()
        XCTAssertTrue(
            app.element(Self.previewID).waitForExistence(timeout: 30),
            "the preview never appeared")
    }

    @MainActor
    func testRenderShowsThePreviewWithAShareButtonAndNoBanner() {
        let app = XCUIApplication.launchMagenda()
        render(app)

        let share = app.buttons[Self.shareID].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 30), "the share button never appeared")
        XCTAssertTrue(share.isHittable, "the share button can't be tapped")
        XCTAssertFalse(app.element("omittedTasksBanner").exists)
    }

    @MainActor
    func testChangingTheDayBringsBackThePlaceholderOnIPad() {
        let app = XCUIApplication.launchMagenda()
        render(app)

        let placeholder = app.element("previewPlaceholder")
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
    func testOverflowShowsTheOmittedTasksBanner() {
        let app = XCUIApplication.launchMagenda(fixture: "overflow")
        render(app)

        let banner = app.element("omittedTasksBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 30), "the banner never appeared")
        let label = banner.label
        XCTAssertNotNil(
            label.range(of: #"^[0-9]+ tasks?"#, options: .regularExpression),
            "the banner label doesn't start with a count: \(label)")
    }

    @MainActor
    func testShareButtonCanBeTappedAtTheLargestTextSize() {
        let app = XCUIApplication.launchMagenda(
            fixture: "longText", ["-UIPreferredContentSizeCategoryName", Self.largestSize])
        render(app)

        let share = app.buttons[Self.shareID].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 30), "the share button never appeared")
        XCTAssertTrue(share.isHittable, "the share button can't be tapped")
    }
}
