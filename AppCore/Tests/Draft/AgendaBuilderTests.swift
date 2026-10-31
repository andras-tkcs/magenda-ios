// AppCore's agenda builder, checked against the standard Google fixture.

import Foundation
import Testing

@testable import AppCore

@Suite("Agenda builder")
struct AgendaBuilderTests {
    private let zone = TimeZone(identifier: "Europe/Budapest") ?? .gmt
    private let day = CalendarDay.today(in: .gmt, now: Date(timeIntervalSince1970: 1_790_726_400))

    private func build(_ fixture: GoogleFixture, on date: CalendarDay? = nil) async throws
        -> AgendaDraft
    {
        let source = FixtureGoogleDataSource(fixture)
        let when = date ?? day
        let events = try await source.events(calendarID: "primary", on: when, timeZone: zone)
        let todos = try await source.openTasks(listID: "todo")
        let delegated = try await source.openTasks(listID: "delegated")
        return AgendaBuilder(timeZone: zone, rules: .default).draft(
            for: when, events: events, tasks: todos, delegated: delegated)
    }

    @Test("The standard fixture's events")
    func standardEvents() async throws {
        let draft = try await build(.standard)
        #expect(draft.date == day)
        #expect(draft.notices.isEmpty)
        #expect(draft.titlePrefixes == BinderRules.default.titlePrefixes)
        #expect(
            draft.events.map(\.originalTitle) == [
                "Start the day", "Team sync", "1:1 with Peter", "Lunch",
                "REMINDER // Decision about the office move", "Server upgrade", "Week preparation",
                "Quarterly Summit", "Quarterly Summit", "Dinner with partners",
            ])
        let exclusions: [EventExclusion?] = [
            .personalBlock, nil, nil, .personalBlock, nil, .declined, nil, nil, .duplicate, nil,
        ]
        #expect(draft.events.map(\.exclusion) == exclusions)
        #expect(
            draft.events.map(\.includesMeetingPage) == [
                false, true, true, false, true, false, false, true, false, true,
            ])
        #expect(draft.events[4].title == "Decision about the office move")
        #expect(draft.events[4].reasons == ["Page title: Decision about the office move"])
        #expect(draft.events[6].reasons == ["No meeting page: no other attendees"])
        #expect(draft.events[9].scheduleSlot == nil)
        #expect(draft.events[9].reasons == ["Not on the schedule: outside 8:00–18:59"])
        #expect(draft.events[8].reasons == ["Duplicate of an earlier event"])
    }

    @Test("The standard fixture's personal tasks")
    func standardTasks() async throws {
        let draft = try await build(.standard)
        #expect(
            draft.tasks.map(\.text) == [
                "Send the slides", "Call the bank", "Nora - to be discussed",
                "Peter – to be discussed", "Book flights",
            ])
        let buckets: [TaskBucket] = [.overdue, .today, .upcoming, .upcoming, .upcoming]
        #expect(draft.tasks.map(\.bucket) == buckets)
        #expect(draft.tasks.map(\.isIncluded) == [true, true, false, true, true])
        #expect(draft.tasks.map(\.dueText) == ["09/28", "09/30", "10/01", "10/02", "10/03"])
        #expect(draft.tasks[0].notes == "Ask Ben for the Q3 numbers first")
        #expect(draft.tasks[2].reason == "To be discussed: no meeting with Nora on this day")
        #expect(draft.tasks[3].reason == "Kept: Peter is in “1:1 with Peter” on this day")
    }

    @Test("The standard fixture's delegated tasks")
    func standardDelegated() async throws {
        let draft = try await build(.standard)
        let texts = ["Hire a designer", "Renew the office lease", "Fix the printer"]
        #expect(draft.delegated.map(\.text) == texts)
        #expect(draft.delegated.map(\.owner) == ["Anna", "Ben", ""])
        let cadences: [Cadence] = [.weekly, .monthly, .daily]
        #expect(draft.delegated.map(\.cadence) == cadences)
        #expect(draft.delegated.map(\.marked) == [true, false, false])
        #expect(
            draft.delegated[0].status == [
                "2026-09-23 Interviews scheduled.", "2026-09-29 Two candidates left.",
            ])
        #expect(draft.delegated.map { $0.warning == nil } == [true, true, false])
    }

    @Test("The standard fixture's content")
    func standardContent() async throws {
        let content = try await build(.standard).content()
        #expect(
            content.meetings == [
                "Team sync", "1:1 with Peter", "Decision about the office move",
                "Quarterly Summit", "Dinner with partners",
            ])
        #expect(content.todoItems.count == 4)
        #expect(content.schedule.map(\.slot) == [2, 5, 10, 14, 16])
        #expect(
            content.schedule.map(\.text) == [
                "Team sync", "1:1 with Peter", "REMINDER // Decision about the office move",
                "Week preparation", "Quarterly Summit",
            ])
        #expect(content.schedule.map(\.meetingIndex) == [0, 1, 2, nil, 3])
        #expect(content.delegated.count == 3)
    }

    @Test("Notices come from the events, and an empty day gives an empty draft")
    func noticesAndEmpty() async throws {
        let away = try await build(.outOfOffice)
        #expect(away.notices == ["You're out of office on this day (“Vacation”)."])
        let empty = try await build(.empty)
        #expect(empty.events.isEmpty)
        #expect(empty.tasks.isEmpty)
        #expect(empty.delegated.isEmpty)
        #expect(empty.content().schedule.isEmpty)
    }

    @Test("The rules' summary routines and the available routines reach the draft")
    func summaryRoutines() {
        var rules = BinderRules.default
        rules.summaryRoutines = ["Sync": ["a"]]
        rules.summaryRoutinePatterns = ["sync [0-9]+": ["a"]]
        let routines = [SummaryRoutine(id: "a", name: "Recap")]
        let draft = AgendaBuilder(timeZone: zone, rules: rules, summaryRoutines: routines).draft(
            for: day, events: [], tasks: [], delegated: [])
        #expect(draft.summaryRules == ["Sync": ["a"]])
        #expect(draft.summaryPatterns == rules.summaryRoutinePatterns)
        #expect(draft.summaryRoutines == routines)
    }
}
