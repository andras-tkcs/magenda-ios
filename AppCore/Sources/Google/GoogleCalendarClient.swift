import Foundation

/// Reads calendars and events from the Google Calendar API.
public struct GoogleCalendarClient: Sendable {
    private let sender: any AuthorizedHTTPSending

    /// Creates a client that sends through `sender`.
    public init(sender: any AuthorizedHTTPSending) {
        self.sender = sender
    }

    /// The calendars the person can read, in Google's order.
    public func calendars() async throws -> [GoogleCalendar] {
        let pages = try await GoogleAPI.pages(
            CalendarListPage.self, sender: sender,
            url: GoogleAPI.url(
                host: "www.googleapis.com", path: "calendar/v3/users/me/calendarList"),
            query: [
                URLQueryItem(name: "minAccessRole", value: "reader"),
                URLQueryItem(name: "maxResults", value: "250"),
            ], nextPageToken: \.nextPageToken)
        return pages.flatMap { $0.items ?? [] }.map { item in
            GoogleCalendar(
                id: item.id, title: item.summaryOverride ?? item.summary ?? item.id,
                isPrimary: item.primary == true)
        }
    }

    /// The events of `calendarID` that start on `day` in `timeZone`, ordered by start. An event
    /// with neither a start date nor a start time is left out.
    public func events(calendarID: String, on day: CalendarDay, timeZone: TimeZone) async throws
        -> [GoogleEvent]
    {
        // Written in UTC with a `Z`, so the query never holds a `+`, which Google reads as a space.
        // The formatter is not `Sendable`, so each call makes its own.
        let utc = ISO8601DateFormatter()
        utc.timeZone = .gmt
        let start = day.startDate(in: timeZone)
        let end = day.adding(days: 1).startDate(in: timeZone)
        let pages = try await GoogleAPI.pages(
            EventsPage.self, sender: sender,
            url: GoogleAPI.url(host: "www.googleapis.com", path: "calendar/v3/calendars")
                .appending(path: calendarID).appending(path: "events"),
            query: [
                URLQueryItem(name: "timeMin", value: utc.string(from: start)),
                URLQueryItem(name: "timeMax", value: utc.string(from: end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "250"),
                URLQueryItem(name: "timeZone", value: timeZone.identifier),
            ], nextPageToken: \.nextPageToken)
        let whole = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return pages.flatMap { $0.items ?? [] }.compactMap { item in
            Self.event(item, calendarID: calendarID, whole: whole, fractional: fractional)
        }
    }

    private static func event(
        _ item: EventDTO, calendarID: String, whole: ISO8601DateFormatter,
        fractional: ISO8601DateFormatter
    ) -> GoogleEvent? {
        let start: EventStart
        if let text = item.start?.dateTime,
            let date = whole.date(from: text) ?? fractional.date(from: text)
        {
            start = .timed(date)
        } else if let text = item.start?.date, let day = CalendarDay(isoString: text) {
            start = .allDay(day)
        } else {
            return nil
        }
        let attendees = (item.attendees ?? []).compactMap { entry -> GoogleAttendee? in
            guard let email = entry.email else {
                return nil
            }
            let isRoom = email.lowercased().hasSuffix("@resource.calendar.google.com")
            return GoogleAttendee(
                email: email, displayName: entry.displayName, isSelf: entry.isSelf == true,
                isResource: entry.resource == true || isRoom, responseStatus: entry.responseStatus)
        }
        return GoogleEvent(
            calendarID: calendarID, id: item.id, iCalUID: item.iCalUID,
            recurringEventID: item.recurringEventId, title: item.summary, status: item.status,
            start: start, eventType: item.eventType,
            selfResponse: attendees.first(where: \.isSelf)?.responseStatus, attendees: attendees)
    }
}

private struct CalendarListPage: Decodable {
    struct Item: Decodable {
        let id: String
        let summary: String?
        let summaryOverride: String?
        let primary: Bool?
    }

    let items: [Item]?
    let nextPageToken: String?
}

private struct EventsPage: Decodable {
    let items: [EventDTO]?
    let nextPageToken: String?
}

private struct EventDTO: Decodable {
    struct When: Decodable {
        let date: String?
        let dateTime: String?
    }

    struct Entry: Decodable {
        let email: String?
        let displayName: String?
        let responseStatus: String?
        let isSelf: Bool?
        let resource: Bool?

        enum CodingKeys: String, CodingKey {
            case email, displayName, responseStatus, resource
            case isSelf = "self"
        }
    }

    let id: String
    let iCalUID: String?
    let recurringEventId: String?
    let summary: String?
    let status: String?
    let eventType: String?
    let start: When?
    let attendees: [Entry]?
}
