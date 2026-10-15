// AppCore's personal and delegated task selection rules.

import Foundation
import Testing

@testable import AppCore

@Suite("Task selection")
struct TaskSelectionTests {
    private let zone = TimeZone(identifier: "Europe/Budapest") ?? .gmt
    private let rules = BinderRules.default
    private let day = TaskSelectionTests.calendarDay(2026, 9, 30)

    private static func calendarDay(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        guard let result = CalendarDay(year: year, month: month, day: day) else {
            fatalError("Invalid test date")
        }
        return result
    }

    private func task(
        _ title: String?, id: String = "t", notes: String? = nil, status: String = "needsAction",
        offset: Int? = 0, position: String? = nil
    ) -> GoogleTask {
        GoogleTask(
            id: id, title: title, notes: notes, status: status,
            due: offset.map { day.adding(days: $0) }, position: position)
    }

    private func event(
        _ title: String, names: [String] = [], emails: [String] = [], included: Bool = true,
        others: Bool = true
    ) -> DraftEvent {
        DraftEvent(
            id: "primary|" + title, originalTitle: title, title: title, defaultTitle: title,
            shortNameKey: "t:" + title, start: day.startDate(in: zone), timeText: "09:00",
            scheduleSlot: 2, exclusion: nil, hasOtherAttendees: others, attendeeEmails: emails,
            attendeeFirstNames: names, isIncluded: included, includesMeetingPage: others)
    }

    private func drafts(
        _ tasks: [GoogleTask], events: [DraftEvent] = [], rules custom: BinderRules? = nil
    ) -> [DraftTask] {
        TaskSelection.draftTasks(for: day, tasks: tasks, events: events, rules: custom ?? rules)
    }

    @Test("Tasks are overdue, due today or upcoming, and later ones are not listed")
    func buckets() {
        let tasks = [
            task("Late", id: "a", offset: -3),
            task("Now", id: "b", offset: 0),
            task("Soon", id: "c", offset: 1),
            task("Edge", id: "d", offset: 5),
            task("Beyond", id: "e", offset: 6),
        ]
        let result = drafts(tasks)
        #expect(result.map(\.id) == ["a", "b", "c", "d"])
        let expected: [TaskBucket] = [.overdue, .today, .upcoming, .upcoming]
        #expect(result.map(\.bucket) == expected)
        #expect(result.allSatisfy { $0.isIncluded })
        #expect(result.allSatisfy { $0.reason == nil })
    }

    @Test("Bucket labels")
    func labels() {
        #expect(TaskBucket.overdue.label == "Overdue")
        #expect(TaskBucket.today.label == "Due today")
        #expect(TaskBucket.upcoming.label == "Upcoming")
    }

    @Test("The look-ahead comes from the rules and is clamped to 0…14")
    func lookAhead() {
        let tasks = [task("Soon", id: "a", offset: 1), task("Later", id: "b", offset: 10)]
        var custom = BinderRules.default
        custom.lookAheadDays = 0
        #expect(drafts(tasks, rules: custom).isEmpty)
        custom.lookAheadDays = -4
        #expect(drafts(tasks, rules: custom).isEmpty)
        custom.lookAheadDays = 10
        #expect(drafts(tasks, rules: custom).map(\.id) == ["a", "b"])
        custom.lookAheadDays = 99
        let far = [task("Fortnight", id: "c", offset: 14), task("Too far", id: "d", offset: 15)]
        #expect(drafts(far, rules: custom).map(\.id) == ["c"])
    }

    @Test("Undated, completed and untitled tasks are not listed")
    func notListed() {
        let tasks = [
            task("Someday", id: "a", offset: nil),
            task("Done", id: "b", status: "completed"),
            task(nil, id: "c"),
            task(" \n ", id: "d"),
            task("Keep", id: "e"),
        ]
        #expect(drafts(tasks).map(\.id) == ["e"])
    }

    @Test("Inside the list, tasks sort by due, then position, then input order")
    func ordering() {
        let tasks = [
            task("Upcoming", id: "a", offset: 2),
            task("Today, no position", id: "b", offset: 0),
            task("Today, late position", id: "c", offset: 0, position: "00000000000000000020"),
            task("Overdue", id: "d", offset: -1),
            task("Today, early position", id: "e", offset: 0, position: "00000000000000000010"),
            task("Today, no position either", id: "f", offset: 0),
        ]
        #expect(drafts(tasks).map(\.id) == ["d", "e", "c", "b", "f", "a"])
    }

    @Test("Text, notes and due date are normalized and formatted")
    func fields() {
        let tasks = [
            task("  Send   the\nslides ", id: "a", notes: " Ask  Ben\tfirst \n", offset: -2),
            task("Call the bank", id: "b", notes: nil, offset: 0),
        ]
        let result = drafts(tasks)
        #expect(result[0].originalText == "Send the slides")
        #expect(result[0].text == "Send the slides")
        #expect(result[0].notes == "Ask Ben first")
        #expect(result[0].dueText == "09/28")
        #expect(result[1].notes == "")
        #expect(result[1].dueText == "09/30")
    }

    @Test("A discussion task is kept when the person is in an included meeting, by first name")
    func discussionKeptByName() {
        let tasks = [task("Zoltán - TBD", id: "a", offset: 2)]
        let meetings = [event("Budget review", names: ["zoltan"])]
        let result = drafts(tasks, events: meetings)
        #expect(result[0].isIncluded)
        #expect(result[0].reason == "Kept: Zoltán is in “Budget review” on this day")
    }

    @Test("A discussion task is kept by a person alias")
    func discussionKeptByAlias() {
        let tasks = [task("Zed - to be discussed", id: "a", offset: 1)]
        let meetings = [event("Planning", names: ["someone"], emails: ["zed@example.com"])]
        #expect(drafts(tasks, events: meetings).map(\.isIncluded) == [false])
        var custom = BinderRules.default
        custom.personAliases = ["zed": "zed@example.com"]
        let result = drafts(tasks, events: meetings, rules: custom)
        #expect(result[0].isIncluded)
        #expect(result[0].reason == "Kept: Zed is in “Planning” on this day")
    }

    @Test("A discussion task is left out, with the reason, when nobody relevant is in a meeting")
    func discussionLeftOut() {
        let tasks = [
            task("Nora - to be discussed", id: "a", offset: 1),
            task("TBD", id: "b", offset: 1),
            task("Peter – to be discussed", id: "c", offset: 2),
        ]
        let meetings = [
            event("With Peter, left out", names: ["peter"], included: false),
            event("With Peter, alone", names: ["peter"], others: false),
            event("With Sam", names: ["sam"]),
        ]
        let result = drafts(tasks, events: meetings)
        #expect(result.map(\.isIncluded) == [false, false, false])
        #expect(
            result.map(\.reason) == [
                "To be discussed: no meeting with Nora on this day",
                "To be discussed",
                "To be discussed: no meeting with Peter on this day",
            ])
    }

    @Test("Overdue and due-today discussion tasks are ordinary tasks")
    func discussionNotUpcoming() {
        let tasks = [
            task("Nora - to be discussed", id: "a", offset: -1),
            task("Nora - to be discussed", id: "b", offset: 0),
        ]
        let result = drafts(tasks)
        #expect(result.map(\.isIncluded) == [true, true])
        #expect(result.allSatisfy { $0.reason == nil })
    }

    @Test("Delegated tasks are marked when the check-in is due on the day or before")
    func delegatedMarked() {
        let tasks = [
            task("Anna: Hire a designer", id: "a", notes: "#weekly\none\ntwo\nthree", offset: 0),
            task("Ben: Renew the lease", id: "b", notes: "#monthly", offset: -5),
            task("Cleo: Later", id: "c", notes: "#daily", offset: 1),
            task("Dan: Undated", id: "d", notes: "#daily", offset: nil),
        ]
        let result = TaskSelection.draftDelegated(for: day, tasks: tasks)
        #expect(result.map(\.marked) == [true, true, false, false])
        #expect(result.map(\.owner) == ["Anna", "Ben", "Cleo", "Dan"])
        #expect(result.map(\.text) == ["Hire a designer", "Renew the lease", "Later", "Undated"])
        #expect(result.map(\.originalText) == result.map(\.text))
        let cadences: [Cadence] = [.weekly, .monthly, .daily, .daily]
        #expect(result.map(\.cadence) == cadences)
        #expect(result[0].status == ["two", "three"])
        #expect(result.allSatisfy { $0.isIncluded })
        #expect(result.allSatisfy { $0.warning == nil })
    }

    @Test("Delegated tasks that do not parse carry their warning, and completed ones are skipped")
    func delegatedWarnings() {
        let tasks = [
            task("Fix the printer", id: "a", offset: nil),
            task("Gone: Done", id: "b", status: "completed"),
            task(nil, id: "c"),
            task("  ", id: "d"),
        ]
        let result = TaskSelection.draftDelegated(for: day, tasks: tasks)
        #expect(result.map(\.id) == ["a"])
        #expect(result[0].owner == "")
        #expect(
            result[0].warning
                == "No “Owner: Task” title — shown without an owner. "
                + "No #daily, #weekly or #monthly on the first line — shown as Daily.")
    }
}
