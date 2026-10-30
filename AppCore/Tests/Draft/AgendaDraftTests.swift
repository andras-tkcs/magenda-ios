// AppCore's agenda draft: edits, toggles and the content it produces.

import Foundation
import Testing

@testable import AppCore

@Suite("Agenda draft")
struct AgendaDraftTests {
    private let zone = TimeZone(identifier: "Europe/Budapest") ?? .gmt
    private let day = AgendaDraftTests.calendarDay(2026, 9, 30)

    private static func calendarDay(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        guard let result = CalendarDay(year: year, month: month, day: day) else {
            fatalError("Invalid test date")
        }
        return result
    }

    private func event(
        _ id: String, _ title: String, slot: Int?, key: String? = nil, included: Bool = true,
        page: Bool = true, others: Bool = true, shortTitle: String? = nil
    ) -> DraftEvent {
        DraftEvent(
            id: "primary|" + id, originalTitle: title, title: shortTitle ?? title,
            defaultTitle: shortTitle ?? title, shortNameKey: key ?? "t:" + title,
            start: day.startDate(in: zone), timeText: "09:00", scheduleSlot: slot, exclusion: nil,
            hasOtherAttendees: others, attendeeEmails: [], attendeeFirstNames: [],
            isIncluded: included, includesMeetingPage: page)
    }

    private func task(_ id: String, _ text: String, included: Bool = true) -> DraftTask {
        DraftTask(
            id: id, originalText: text, text: text, notes: id == "t1" ? "Some notes" : "",
            dueText: "09/30", bucket: .today, reason: nil, isIncluded: included)
    }

    private func delegatedTask(_ id: String, _ text: String, marked: Bool = false)
        -> DraftDelegated
    {
        DraftDelegated(
            id: id, originalText: text, text: text, owner: "Anna", cadence: .weekly,
            marked: marked, status: ["One", "Two"], warning: nil, isIncluded: true)
    }

    private func draft(events: [DraftEvent] = [], tasks: [DraftTask] = []) -> AgendaDraft {
        AgendaDraft(
            date: day, notices: [], titlePrefixes: BinderRules.default.titlePrefixes,
            events: events, tasks: tasks,
            delegated: [delegatedTask("d1", "Hire", marked: true), delegatedTask("d2", "Lease")])
    }

    @Test("Turning an event off drops its meeting page, turning it on restores one")
    func includeEvent() {
        var value = draft(events: [
            event("a", "Sync", slot: 2), event("b", "Alone", slot: 4, page: false, others: false),
        ])
        value.setIncluded(false, forEvent: "primary|a")
        #expect(!value.events[0].isIncluded)
        #expect(!value.events[0].includesMeetingPage)
        value.setIncluded(true, forEvent: "primary|a")
        #expect(value.events[0].isIncluded)
        #expect(value.events[0].includesMeetingPage)
        value.setIncluded(true, forEvent: "primary|b")
        #expect(!value.events[1].includesMeetingPage)
        value.setIncluded(true, forEvent: "primary|unknown")
        #expect(value.events.count == 2)
    }

    @Test("A meeting page can be switched on and off, but not for a left-out event")
    func meetingPage() {
        var value = draft(events: [
            event("a", "Sync", slot: 2, page: false),
            event("b", "Out", slot: 4, included: false, page: false),
        ])
        value.setMeetingPage(true, forEvent: "primary|a")
        #expect(value.events[0].includesMeetingPage)
        value.setMeetingPage(false, forEvent: "primary|a")
        #expect(!value.events[0].includesMeetingPage)
        value.setMeetingPage(true, forEvent: "primary|b")
        #expect(!value.events[1].includesMeetingPage)
    }

    @Test("A blank title restores the default, any other is normalized")
    func titles() {
        var value = draft(events: [event("a", "REMINDER // Sync", slot: 2, shortTitle: "Sync")])
        value.setTitle("  A  better\ntitle ", forEvent: "primary|a")
        #expect(value.events[0].title == "A better title")
        value.setTitle(" \n ", forEvent: "primary|a")
        #expect(value.events[0].title == "Sync")
        value.setTitle("Elsewhere", forEvent: "primary|unknown")
        #expect(value.events[0].title == "Sync")
    }

    @Test("A short name applies to every event sharing its key")
    func shortName() {
        var value = draft(events: [
            event("a", "Budget review", slot: 2, key: "r:rec", shortTitle: "Budget"),
            event("b", "Budget review", slot: 4, key: "r:rec", shortTitle: "Budget"),
            event("c", "Other", slot: 6),
        ])
        value.setTitle("Edited", forEvent: "primary|b")
        value.applyShortName("  Review  ", key: "r:rec")
        #expect(value.events.map(\.title) == ["Review", "Review", "Other"])
        #expect(value.events.map(\.defaultTitle) == ["Review", "Review", "Other"])
        value.setTitle("", forEvent: "primary|a")
        #expect(value.events[0].title == "Review")
    }

    @Test("A blank short name goes back to the title without its prefixes")
    func removedShortName() {
        var value = draft(events: [
            event("a", "REMINDER // Budget review", slot: 2, key: "r:rec", shortTitle: "Short")
        ])
        value.applyShortName(" ", key: "r:rec")
        #expect(value.events[0].title == "Budget review")
        #expect(value.events[0].defaultTitle == "Budget review")
    }

    @Test("Task and delegated text edits fall back to the original when blank")
    func texts() {
        var value = draft(tasks: [task("t1", "Call the bank")])
        value.setText("  Call   the\nbank today ", forTask: "t1")
        value.setText("Hire a lead", forDelegated: "d1")
        #expect(value.tasks[0].text == "Call the bank today")
        #expect(value.delegated[0].text == "Hire a lead")
        value.setText("", forTask: "t1")
        value.setText(" ", forDelegated: "d1")
        value.setText("x", forTask: "unknown")
        value.setText("x", forDelegated: "unknown")
        #expect(value.tasks[0].text == "Call the bank")
        #expect(value.delegated[0].text == "Hire")
    }

    @Test("Tasks and delegated tasks can be switched off and on")
    func toggles() {
        var value = draft(tasks: [task("t1", "Call"), task("t2", "Book")])
        value.setIncluded(false, forTask: "t1")
        value.setIncluded(false, forDelegated: "d2")
        #expect(value.tasks.map(\.isIncluded) == [false, true])
        #expect(value.delegated.map(\.isIncluded) == [true, false])
        value.setIncluded(true, forTask: "t1")
        value.setIncluded(true, forDelegated: "d2")
        #expect(value.tasks.map(\.isIncluded) == [true, true])
        #expect(value.delegated.map(\.isIncluded) == [true, true])
    }

    @Test("The schedule keeps the calendar title and the meetings use the page title")
    func scheduleAndMeetings() {
        let value = draft(events: [
            event("a", "REMINDER // Sync", slot: 2, shortTitle: "Sync"),
            event("b", "Lunch", slot: 8, included: false, page: false),
            event("c", "Focus", slot: 12, page: false, others: false),
            event("d", "Review", slot: 14),
        ])
        let content = value.content()
        #expect(content.date == day)
        #expect(content.meetings == ["Sync", "Review"])
        #expect(content.meetingIDs == ["primary|a", "primary|d"])
        #expect(content.schedule.map(\.slot) == [2, 12, 14])
        #expect(content.schedule.map(\.text) == ["REMINDER // Sync", "Focus", "Review"])
        #expect(content.schedule.map(\.meetingIndex) == [0, nil, 1])
    }

    @Test("Two events in one slot are joined and link to no meeting page")
    func sharedSlot() {
        let value = draft(events: [
            event("a", "Sync", slot: 2), event("b", "Review", slot: 2),
            event("c", "Later", slot: 3),
        ])
        let content = value.content()
        #expect(content.schedule.map(\.text) == ["Sync / Review", "Later"])
        #expect(content.schedule.map(\.meetingIndex) == [nil, 2])
        #expect(content.meetings == ["Sync", "Review", "Later"])
    }

    @Test("An event outside the schedule still gets its meeting page")
    func unscheduled() {
        let value = draft(events: [event("a", "Dinner", slot: nil)])
        let content = value.content()
        #expect(content.schedule.isEmpty)
        #expect(content.meetings == ["Dinner"])
    }

    @Test("To-dos carry their notes, delegated tasks their mark, and left-out items are dropped")
    func todosAndDelegated() {
        var value = draft(tasks: [task("t1", "Call"), task("t2", "Book", included: false)])
        value.setIncluded(false, forDelegated: "d2")
        let content = value.content()
        #expect(
            content.todoItems == [
                TodoItem(text: "Call", notes: "Some notes", due: "09/30", taskID: "t1")
            ])
        #expect(
            content.delegated == [
                DelegatedItem(
                    text: "Hire", owner: "Anna", cadence: .weekly, marked: true,
                    status: ["One", "Two"], taskID: "d1")
            ])
    }

    @Test("Switching an event off removes it from the content")
    func leftOutEvent() {
        var value = draft(events: [event("a", "Sync", slot: 2)])
        value.setIncluded(false, forEvent: "primary|a")
        let content = value.content()
        #expect(content.schedule.isEmpty)
        #expect(content.meetings.isEmpty)
    }

    private let recap = SummaryRoutine(id: "id-recap", name: "Recap")
    private let board = SummaryRoutine(id: "id-board", name: "Board")

    @Test("Content carries task IDs and each meeting's summary routines in the list's order")
    func contentIDsAndRoutines() {
        var first = event("a", "Sync", slot: 2)
        first.summaryRoutineIDs = ["id-board", "id-gone", "id-recap"]
        let value = AgendaDraft(
            date: day, notices: [], titlePrefixes: [],
            events: [first, event("b", "Other", slot: 4)], tasks: [task("t1", "Call")],
            delegated: [delegatedTask("d1", "Hire", marked: true), delegatedTask("d2", "Lease")],
            summaryRoutines: [recap, board])
        let content = value.content()
        #expect(content.todoItems.map(\.taskID) == ["t1"])
        #expect(content.delegated.map(\.taskID) == ["d1", "d2"])
        #expect(content.meetingSummaryRoutines == [[recap, board], []])
        #expect(content.routinePages.isEmpty)
    }

    @Test("The content lists the routines that have a page of their own, in order")
    func contentRoutinePages() {
        var paged = board
        paged.hasPage = true
        let value = AgendaDraft(
            date: day, notices: [], titlePrefixes: [], events: [], tasks: [], delegated: [],
            summaryRoutines: [recap, paged])
        #expect(value.content().routinePages == [paged])
    }

    @Test("A short name that maps to routines gives the events with that key the routine IDs")
    func shortNameRoutines() {
        var value = AgendaDraft(
            date: day, notices: [], titlePrefixes: [],
            events: [event("a", "Team sync", slot: 2, key: "k"), event("b", "Other", slot: 4)],
            tasks: [], delegated: [], summaryRules: ["Sync": ["id-recap"]],
            summaryRoutines: [recap])
        value.applyShortName("sync", key: "k")
        #expect(value.events.map(\.summaryRoutineIDs) == [["id-recap"], []])
        value.applyShortName("", key: "k")
        #expect(value.events.map(\.summaryRoutineIDs) == [[], []])
    }

    @Test("A title that maps to routines gives the event the routine IDs, and a change recomputes")
    func titleRoutines() {
        var value = AgendaDraft(
            date: day, notices: [], titlePrefixes: [],
            events: [event("a", "Team sync", slot: 2)], tasks: [], delegated: [],
            summaryRules: ["Sync": ["id-recap", "id-board"]], summaryRoutines: [recap, board])
        value.setTitle("Sync", forEvent: "primary|a")
        #expect(value.events[0].summaryRoutineIDs == ["id-recap", "id-board"])
        value.setSummaryRoutineIDs(["id-board"], forEvent: "primary|a")
        #expect(value.events[0].summaryRoutineIDs == ["id-board"])
        value.setTitle("Elsewhere", forEvent: "primary|a")
        #expect(value.events[0].summaryRoutineIDs.isEmpty)
    }

    @Test("A title that only a pattern matches gives the event the pattern's routine IDs")
    func titlePatternRoutines() {
        var value = AgendaDraft(
            date: day, notices: [], titlePrefixes: [],
            events: [event("a", "Team sync", slot: 2)], tasks: [], delegated: [],
            summaryPatterns: ["sync [0-9]+": ["id-recap"]], summaryRoutines: [recap])
        value.setTitle("Sync 12", forEvent: "primary|a")
        #expect(value.events[0].summaryRoutineIDs == ["id-recap"])
        value.setTitle("Sync", forEvent: "primary|a")
        #expect(value.events[0].summaryRoutineIDs.isEmpty)
    }

    @Test("Setting the routine IDs overrides the title's rule and drops unknown IDs")
    func setRoutineIDs() {
        var value = AgendaDraft(
            date: day, notices: [], titlePrefixes: [],
            events: [event("a", "Sync", slot: 2), event("b", "Other", slot: 4)], tasks: [],
            delegated: [], summaryRules: ["Sync": ["id-recap"]], summaryRoutines: [recap, board])
        value.setSummaryRoutineIDs(["id-board", "id-gone"], forEvent: "primary|a")
        #expect(value.events.map(\.summaryRoutineIDs) == [["id-board"], []])
        value.setSummaryRoutineIDs([], forEvent: "primary|a")
        #expect(value.events[0].summaryRoutineIDs.isEmpty)
    }
}
