// The binder on iPad: its pages, swiping between them and deleting added ones, the page
// indicator, the pen, eraser, undo and page buttons, handwriting kept with its day and across a
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
    func testAFingerSwipesToTheNextPage() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("overflow")
        render(app)

        let binder = element(app, "binderView")
        let indicator = element(app, "binderPageIndicator")
        XCTAssertTrue(indicator.waitForExistence(timeout: 30), "the page indicator never appeared")
        var swipes = 0
        while indicator.label.hasPrefix("Page 1 of ") && swipes < 3 {
            binder.swipeLeft(velocity: .fast)
            swipes += 1
        }
        // Where the pages are tells a swipe that did not move them from one that moved them
        // without the indicator following.
        var pages: [String] = []
        for index in 0..<3 {
            let page = element(app, "binderPage.\(index)")
            pages.append(page.exists ? "\(page.frame)" : "none")
        }
        XCTAssertFalse(
            indicator.label.hasPrefix("Page 1 of "),
            "a finger did not turn the page: the indicator still says \(indicator.label); "
                + "the binder is at \(binder.frame), its first pages at \(pages)")
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

    /// Taps the button `identifier` once it exists.
    @MainActor
    private func tapButton(_ app: XCUIApplication, _ identifier: String) {
        let button = element(app, identifier)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "\(identifier) never appeared")
        button.tap()
    }

    /// Waits up to 10 seconds for the page indicator's label to match `pattern`; returns the
    /// final label.
    @MainActor
    private func waitForIndicator(_ app: XCUIApplication, matching pattern: String) -> String {
        let indicator = element(app, "binderPageIndicator")
        let matches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", pattern), object: indicator)
        _ = XCTWaiter().wait(for: [matches], timeout: 10)
        return indicator.label
    }

    @MainActor
    func testNotesAndOverviewButtonsMoveBetweenPages() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard")
        render(app)

        tapButton(app, "binderNotesButton")
        let atNotes = waitForIndicator(app, matching: #"Page ([0-9]+) of \1"#)
        XCTAssertNotNil(
            atNotes.range(of: #"^Page ([0-9]+) of \1$"#, options: .regularExpression),
            "the page indicator says \(atNotes) after Notes")

        tapButton(app, "binderOverviewButton")
        let atOverview = waitForIndicator(app, matching: #"Page 1 of [0-9]+"#)
        XCTAssertNotNil(
            atOverview.range(of: #"^Page 1 of [0-9]+$"#, options: .regularExpression),
            "the page indicator says \(atOverview) after Overview")
    }

    /// Taps Add page and returns the page count once the new page is there.
    @MainActor
    private func addPage(_ app: XCUIApplication) -> Int {
        let indicator = element(app, "binderPageIndicator")
        XCTAssertTrue(indicator.waitForExistence(timeout: 30), "the page indicator never appeared")
        let before = indicator.label
        let count = before.split(separator: " ").last.flatMap { Int($0) }
        XCTAssertNotNil(count, "the page indicator says \(before)")

        // The iPad simulator sometimes drops a tap. A tap that was not dropped adds the page, so
        // tap again only while the page count has not grown.
        let total = (count ?? 0) + 1
        var after = before
        var taps = 0
        while after == before && taps < 3 {
            tapButton(app, "addPageButton")
            taps += 1
            after = waitForIndicator(app, matching: "Page [0-9]+ of \(total)")
            if after.hasPrefix("Page 1 of ") {
                after = waitForIndicator(app, matching: "Page 2 of \(total)")
            }
        }
        return total
    }

    @MainActor
    func testAddPageAddsAPageAfterTheCurrentOne() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard")
        render(app)

        let total = addPage(app)
        let after = waitForIndicator(app, matching: "Page 2 of \(total)")
        let expected = "Page 2 of \(total)"
        XCTAssertEqual(after, expected, "the page indicator says \(after)")
    }

    @MainActor
    func testAPageIsShownWhole() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard")
        render(app)

        let binder = element(app, "binderView")
        let page = element(app, "binderPage.0")
        XCTAssertTrue(page.waitForExistence(timeout: 30), "the first page never appeared")
        XCTAssertTrue(
            binder.frame.contains(page.frame),
            "the page \(page.frame) is not inside the binder \(binder.frame)")
        XCTAssertGreaterThanOrEqual(
            page.frame.minY, element(app, "binderOverviewButton").frame.maxY,
            "the page sits under the toolbar")
    }

    @MainActor
    func testDeletingAnAddedPageAsksFirst() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard")
        render(app)

        let total = addPage(app)
        let delete = element(app, "deletePageButton")
        XCTAssertTrue(delete.waitForExistence(timeout: 30), "the Delete button never appeared")
        XCTAssertTrue(delete.isEnabled, "Delete is disabled on an added page")

        delete.tap()
        tapButton(app, "cancelDeletePageButton")
        XCTAssertEqual(
            waitForIndicator(app, matching: "Page 2 of \(total)"), "Page 2 of \(total)",
            "cancelling deleted the page")

        delete.tap()
        tapButton(app, "confirmDeletePageButton")
        XCTAssertEqual(
            waitForIndicator(app, matching: "Page 1 of \(total - 1)"), "Page 1 of \(total - 1)",
            "confirming did not delete the page")
    }

    @MainActor
    func testDeletingIsDisabledOnAPrintedPage() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard")
        render(app)

        let delete = element(app, "deletePageButton")
        XCTAssertTrue(delete.waitForExistence(timeout: 30), "the Delete button never appeared")
        XCTAssertFalse(delete.isEnabled, "Delete is enabled on a printed page")
    }

    @MainActor
    func testUndoAndRedoAffectTheLastDrawing() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard", extra: ["-MagendaFingerDrawing"])
        render(app)

        let page = element(app, "binderPage.0")
        XCTAssertTrue(page.waitForExistence(timeout: 30), "the first page never appeared")
        draw(on: page)
        XCTAssertEqual(waitForValue(page, "Handwritten"), "Handwritten", "the stroke was not saved")

        tapButton(app, "undoButton")
        XCTAssertEqual(waitForValue(page, "Blank"), "Blank", "undo did not remove the stroke")

        tapButton(app, "redoButton")
        XCTAssertEqual(waitForValue(page, "Handwritten"), "Handwritten", "redo did not restore it")
    }

    @MainActor
    func testUndoRevertsAPageThatScrolledAway() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard", extra: ["-MagendaFingerDrawing"])
        render(app)

        let undo = element(app, "undoButton")
        XCTAssertTrue(undo.waitForExistence(timeout: 30), "the Undo button never appeared")
        XCTAssertFalse(undo.isEnabled, "undo is enabled before anything was drawn")

        let page = element(app, "binderPage.0")
        XCTAssertTrue(page.waitForExistence(timeout: 30), "the first page never appeared")
        draw(on: page)
        XCTAssertEqual(waitForValue(page, "Handwritten"), "Handwritten", "the stroke was not saved")

        tapButton(app, "binderNotesButton")
        let atNotes = waitForIndicator(app, matching: #"Page ([0-9]+) of \1"#)
        XCTAssertNotNil(
            atNotes.range(of: #"^Page ([0-9]+) of \1$"#, options: .regularExpression),
            "the notes button did not scroll to the last page: \(atNotes)")
        XCTAssertFalse(atNotes.hasPrefix("Page 1 of "), "the first page is still the visible one")

        tapButton(app, "undoButton")
        let back = waitForIndicator(app, matching: #"Page 1 of [0-9]+"#)
        XCTAssertNotNil(
            back.range(of: #"^Page 1 of [0-9]+$"#, options: .regularExpression),
            "undo did not scroll back to the first page: \(back)")
        let again = element(app, "binderPage.0")
        XCTAssertTrue(again.waitForExistence(timeout: 30), "the first page never came back")
        XCTAssertEqual(
            waitForValue(again, "Blank"), "Blank",
            "undo did not reach the page that scrolled away")
    }

    @MainActor
    func testPickingAPenSelectsIt() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch("standard")
        render(app)

        let black = element(app, "penButton.black")
        let red = element(app, "penButton.red")
        let eraser = element(app, "eraserButton")
        XCTAssertTrue(black.waitForExistence(timeout: 30), "the pens never appeared")
        XCTAssertTrue(black.isSelected, "black is not the pen to start with")

        red.tap()
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: red)
        _ = XCTWaiter().wait(for: [selected], timeout: 10)
        XCTAssertTrue(red.isSelected, "the red pen was not selected")
        XCTAssertFalse(black.isSelected, "the black pen is still selected")

        eraser.tap()
        let erasing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: eraser)
        _ = XCTWaiter().wait(for: [erasing], timeout: 10)
        XCTAssertTrue(eraser.isSelected, "the eraser was not selected")
    }
}
