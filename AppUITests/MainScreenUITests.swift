// The real app, launched on a simulator and driven through its accessibility tree.
//
// Layer 2 of docs/testing-policy.md: the app starts, its first screen appears, and a value typed
// into it flows through AppCore and back onto the screen. Elements are found by the identifiers in
// `ContentView.ID`, never by their visible text, so copy changes do not break the suite.

import XCTest

final class MainScreenUITests: XCTestCase {
    @MainActor
    func testTypedNameIsGreeted() {
        let app = XCUIApplication()
        app.launch()

        let field = app.textFields["nameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field never appeared")
        field.tap()
        field.typeText("Ada")

        XCTAssertEqual(app.staticTexts["greeting"].label, "Hello, Ada!")
    }

    @MainActor
    func testVersionIsShown() {
        let app = XCUIApplication()
        app.launch()

        let version = app.descendants(matching: .any)["version"]
        XCTAssertTrue(version.waitForExistence(timeout: 10), "the version row never appeared")
    }
}
