// The binder-rules editor, driven through the accessibility tree against fixtures.
//
// Layer 2 of docs/testing-policy.md. Elements are found by the identifiers in `RulesView.ID`,
// `SettingsView.ID` and `RowID`, never by their visible text, except for the swipe action, the
// context-menu Delete and the navigation back button, which have none.

import XCTest

final class RulesUITests: XCTestCase {
    /// Launches straight into the rules and waits for the first block's row.
    @MainActor
    private func launchIntoRules(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.launchMagenda(["-MagendaOpen", "rules"] + extraArguments)
        XCTAssertTrue(
            app.element("rulesRow.personalBlocks.0").waitForExistence(timeout: 30),
            "the rules never opened")
        return app
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
            _ = done.waitForNonExistence(timeout: 10)
        }
        XCTAssertFalse(done.exists, "the settings sheet never closed")
    }

    /// The rules form, which the scroll helpers drag.
    @MainActor
    private func rulesForm(_ app: XCUIApplication) -> XCUIElement {
        app.element("rulesForm")
    }

    /// The bottom limit for a field about to be typed into: the top half of the screen, clear of
    /// the keyboard.
    @MainActor
    private func upperHalf(_ app: XCUIApplication) -> CGFloat {
        app.windows.firstMatch.frame.height / 2
    }

    /// Types `text` and presses return in a field. The keys go to whatever has focus rather than
    /// to the field, which an iPad's form sheet may briefly drop from the accessibility tree while
    /// it makes room for the keyboard.
    @MainActor
    private func enter(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        field.reveal(in: rulesForm(app), bottom: upperHalf(app))
        field.focusForTyping(in: app)
        app.typeText(text)
    }

    @MainActor
    func testAddingAPersonalBlockLeavesMatchingEventsOffTheAgenda() {
        let app = launchIntoRules()
        enter(app, app.element("rulesAdd.personalBlocks"), "Week preparation\n")
        let added = app.element("rulesRow.personalBlocks.2")
        XCTAssertTrue(added.waitForExistence(timeout: 30), "the new block never appeared")

        closeSettings(app)
        let reason = app.element("eventReason.6")
        XCTAssertTrue(reason.waitForExistence(timeout: 30), "eventReason.6 never appeared")
        waitUntil(reason, "label CONTAINS %@", "Personal block")
    }

    @MainActor
    func testDeletingAPersonalBlockBringsItsEventsBack() {
        let app = launchIntoRules()
        let row = app.element("rulesRow.personalBlocks.0")
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
        let reason = app.element("eventReason.3")
        XCTAssertTrue(reason.waitForExistence(timeout: 30), "eventReason.3 never appeared")
        waitUntil(reason, "NOT (label CONTAINS %@)", "Personal block")
    }

    /// Guards the long-press Delete on a rules row, which lets a default be removed without
    /// discovering the swipe. Each attempt presses, waits for the Delete button to be hittable and
    /// taps it, and repeats (at most 3 times) while the row is still there, because a tap that
    /// lands mid-animation is swallowed.
    @MainActor
    func testLongPressDeletesADefaultOutOfOfficeWord() {
        let app = launchIntoRules()
        let row = app.element("rulesRow.outOfOfficeWords.3")
        row.reveal(in: rulesForm(app))
        XCTAssertEqual(row.label, "PTO")
        let delete = app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "rulesDeleteAction", "Delete")
        ).firstMatch
        var attempts = 0
        while row.exists && attempts < 3 {
            row.press(forDuration: 1.2)
            attempts += 1
            guard delete.waitForExistence(timeout: 10) else { continue }
            // The menu animates in; a tap before it settles is swallowed on the oldest runtime.
            if delete.waitUntil(\.isHittable, is: true, timeout: 10) {
                delete.tap()
            }
            _ = row.waitForNonExistence(timeout: 10)
        }

        XCTAssertTrue(row.waitForNonExistence(timeout: 30), "PTO was never deleted")
        XCTAssertEqual(app.element("rulesRow.outOfOfficeWords.2").label, "Vacation")
    }

    /// Guards the Edit button on the rules screen, which shows the delete controls without a swipe.
    @MainActor
    func testEditTogglesTheRulesIntoEditing() {
        let app = launchIntoRules()
        let button = app.buttons["rulesEditButton"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30), "the Edit button never appeared")
        button.tap()
        XCTAssertTrue(button.waitUntil(\.label, is: "Done"), "\(button) never said Done")
        button.tap()
        XCTAssertTrue(button.waitUntil(\.label, is: "Edit"), "\(button) never said Edit")
    }

    @MainActor
    func testAddingAPersonShowsTheAlias() {
        let app = launchIntoRules()
        enter(app, app.element("peopleName"), "Nora\n")
        enter(app, app.element("peopleEmail"), "nora@example.com\n")
        let add = app.buttons["peopleAdd"].firstMatch
        add.reveal(in: rulesForm(app))
        var taps = 0
        let row = app.element("rulesRow.people.0")
        while !row.exists && taps < 5 {
            add.tap()
            taps += 1
            _ = row.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(row.exists, "the person never appeared after \(taps) taps")
    }

    @MainActor
    func testAddingSeveralNamesForOneEmailShowsOneRow() {
        let app = launchIntoRules()
        enter(app, app.element("peopleName"), "Bob, Robert\n")
        enter(app, app.element("peopleEmail"), "robert@example.com\n")
        let add = app.buttons["peopleAdd"].firstMatch
        add.reveal(in: rulesForm(app))
        var taps = 0
        let row = app.element("rulesRow.people.0")
        while !row.exists && taps < 5 {
            add.tap()
            taps += 1
            _ = row.waitForExistence(timeout: 10)
        }
        let text = "bob, robert → robert@example.com"
        XCTAssertTrue(row.waitUntil(\.label, is: text), "\(row) never said \(text)")
        XCTAssertFalse(app.element("rulesRow.people.1").exists, "the names got a row each")
    }

    @MainActor
    func testChoosingAContactFillsThePerson() {
        let app = launchIntoRules()
        let choose = app.buttons["peopleFromContacts"].firstMatch
        choose.reveal(in: rulesForm(app))
        choose.tap()
        waitUntil(app.element("peopleName"), "value == %@", "Nora")
        waitUntil(app.element("peopleEmail"), "value == %@", "nora.kim@example.com")

        let add = app.buttons["peopleAdd"].firstMatch
        add.reveal(in: rulesForm(app))
        var taps = 0
        let row = app.element("rulesRow.people.0")
        while !row.exists && taps < 5 {
            add.tap()
            taps += 1
            _ = row.waitForExistence(timeout: 10)
        }
        let alias = "nora → nora.kim@example.com"
        XCTAssertTrue(row.waitUntil(\.label, is: alias), "\(row) never said \(alias)")
    }

    @MainActor
    private func turnOn(_ app: XCUIApplication, _ identifier: String) {
        let element = app.element(identifier)
        element.reveal(in: rulesForm(app))
        let toggle = element.switches.firstMatch.exists ? element.switches.firstMatch : element
        var taps = 0
        while (toggle.value as? String) != "1" && taps < 5 {
            toggle.tapSwitch(attempt: taps)
            taps += 1
        }
        XCTAssertEqual(toggle.value as? String, "1", "\(identifier) did not turn on")
    }

    @MainActor
    private func addSummary(
        _ app: XCUIApplication, title: String, tickFirst: Bool, pattern: Bool = false
    ) {
        enter(app, app.element("summaryTitleField"), title)
        if tickFirst { turnOn(app, "summaryChoice.0") }
        if pattern { turnOn(app, "summaryPatternToggle") }
        let add = app.buttons["summaryAdd"].firstMatch
        add.reveal(in: rulesForm(app))
        add.tap()
    }

    @MainActor
    func testAddingAMeetingSummaryShowsTheRowWithTheRoutineName() {
        let app = launchIntoRules()
        addSummary(app, title: "Board meeting", tickFirst: true)
        let row = app.element("rulesRow.summaries.0")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the summary never appeared")
        XCTAssertTrue(row.label.contains("Client memo"), "the row named no routine: \(row.label)")
    }

    @MainActor
    func testAddingATitlePatternShowsItsRow() {
        let app = launchIntoRules()
        addSummary(app, title: "delivery sync [0-9]+", tickFirst: true, pattern: true)
        let row = app.element("rulesRow.summaryPatterns.0")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the pattern never appeared")
        XCTAssertTrue(row.label.contains("Client memo"), "the row named no routine: \(row.label)")
    }

    @MainActor
    func testAnInvalidPatternShowsAnError() {
        let app = launchIntoRules()
        addSummary(app, title: "delivery sync [0-9", tickFirst: true, pattern: true)
        let error = app.element("summaryError")
        XCTAssertTrue(error.waitForExistence(timeout: 30), "summaryError never appeared")
    }

    @MainActor
    func testADuplicateSummaryTitleShowsAnError() {
        let app = launchIntoRules()
        addSummary(app, title: "Board meeting", tickFirst: true)
        XCTAssertTrue(
            app.element("rulesRow.summaries.0").waitForExistence(timeout: 30),
            "the first summary never appeared")
        addSummary(app, title: "Board meeting", tickFirst: true)
        let error = app.element("summaryError")
        XCTAssertTrue(error.waitForExistence(timeout: 30), "summaryError never appeared")
    }

    @MainActor
    func testAddingASummaryWithoutAChoiceShowsAnError() {
        let app = launchIntoRules()
        addSummary(app, title: "Board meeting", tickFirst: false)
        let error = app.element("summaryError")
        XCTAssertTrue(error.waitForExistence(timeout: 30), "summaryError never appeared")
    }

    @MainActor
    func testWithoutSummaryRoutinesTheRulesSaySoInsteadOfCheckboxes() {
        let app = launchIntoRules(["-MagendaNoSummaryRoutines"])
        let note = app.element("summaryNoRoutines")
        note.reveal(in: rulesForm(app))
        XCTAssertTrue(note.exists)
    }

    @MainActor
    func testTheLookAheadStepperIncrements() {
        let app = launchIntoRules()
        let stepper = app.element("lookAheadStepper")
        stepper.reveal(in: rulesForm(app))
        // The stepper's plus half is at the trailing edge of its row.
        stepper.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        let expected = "Upcoming tasks: 6 days"
        waitUntil(stepper, "label == %@ OR value == %@", expected)
    }

    @MainActor
    func testResetRulesRestoresTheDefaults() {
        let app = launchIntoRules()
        let first = app.element("rulesRow.personalBlocks.0")
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
        reset.reveal(in: rulesForm(app))
        reset.tap()
        // The first rows are at the top, and the form is lazy, so they are gone from the tree down
        // here; `reveal` would look further down first. Scroll back up until they are there.
        let second = app.element("rulesRow.personalBlocks.1")
        var scrolls = 0
        while !second.exists && scrolls < 12 {
            rulesForm(app).scrollContent(by: -300)
            scrolls += 1
        }
        second.reveal(in: rulesForm(app))
        XCTAssertTrue(second.exists)
        first.reveal(in: rulesForm(app))
        XCTAssertTrue(first.waitUntil(\.label, is: "Lunch"), "\(first) never said Lunch")
    }
}
