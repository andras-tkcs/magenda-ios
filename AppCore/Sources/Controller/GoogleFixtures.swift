import Foundation

/// A fixed set of Google data for UI tests and SwiftUI previews.
public enum GoogleFixture: String, CaseIterable, Sendable {
    /// A typical day with every kind of event and task.
    case standard
    /// A day on which the person is out of office.
    case outOfOffice
    /// Titles and notes that are far too long, in several scripts.
    case longText
    /// More events, to-dos and delegated tasks than the pages can hold.
    case overflow
    /// Calendars and task lists with nothing in them.
    case empty

    /// The fixture named by the value after `-MagendaFixture`, or `nil` when the flag, its value
    /// or a fixture of that name is missing.
    public init?(launchArguments: [String]) {
        guard
            let value = launchArguments.drop(while: { $0 != "-MagendaFixture" }).dropFirst().first,
            let fixture = GoogleFixture(rawValue: value)
        else {
            return nil
        }
        self = fixture
    }
}

/// A `GoogleDataSource` that serves a `GoogleFixture` instead of calling Google.
public struct FixtureGoogleDataSource: GoogleDataSource {
    private let fixture: GoogleFixture

    // The day the fixtures' tasks are due around: 2026-09-30.
    private static let day = CalendarDay.today(
        in: .gmt, now: Date(timeIntervalSince1970: 1_790_726_400))

    /// Creates a data source serving `fixture`.
    public init(_ fixture: GoogleFixture) {
        self.fixture = fixture
    }

    /// The work and family calendars.
    public func calendars() async throws -> [GoogleCalendar] {
        [
            GoogleCalendar(id: "primary", title: "Work", isPrimary: true),
            GoogleCalendar(id: "family", title: "Family", isPrimary: false),
        ]
    }

    /// The fixture's events, on the primary calendar only, built on `day` in `timeZone`.
    public func events(calendarID: String, on day: CalendarDay, timeZone: TimeZone) async throws
        -> [GoogleEvent]
    {
        guard calendarID == "primary" else {
            return []
        }
        let longStrings = AgendaContentFixtures.longStrings
        let specs: [EventSpec]
        switch fixture {
        case .standard:
            specs = Self.standardEvents
        case .outOfOffice:
            specs = [
                EventSpec(title: "Vacation", time: nil, people: []),
                EventSpec(
                    title: "Team sync", time: Time(10, 0), people: [Self.me, Self.person("anna")]),
            ]
        case .longText:
            let times = [
                Time(8, 0), Time(9, 30), Time(11, 0), Time(13, 30), Time(15, 0), Time(17, 30),
            ]
            specs = (0...5).map { index in
                EventSpec(
                    title: longStrings[index], time: times[index],
                    people: [Self.me, Self.person("anna")])
            }
        case .overflow:
            specs = (0..<22).map { index in
                EventSpec(
                    title: "Meeting " + String(index) + ": " + longStrings[1],
                    time: Time(8 + index / 2, (index % 2) * 30),
                    people: [Self.me, Self.person("anna")])
            }
        case .empty:
            specs = []
        }
        return specs.enumerated().map { index, spec in
            Self.event(index, spec, day: day, timeZone: timeZone)
        }
    }

    /// The work, delegations and "other" lists.
    public func taskLists() async throws -> [GoogleTaskList] {
        [
            GoogleTaskList(id: "todo", title: "Claude"),
            GoogleTaskList(id: "delegated", title: "Claude Delegations"),
            GoogleTaskList(id: "other", title: "ToDos"),
        ]
    }

    /// The open tasks of `listID`; an unknown list has none.
    public func openTasks(listID: String) async throws -> [GoogleTask] {
        switch listID {
        case "todo":
            return Self.tasks(todos)
        case "delegated":
            return Self.tasks(delegated)
        case "other":
            return Self.tasks([TaskSpec(title: "Wrong list", notes: nil, due: Self.day)])
        default:
            return []
        }
    }

    // MARK: - Events

    private struct Time {
        let hour: Int
        let minute: Int

        init(_ hour: Int, _ minute: Int) {
            self.hour = hour
            self.minute = minute
        }
    }

    private struct EventSpec {
        let title: String
        /// `nil` for an all-day event.
        let time: Time?
        let people: [GoogleAttendee]
        var recurringEventID: String?
    }

    private static let me = GoogleAttendee(
        email: "me@example.com", displayName: "Me", isSelf: true, isResource: false,
        responseStatus: "accepted")

    private static let declinedMe = GoogleAttendee(
        email: "me@example.com", displayName: "Me", isSelf: true, isResource: false,
        responseStatus: "declined")

    private static let room = GoogleAttendee(
        email: "room-1@resource.calendar.google.com", displayName: nil, isSelf: false,
        isResource: true, responseStatus: "accepted")

    private static func person(_ name: String) -> GoogleAttendee {
        GoogleAttendee(
            email: name + "@example.com", displayName: nil, isSelf: false, isResource: false,
            responseStatus: "accepted")
    }

    private static let standardEvents: [EventSpec] = [
        EventSpec(title: "Home", time: nil, people: []),
        EventSpec(title: "Start the day", time: Time(8, 0), people: []),
        EventSpec(title: "Team sync", time: Time(9, 0), people: [me, person("anna"), room]),
        EventSpec(
            title: "1:1 with Peter", time: Time(10, 30), people: [me, person("peter.brown")]),
        EventSpec(title: "Lunch", time: Time(12, 0), people: []),
        EventSpec(
            title: "REMINDER // Decision about the office move", time: Time(13, 0),
            people: [me, person("ben")], recurringEventID: "rec-office"),
        EventSpec(
            title: "Server upgrade", time: Time(14, 0), people: [declinedMe, person("ops")]),
        EventSpec(title: "Week preparation", time: Time(15, 0), people: [me]),
        EventSpec(title: "Quarterly Summit", time: Time(16, 0), people: [me, person("anna")]),
        EventSpec(title: "Quarterly Summit", time: Time(16, 30), people: [me, person("anna")]),
        EventSpec(
            title: "Dinner with partners", time: Time(19, 0), people: [me, person("partner")]),
    ]

    private static func event(
        _ index: Int, _ spec: EventSpec, day: CalendarDay, timeZone: TimeZone
    ) -> GoogleEvent {
        var start = EventStart.allDay(day)
        if let time = spec.time {
            let offset = TimeInterval(time.hour * 3600 + time.minute * 60)
            start = .timed(day.startDate(in: timeZone).addingTimeInterval(offset))
        }
        return GoogleEvent(
            calendarID: "primary", id: "e" + String(index), iCalUID: nil,
            recurringEventID: spec.recurringEventID, title: spec.title, status: "confirmed",
            start: start, eventType: nil,
            selfResponse: spec.people.first(where: \.isSelf)?.responseStatus,
            attendees: spec.people)
    }

    // MARK: - Tasks

    private struct TaskSpec {
        let title: String
        let notes: String?
        let due: CalendarDay?
    }

    private static func tasks(_ specs: [TaskSpec]) -> [GoogleTask] {
        specs.enumerated().map { index, spec in
            GoogleTask(
                id: "t" + String(index), title: spec.title, notes: spec.notes,
                status: "needsAction", due: spec.due, position: nil)
        }
    }

    private var todos: [TaskSpec] {
        let day = Self.day
        let longStrings = AgendaContentFixtures.longStrings
        switch fixture {
        case .standard:
            return [
                TaskSpec(
                    title: "Send the slides", notes: "Ask Ben for the Q3 numbers first",
                    due: day.adding(days: -2)),
                TaskSpec(title: "Call the bank", notes: nil, due: day),
                TaskSpec(title: "Nora - to be discussed", notes: nil, due: day.adding(days: 1)),
                TaskSpec(title: "Peter – to be discussed", notes: nil, due: day.adding(days: 2)),
                TaskSpec(title: "Book flights", notes: nil, due: day.adding(days: 3)),
                TaskSpec(title: "Renew passport", notes: nil, due: day.adding(days: 9)),
                TaskSpec(title: "Someday", notes: nil, due: nil),
            ]
        case .longText:
            return (0...5).map { index in
                TaskSpec(title: longStrings[index], notes: longStrings[6], due: day)
            }
        case .overflow:
            return (0..<30).map { _ in
                TaskSpec(title: longStrings[0], notes: longStrings[6], due: day)
            }
        case .outOfOffice, .empty:
            return []
        }
    }

    private var delegated: [TaskSpec] {
        let day = Self.day
        let longStrings = AgendaContentFixtures.longStrings
        switch fixture {
        case .standard:
            return [
                TaskSpec(
                    title: "Anna: Hire a designer",
                    notes: "#weekly\n2026-09-16 Delegated to Anna.\n"
                        + "2026-09-23 Interviews scheduled.\n2026-09-29 Two candidates left.",
                    due: day),
                TaskSpec(
                    title: "Ben: Renew the office lease",
                    notes: "#monthly\n2026-09-01 Waiting for the landlord.",
                    due: day.adding(days: 10)),
                TaskSpec(title: "Fix the printer", notes: nil, due: nil),
            ]
        case .longText:
            let notes =
                "#weekly\n" + longStrings[0] + "\n" + longStrings[2] + "\n" + longStrings[3]
            return [
                TaskSpec(title: longStrings[1] + ": " + longStrings[0], notes: notes, due: day),
                TaskSpec(title: longStrings[1] + ": " + longStrings[3], notes: notes, due: day),
                TaskSpec(title: "Owner: " + longStrings[2], notes: notes, due: day),
            ]
        case .overflow:
            let cadences = ["daily", "weekly", "monthly"]
            return (0..<40).map { index in
                let lines = String(repeating: "\n" + longStrings[0], count: 5)
                return TaskSpec(
                    title: "Alexandra Montgomery-Smith: Delegated task " + String(index) + " "
                        + longStrings[0],
                    notes: "#" + cadences[index % 3] + lines,
                    due: index % 4 == 0 ? day : day.adding(days: 7))
            }
        case .outOfOffice, .empty:
            return []
        }
    }
}

/// A `GoogleAccount` that signs in without contacting Google.
public actor FixtureGoogleAccount: GoogleAccount {
    private var configuration: GoogleOAuthConfiguration?
    private var signedIn: Bool

    /// Creates an unconfigured account that is, or is not, signed in once configured.
    public init(signedIn: Bool) {
        self.signedIn = signedIn
    }

    /// Stores the OAuth client.
    public func configure(_ configuration: GoogleOAuthConfiguration?) {
        self.configuration = configuration
    }

    /// Whether an OAuth client has been set.
    public func isConfigured() -> Bool {
        configuration != nil
    }

    /// Whether a client is set and the account is signed in.
    public func isSignedIn() -> Bool {
        configuration != nil && signedIn
    }

    /// Signs in without calling `authenticate`; fails with `.notConfigured` before `configure`.
    public func signIn(
        authenticate: @escaping @Sendable (URL, String) async throws -> URL
    ) async throws {
        guard configuration != nil else {
            throw GoogleAPIError.notConfigured
        }
        signedIn = true
    }

    /// Signs out.
    public func signOut() {
        signedIn = false
    }
}
