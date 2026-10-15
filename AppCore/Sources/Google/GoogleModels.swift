import Foundation

/// A calendar the signed-in person can read.
public struct GoogleCalendar: Equatable, Identifiable, Sendable {
    /// Google's calendar ID, often an email address.
    public let id: String
    /// The name to show: the person's own override, else Google's summary, else the ID.
    public let title: String
    /// Whether this is the person's primary calendar.
    public let isPrimary: Bool

    /// Creates a calendar.
    public init(id: String, title: String, isPrimary: Bool) {
        self.id = id
        self.title = title
        self.isPrimary = isPrimary
    }
}

/// When an event starts: on a whole day, or at an instant.
public enum EventStart: Equatable, Sendable {
    /// An all-day event on this day.
    case allDay(CalendarDay)
    /// A timed event starting at this instant.
    case timed(Date)
}

/// One invitee of an event.
public struct GoogleAttendee: Equatable, Sendable {
    /// The invitee's email address.
    public let email: String
    /// The invitee's display name, if Google has one.
    public let displayName: String?
    /// Whether this invitee is the signed-in person.
    public let isSelf: Bool
    /// Whether this invitee is a room or other bookable resource.
    public let isResource: Bool
    /// The invitee's answer (`accepted`, `declined`, `tentative`, `needsAction`), if present.
    public let responseStatus: String?

    /// Creates an attendee.
    public init(
        email: String, displayName: String?, isSelf: Bool, isResource: Bool,
        responseStatus: String?
    ) {
        self.email = email
        self.displayName = displayName
        self.isSelf = isSelf
        self.isResource = isResource
        self.responseStatus = responseStatus
    }
}

/// One event, as the agenda needs it.
public struct GoogleEvent: Equatable, Sendable {
    /// The calendar the event was read from.
    public let calendarID: String
    /// Google's event ID.
    public let id: String
    /// The iCalendar UID shared by copies of the event on different calendars, if present.
    public let iCalUID: String?
    /// The ID of the recurring series this event is an instance of, if any.
    public let recurringEventID: String?
    /// The event title, if it has one.
    public let title: String?
    /// `confirmed`, `tentative` or `cancelled`, if present.
    public let status: String?
    /// When the event starts.
    public let start: EventStart
    /// Google's event type (`default`, `outOfOffice`, `focusTime`, ...), if present.
    public let eventType: String?
    /// The signed-in person's own answer, taken from their attendee entry.
    public let selfResponse: String?
    /// Every attendee, the signed-in person and rooms included.
    public let attendees: [GoogleAttendee]

    /// Creates an event.
    public init(
        calendarID: String, id: String, iCalUID: String?, recurringEventID: String?,
        title: String?, status: String?, start: EventStart, eventType: String?,
        selfResponse: String?, attendees: [GoogleAttendee]
    ) {
        self.calendarID = calendarID
        self.id = id
        self.iCalUID = iCalUID
        self.recurringEventID = recurringEventID
        self.title = title
        self.status = status
        self.start = start
        self.eventType = eventType
        self.selfResponse = selfResponse
        self.attendees = attendees
    }
}

/// A Google Tasks list.
public struct GoogleTaskList: Equatable, Identifiable, Sendable {
    /// Google's list ID.
    public let id: String
    /// The list's title.
    public let title: String

    /// Creates a task list.
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// One task.
public struct GoogleTask: Equatable, Sendable {
    /// Google's task ID.
    public let id: String
    /// The title, if it has one.
    public let title: String?
    /// The notes, if any.
    public let notes: String?
    /// `needsAction` or `completed`.
    public let status: String
    /// The due day, if the task has one.
    public let due: CalendarDay?
    /// Google's sort key within the list, if present.
    public let position: String?

    /// Creates a task.
    public init(
        id: String, title: String?, notes: String?, status: String, due: CalendarDay?,
        position: String?
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.due = due
        self.position = position
    }
}

/// Where the agenda gets its calendars, events and tasks.
public protocol GoogleDataSource: Sendable {
    /// The calendars the person can read.
    func calendars() async throws -> [GoogleCalendar]
    /// The events of `calendarID` that fall on `day` in `timeZone`, ordered by start.
    func events(calendarID: String, on day: CalendarDay, timeZone: TimeZone) async throws
        -> [GoogleEvent]
    /// The person's task lists.
    func taskLists() async throws -> [GoogleTaskList]
    /// The tasks of `listID` that are not completed.
    func openTasks(listID: String) async throws -> [GoogleTask]
}

/// A `GoogleDataSource` backed by the Calendar and Tasks clients.
public struct LiveGoogleDataSource: GoogleDataSource {
    private let calendar: GoogleCalendarClient
    private let tasks: GoogleTasksClient

    /// Creates a data source over the two clients.
    public init(calendar: GoogleCalendarClient, tasks: GoogleTasksClient) {
        self.calendar = calendar
        self.tasks = tasks
    }

    /// The calendars the person can read.
    public func calendars() async throws -> [GoogleCalendar] {
        try await calendar.calendars()
    }

    /// The events of `calendarID` that fall on `day` in `timeZone`.
    public func events(calendarID: String, on day: CalendarDay, timeZone: TimeZone) async throws
        -> [GoogleEvent]
    {
        try await calendar.events(calendarID: calendarID, on: day, timeZone: timeZone)
    }

    /// The person's task lists.
    public func taskLists() async throws -> [GoogleTaskList] {
        try await tasks.taskLists()
    }

    /// The tasks of `listID` that are not completed.
    public func openTasks(listID: String) async throws -> [GoogleTask] {
        try await tasks.openTasks(listID: listID)
    }
}

/// Request building and paging shared by the Calendar and Tasks clients.
enum GoogleAPI {
    /// Pages are followed at most this many times.
    static let maxPages = 10

    /// `https://<host>` followed by `path`. Callers append IDs with `appending(path:)`, never by
    /// writing them into a string, so a `#` or `?` in an ID is percent-encoded. A `/` stays a
    /// path separator; no Calendar or Tasks ID contains one.
    static func url(host: String, path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        // A fixed host always forms a URL, but `URLComponents.url` is optional. Replacing a
        // placeholder, rather than falling back to one, leaves no branch that never runs.
        var base = URL(fileURLWithPath: "/")
        if let built = components.url {
            base = built
        }
        return base.appending(path: path)
    }

    /// Fetches `url` with `query`, then each following page, decoding every body as `Page`.
    static func pages<Page: Decodable>(
        _ type: Page.Type, sender: any AuthorizedHTTPSending, url: URL,
        query: KeyValuePairs<String, String>, nextPageToken: (Page) -> String?
    ) async throws -> [Page] {
        var result: [Page] = []
        var token: String?
        for _ in 0..<maxPages {
            var items = Array(query)
            if let token {
                items.append((key: "pageToken", value: token))
            }
            let request = HTTPRequest(
                method: .get, url: withQuery(items, on: url), headers: [:], body: nil)
            let response = try await sender.send(request)
            let page: Page
            do {
                page = try JSONDecoder().decode(Page.self, from: response.body)
            } catch {
                throw GoogleAPIError.unexpectedResponse
            }
            result.append(page)
            guard let next = nextPageToken(page) else {
                break
            }
            token = next
        }
        return result
    }

    /// `url` with `items` as its query, every name and value escaped down to the unreserved
    /// characters. `appending(queryItems:)` would leave a `+` as it is, and Google reads a `+` in
    /// a query as a space, which breaks a time zone such as `Etc/GMT+5` or a page token.
    static func withQuery(_ items: [(key: String, value: String)], on url: URL) -> URL {
        let pairs = items.map { escaped($0.key) + "=" + escaped($0.value) }
        let query = pairs.joined(separator: "&")
        // `url` is always one `url(host:path:)` built, so the components and their URL exist; as
        // there, replacing it rather than falling back leaves no branch that never runs.
        var result = url
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.percentEncodedQuery = query
            if let built = components.url {
                result = built
            }
        }
        return result
    }

    private static let unreserved = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)

    /// `text` with every byte outside the unreserved characters percent-encoded.
    static func escaped(_ text: String) -> String {
        var result = ""
        for byte in text.utf8 {
            if unreserved.contains(byte) {
                result.append(Character(Unicode.Scalar(byte)))
            } else {
                result += String(format: "%%%02X", UInt32(byte))
            }
        }
        return result
    }
}
