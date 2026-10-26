// The binder-rules editor, driven through the accessibility tree against fixtures.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `RulesView.ID`,
// `SettingsView.ID` and `RowID`, never by their visible text, except for the swipe action and the
// navigation back button, which have none.

import XCTest

final class RulesUITests: XCTestCase {
    @MainActor
    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MagendaFixture", "standard"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func waitUntil(_ element: XCUIElement, _ format: String, _ argument: String) {
        let count = format.components(separatedBy: "%@").count - 1
        let predicate = NSPredicate(
            format: format, argumentArray: Array(repeating: argument, count: count))
        let result = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 30)
        XCTAssertEqual(result, .completed, "\(element) never satisfied \(format)")
    }

    /// Opens the settings sheet, then the rules, retrying dropped taps.
    @MainActor
    private func openRules(_ app: XCUIApplication) {
        XCTAssertTrue(
            element(app, "eventRow.0").waitForExistence(timeout: 30), "the list never appeared")
        let button = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30), "the settings button never appeared")
        let done = app.buttons["settingsDone"].firstMatch
        var taps = 0
        while !done.exists && taps < 5 {
            button.tap()
            taps += 1
            _ = done.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(done.exists, "the settings sheet never opened after \(taps) taps")

        let link = element(app, "rulesLink")
        reveal(app, link)
        let first = element(app, "rulesRow.personalBlocks.0")
        taps = 0
        while !first.exists && taps < 5 {
            link.tap()
            taps += 1
            _ = first.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(first.exists, "the rules never opened after \(taps) taps")
    }

    /// Goes back from the rules to the settings form and closes the sheet.
    @MainActor
    private func closeSettings(_ app: XCUIApplication) {
        let done = app.buttons["settingsDone"].firstMatch
        var taps = 0
        while !done.exists && taps < 5 {
            app.navigationBars["Binder rules"].buttons.firstMatch.tap()
            taps += 1
            _ = done.waitForExistence(timeout: 10)
        }
        taps = 0
        while done.exists && taps < 5 {
            done.tap()
            taps += 1
            _ = XCTWaiter().wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "exists == false"), object: done)
                ], timeout: 10)
        }
        XCTAssertFalse(done.exists, "the settings sheet never closed")
    }

    /// The bar the form scrolls under: the settings sheet's own, never the agenda's behind it.
    @MainActor
    private func formTop(_ app: XCUIApplication) -> XCUIElement {
        let done = app.buttons["settingsDone"].firstMatch
        return done.exists ? done : app.navigationBars["Binder rules"].firstMatch
    }

    /// Drags the form by `distance` points (positive scrolls further down). The drag starts below
    /// the sheet's top bar, so it lands in the form on a phone and in an iPad's form sheet alike,
    /// and it holds at the end so the form does not fling past a row.
    @MainActor
    private func drag(_ app: XCUIApplication, by distance: CGFloat) {
        let top = formTop(app)
        let center = top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let sideways: CGFloat = top.identifier == "settingsDone" ? -150 : 0
        let anchor = center.withOffset(CGVector(dx: sideways, dy: 275))
        let start = anchor.withOffset(CGVector(dx: 0, dy: distance / 2))
        let end = anchor.withOffset(CGVector(dx: 0, dy: -distance / 2))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 300, thenHoldForDuration: 0.3)
    }

    /// Scrolls in held drags until `target` can be tapped. A lazy row does not exist until it is
    /// scrolled near, so a missing target is looked for further down first and then back up. With
    /// `upperHalf`, the target should also sit in the top half of the screen, clear of the keyboard
    /// that tapping a text field brings up, unless the form cannot scroll any further.
    @MainActor
    private func reveal(_ app: XCUIApplication, _ target: XCUIElement, upperHalf: Bool = false) {
        let bottom = upperHalf ? app.windows.firstMatch.frame.height / 2 : .greatestFiniteMagnitude
        var drags = 0
        var lastMid: CGFloat?
        var stalled = 0
        while drags < 40 {
            guard target.waitForExistence(timeout: 1) else {
                lastMid = nil
                drag(app, by: drags < 12 ? 300 : -300)
                drags += 1
                continue
            }
            let top = formTop(app).frame.maxY + 40
            let mid = target.frame.midY
            stalled = lastMid.map { abs($0 - mid) < 2 ? stalled + 1 : 0 } ?? 0
            lastMid = mid
            if mid < top {
                drag(app, by: -min(max(top - mid + 40, 100), 300))
            } else if target.isHittable && (mid <= bottom || stalled >= 1) {
                break
            } else if stalled >= 3 {
                break
            } else {
                drag(app, by: min(max(mid - bottom + 40, 100), 300))
            }
            drags += 1
        }
        XCTAssertTrue(target.exists && target.isHittable, "\(target) was never scrolled into view")
    }

    /// Types `text` and presses return in a field. The keys go to whatever has focus rather than
    /// to the field, which an iPad's form sheet may briefly drop from the accessibility tree while
    /// it makes room for the keyboard.
    @MainActor
    private func enter(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        reveal(app, field, upperHalf: true)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        app.typeText(text)
    }

    @MainActor
    func testAddingAPersonalBlockLeavesMatchingEventsOffTheAgenda() {
        let app = launch()
        openRules(app)

        enter(app, element(app, "rulesAdd.personalBlocks"), "Week preparation\n")
        let added = element(app, "rulesRow.personalBlocks.2")
        XCTAssertTrue(added.waitForExistence(timeout: 30), "the new block never appeared")

        closeSettings(app)
        let reason = element(app, "eventReason.6")
        XCTAssertTrue(reason.waitForExistence(timeout: 30), "eventReason.6 never appeared")
        waitUntil(reason, "label CONTAINS %@", "Personal block")
    }

    @MainActor
    func testDeletingAPersonalBlockBringsItsEventsBack() {
        let app = launch()
        openRules(app)

        let row = element(app, "rulesRow.personalBlocks.0")
        var swipes = 0
        while row.exists && swipes < 5 {
            row.swipeLeft()
            swipes += 1
            let delete = app.buttons["Delete"].firstMatch
            if delete.waitForExistence(timeout: 5) {
                delete.tap()
            }
            _ = XCTWaiter().wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "label != %@", "Lunch"), object: row)
                ], timeout: 5)
            if row.exists && row.label != "Lunch" { break }
        }
        XCTAssertNotEqual(row.label, "Lunch", "Lunch was never deleted")

        closeSettings(app)
        let reason = element(app, "eventReason.3")
        XCTAssertTrue(reason.waitForExistence(timeout: 30), "eventReason.3 never appeared")
        waitUntil(reason, "NOT (label CONTAINS %@)", "Personal block")
    }

    @MainActor
    func testAddingAPersonShowsTheAlias() {
        let app = launch()
        openRules(app)

        enter(app, element(app, "peopleName"), "Nora\n")
        enter(app, element(app, "peopleEmail"), "nora@example.com\n")
        let add = app.buttons["peopleAdd"].firstMatch
        reveal(app, add)
        var taps = 0
        let row = element(app, "rulesRow.people.0")
        while !row.exists && taps < 5 {
            add.tap()
            taps += 1
            _ = row.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(row.exists, "the person never appeared after \(taps) taps")
    }

    @MainActor
    private func addSummary(_ app: XCUIApplication, title: String, tickFirst: Bool) {
        enter(app, element(app, "summaryTitleField"), title)
        if tickFirst {
            let choice = element(app, "summaryChoice.0")
            reveal(app, choice)
            choice.tap()
        }
        let add = app.buttons["summaryAdd"].firstMatch
        reveal(app, add)
        add.tap()
    }

    @MainActor
    func testAddingAMeetingSummaryShowsTheRowWithTheRoutineName() {
        let app = launch()
        openRules(app)

        addSummary(app, title: "Board meeting", tickFirst: true)
        let row = element(app, "rulesRow.summaries.0")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the summary never appeared")
        XCTAssertTrue(row.label.contains("Client memo"), "the row named no routine: \(row.label)")
    }

    @MainActor
    func testAddingASummaryWithoutAChoiceShowsAnError() {
        let app = launch()
        openRules(app)

        addSummary(app, title: "Board meeting", tickFirst: false)
        let error = element(app, "summaryError")
        XCTAssertTrue(error.waitForExistence(timeout: 30), "summaryError never appeared")
    }

    @MainActor
    func testWithoutSummaryRoutinesTheRulesSaySoInsteadOfCheckboxes() {
        let app = launch(["-MagendaNoSummaryRoutines"])
        openRules(app)

        let note = element(app, "summaryNoRoutines")
        reveal(app, note)
        XCTAssertTrue(note.exists)
    }

    @MainActor
    func testTheLookAheadStepperIncrements() {
        let app = launch()
        openRules(app)

        let stepper = element(app, "lookAheadStepper")
        reveal(app, stepper)
        // The stepper's plus half is at the trailing edge of its row.
        stepper.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        let expected = "Upcoming tasks: 6 days"
        waitUntil(stepper, "label == %@ OR value == %@", expected)
    }

    @MainActor
    func testResetRulesRestoresTheDefaults() {
        let app = launch()
        openRules(app)

        let first = element(app, "rulesRow.personalBlocks.0")
        var swipes = 0
        while first.exists && first.label == "Lunch" && swipes < 5 {
            first.swipeLeft()
            swipes += 1
            let delete = app.buttons["Delete"].firstMatch
            if delete.waitForExistence(timeout: 5) {
                delete.tap()
            }
            _ = XCTWaiter().wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "label != %@", "Lunch"), object: first)
                ], timeout: 5)
        }
        XCTAssertNotEqual(first.label, "Lunch", "Lunch was never deleted")

        let reset = app.buttons["resetRulesButton"].firstMatch
        reveal(app, reset)
        reset.tap()
        reveal(app, element(app, "rulesRow.personalBlocks.1"))
        XCTAssertTrue(element(app, "rulesRow.personalBlocks.1").exists)
        reveal(app, first)
        waitUntil(first, "label == %@", "Lunch")
    }
}
