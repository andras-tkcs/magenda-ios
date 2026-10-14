// AppCore's Google data fixtures: launch-argument parsing, each fixture's contents and the
// fixture account.

import Foundation
import Testing

@testable import AppCore

private struct Counts: Equatable {
    let events: Int
    let todos: Int
    let delegated: Int
}

private let budapest = TimeZone(identifier: "Europe/Budapest") ?? .gmt
private let day = CalendarDay.today(in: .gmt, now: Date(timeIntervalSince1970: 1_790_726_400))
private let longStrings = AgendaContentFixtures.longStrings

private func events(_ fixture: GoogleFixture) async throws -> [GoogleEvent] {
    try await FixtureGoogleDataSource(fixture).events(
        calendarID: "primary", on: day, timeZone: budapest)
}

private func tasks(_ fixture: GoogleFixture, _ list: String) async throws -> [GoogleTask] {
    try await FixtureGoogleDataSource(fixture).openTasks(listID: list)
}

private func instant(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? .distantPast
}

private func startDate(_ event: GoogleEvent) -> Date {
    if case .timed(let date) = event.start {
        return date
    }
    return .distantPast
}

@Suite("Google fixtures")
struct GoogleFixturesTests {
    @Test("launch arguments name a fixture after -MagendaFixture")
    func parsing() {
        #expect(GoogleFixture(launchArguments: ["app", "-MagendaFixture", "standard"]) == .standard)
        #expect(GoogleFixture(launchArguments: ["-MagendaFixture", "overflow", "-x"]) == .overflow)
        #expect(GoogleFixture(launchArguments: ["app", "-MagendaFixture"]) == nil)
        #expect(GoogleFixture(launchArguments: ["app", "-MagendaFixture", "bogus"]) == nil)
        #expect(GoogleFixture(launchArguments: ["app", "standard"]) == nil)
        #expect(GoogleFixture.allCases.count == 5)
    }

    @Test("every fixture lists the same calendars and task lists")
    func listings() async throws {
        for fixture in GoogleFixture.allCases {
            let source = FixtureGoogleDataSource(fixture)
            let calendars = try await source.calendars()
            #expect(
                calendars == [
                    GoogleCalendar(id: "primary", title: "Work", isPrimary: true),
                    GoogleCalendar(id: "family", title: "Family", isPrimary: false),
                ])
            let lists = try await source.taskLists()
            #expect(
                lists == [
                    GoogleTaskList(id: "todo", title: "Claude"),
                    GoogleTaskList(id: "delegated", title: "Claude Delegations"),
                    GoogleTaskList(id: "other", title: "ToDos"),
                ])
        }
    }

    @Test("each fixture has the specified number of events, to-dos and delegated tasks")
    func counts() async throws {
        let expected: [GoogleFixture: Counts] = [
            .standard: Counts(events: 11, todos: 7, delegated: 3),
            .outOfOffice: Counts(events: 2, todos: 0, delegated: 0),
            .longText: Counts(events: 6, todos: 6, delegated: 3),
            .overflow: Counts(events: 22, todos: 30, delegated: 40),
            .empty: Counts(events: 0, todos: 0, delegated: 0),
        ]
        for fixture in GoogleFixture.allCases {
            let found = Counts(
                events: try await events(fixture).count,
                todos: try await tasks(fixture, "todo").count,
                delegated: try await tasks(fixture, "delegated").count)
            #expect(found == expected[fixture])
        }
    }

    @Test("the other list holds only the wrong-list task, and an unknown list is empty")
    func otherAndUnknownLists() async throws {
        for fixture in GoogleFixture.allCases {
            let other = try await tasks(fixture, "other")
            #expect(
                other == [
                    GoogleTask(
                        id: "t0", title: "Wrong list", notes: nil, status: "needsAction", due: day,
                        position: nil)
                ])
            let unknown = try await tasks(fixture, "nope")
            #expect(unknown.isEmpty)
        }
    }

    @Test("events exist only on the primary calendar")
    func familyCalendarIsEmpty() async throws {
        let family = try await FixtureGoogleDataSource(.standard).events(
            calendarID: "family", on: day, timeZone: budapest)
        #expect(family.isEmpty)
    }

    @Test("events are built on the requested day in the requested time zone")
    func timeZone() async throws {
        let standard = try await events(.standard)
        #expect(standard[2].title == "Team sync")
        #expect(startDate(standard[2]) == instant("2026-09-30T07:00:00Z"))
        let utc = try await FixtureGoogleDataSource(.standard).events(
            calendarID: "primary", on: day, timeZone: .gmt)
        #expect(startDate(utc[2]) == instant("2026-09-30T09:00:00Z"))
        #expect(standard[0].start == .allDay(day))
    }

    @Test("the standard events")
    func standardEvents() async throws {
        let found = try await events(.standard)
        #expect(found.map(\.id) == (0...10).map { "e" + String($0) })
        #expect(
            found.map(\.title) == [
                "Home", "Start the day", "Team sync", "1:1 with Peter", "Lunch",
                "REMINDER // Decision about the office move", "Server upgrade",
                "Week preparation", "Quarterly Summit", "Quarterly Summit",
                "Dinner with partners",
            ])
        #expect(found.allSatisfy { $0.status == "confirmed" && $0.calendarID == "primary" })
        #expect(found.allSatisfy { $0.iCalUID == nil && $0.eventType == nil })
        #expect(found[1].attendees.isEmpty)
        #expect(found[1].selfResponse == nil)
        #expect(found[2].selfResponse == "accepted")
        #expect(
            found[2].attendees.map(\.email) == [
                "me@example.com", "anna@example.com", "room-1@resource.calendar.google.com",
            ])
        #expect(found[2].attendees[2].isResource)
        #expect(found[3].attendees[1].email == "peter.brown@example.com")
        #expect(found[5].recurringEventID == "rec-office")
        #expect(found[2].recurringEventID == nil)
        #expect(found[6].selfResponse == "declined")
        #expect(found[6].attendees[0].responseStatus == "declined")
        #expect(found[7].attendees.count == 1)
        #expect(startDate(found[9]) == instant("2026-09-30T14:30:00Z"))
    }

    @Test("the standard tasks")
    func standardTasks() async throws {
        let todos = try await tasks(.standard, "todo")
        #expect(todos.map(\.id) == (0...6).map { "t" + String($0) })
        #expect(todos.allSatisfy { $0.status == "needsAction" && $0.position == nil })
        #expect(todos[0].notes == "Ask Ben for the Q3 numbers first")
        let offsets: [Int?] = [-2, 0, 1, 2, 3, 9, nil]
        let dues: [CalendarDay?] = offsets.map { offset in
            offset.map { day.adding(days: $0) }
        }
        #expect(todos.map(\.due) == dues)
        #expect(todos[3].title == "Peter – to be discussed")
        let delegated = try await tasks(.standard, "delegated")
        #expect(
            delegated.map(\.title) == [
                "Anna: Hire a designer", "Ben: Renew the office lease", "Fix the printer",
            ])
        #expect(
            delegated[0].notes
                == "#weekly\n2026-09-16 Delegated to Anna.\n2026-09-23 Interviews scheduled.\n"
                + "2026-09-29 Two candidates left.")
        let delegatedDues: [CalendarDay?] = [day, day.adding(days: 10), nil]
        #expect(delegated.map(\.due) == delegatedDues)
        #expect(delegated[2].notes == nil)
    }

    @Test("the out-of-office fixture")
    func outOfOffice() async throws {
        let found = try await events(.outOfOffice)
        #expect(found.map(\.title) == ["Vacation", "Team sync"])
        #expect(found[0].start == .allDay(day))
        #expect(startDate(found[1]) == instant("2026-09-30T08:00:00Z"))
        #expect(found[1].attendees.count == 2)
    }

    @Test("the long-text fixture uses the layout audit's strings")
    func longText() async throws {
        let found = try await events(.longText)
        #expect(found.map(\.title) == (0...5).map { Optional(longStrings[$0]) })
        let hours = [8, 9, 11, 13, 15, 17]
        let minutes = [0, 30, 0, 30, 0, 30]
        for index in 0...5 {
            let offset = TimeInterval(hours[index] * 3600 + minutes[index] * 60)
            let expected = day.startDate(in: budapest).addingTimeInterval(offset)
            #expect(startDate(found[index]) == expected)
            #expect(found[index].attendees.count == 2)
        }
        let todos = try await tasks(.longText, "todo")
        #expect(todos.map(\.title) == (0...5).map { Optional(longStrings[$0]) })
        #expect(todos.allSatisfy { $0.notes == longStrings[6] && $0.due == day })
        let delegated = try await tasks(.longText, "delegated")
        let notes = "#weekly\n" + longStrings[0] + "\n" + longStrings[2] + "\n" + longStrings[3]
        #expect(
            delegated.map(\.title) == [
                longStrings[1] + ": " + longStrings[0], longStrings[1] + ": " + longStrings[3],
                "Owner: " + longStrings[2],
            ])
        #expect(delegated.allSatisfy { $0.notes == notes && $0.due == day })
    }

    @Test("the overflow fixture")
    func overflow() async throws {
        let found = try await events(.overflow)
        #expect(found[0].title == "Meeting 0: " + longStrings[1])
        #expect(found[21].title == "Meeting 21: " + longStrings[1])
        #expect(Set(found.compactMap(\.title)).count == 22)
        #expect(startDate(found[0]) == instant("2026-09-30T06:00:00Z"))
        #expect(startDate(found[1]) == instant("2026-09-30T06:30:00Z"))
        #expect(startDate(found[21]) == instant("2026-09-30T16:30:00Z"))
        let todos = try await tasks(.overflow, "todo")
        #expect(todos.allSatisfy { $0.title == longStrings[0] && $0.notes == longStrings[6] })
        #expect(todos.allSatisfy { $0.due == day })
        let delegated = try await tasks(.overflow, "delegated")
        #expect(
            delegated[1].title
                == "Alexandra Montgomery-Smith: Delegated task 1 " + longStrings[0])
        let lines = String(repeating: "\n" + longStrings[0], count: 5)
        #expect(delegated[0].notes == "#daily" + lines)
        #expect(delegated[1].notes == "#weekly" + lines)
        #expect(delegated[2].notes == "#monthly" + lines)
        #expect(delegated[3].notes == "#daily" + lines)
        #expect(delegated[0].due == day)
        #expect(delegated[1].due == day.adding(days: 7))
        #expect(delegated[4].due == day)
    }

    @Test("the fixture account signs in without calling the closure, and signs out")
    func account() async throws {
        let account = FixtureGoogleAccount(signedIn: false)
        #expect(await account.isConfigured() == false)
        #expect(await account.isSignedIn() == false)
        do {
            try await account.signIn { _, _ in
                Issue.record("authenticate must not be called")
                throw GoogleAPIError.network
            }
            Issue.record("signIn must throw while unconfigured")
        } catch {
            #expect(error as? GoogleAPIError == .notConfigured)
        }
        let configuration = GoogleOAuthConfiguration(
            clientID: "123-abc.apps.googleusercontent.com")
        await account.configure(configuration)
        #expect(await account.isConfigured())
        #expect(await account.isSignedIn() == false)
        try await account.signIn { _, _ in
            Issue.record("authenticate must not be called")
            throw GoogleAPIError.network
        }
        #expect(await account.isSignedIn())
        await account.signOut()
        #expect(await account.isSignedIn() == false)
        await account.configure(nil)
        #expect(await account.isConfigured() == false)
        let signedIn = FixtureGoogleAccount(signedIn: true)
        #expect(await signedIn.isSignedIn() == false)
        await signedIn.configure(configuration)
        #expect(await signedIn.isSignedIn())
    }
}
