// Long text in every row, at the default and the largest accessibility text size.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `AgendaView.ID` and
// `RowID`.

import XCTest

final class LongTextUITests: XCTestCase {
    private static let largestSize = "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"

    /// What a render shows.
    private static let previewID = "binderView"

    @MainActor
    func testRowsFitTheWindowAtTheDefaultSize() {
        checkRows(arguments: [])
    }

    @MainActor
    func testRowsFitTheWindowAtTheLargestTextSize() {
        checkRows(arguments: ["-UIPreferredContentSizeCategoryName", Self.largestSize])
    }

    @MainActor
    private func checkRows(arguments: [String]) {
        let app = XCUIApplication.launchMagenda(fixture: "longText", arguments)

        let list = app.element("agendaScreen")
        XCTAssertTrue(list.waitForExistence(timeout: 10), "the agenda never appeared")
        let window = app.windows.firstMatch

        let groups: [(row: String, toggle: String, count: Int)] = [
            ("eventRow", "eventToggle", 6),
            ("taskRow", "taskToggle", 6),
            ("delegatedRow", "delegatedToggle", 3),
        ]
        for group in groups {
            for n in 0..<group.count {
                let row = app.element("\(group.row).\(n)")
                let toggle = app.element("\(group.toggle).\(n)")
                scrollIntoView(row, in: list)
                XCTAssertTrue(row.exists, "\(group.row).\(n) was never found")
                XCTAssertGreaterThanOrEqual(
                    row.frame.minX, window.frame.minX, "\(group.row).\(n) starts outside")
                XCTAssertLessThanOrEqual(
                    row.frame.maxX, window.frame.maxX, "\(group.row).\(n) ends outside")
                XCTAssertTrue(toggle.isHittable, "\(group.toggle).\(n) can't be tapped")
            }
        }

        let render = app.buttons["renderButton"]
        XCTAssertTrue(render.isHittable, "the Render button can't be tapped")
        render.tap()
        XCTAssertTrue(
            app.element(Self.previewID).waitForExistence(timeout: 30),
            "the preview never appeared")
    }

    /// Drags the list up until `element` can be tapped, at most 40 times.
    @MainActor
    private func scrollIntoView(_ element: XCUIElement, in list: XCUIElement) {
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < 40 {
            start.press(forDuration: 0.05, thenDragTo: end)
            attempts += 1
        }
    }
}
