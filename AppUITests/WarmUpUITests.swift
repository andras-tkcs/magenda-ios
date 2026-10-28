// Warms up XCTest's automation session on a just-booted simulator before a CI job's tests.
//
// tests.yml runs this class on its own, before the job's tests, and ignores its result: the
// first accessibility snapshot on a fresh simulator can time out, and that failure belongs to
// the runner, not to the app. It is never part of a shard and never the merge gate (ADR 0049).

import XCTest

final class WarmUpUITests: XCTestCase {
    @MainActor
    func testTheAppAnswers() {
        let app = XCUIApplication.launchMagenda()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 60), "Magenda's window never appeared")
    }
}
