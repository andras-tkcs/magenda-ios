// AppCore's Google Calendar client: the exact requests it sends and how it reads the recorded
// responses. Every name and address in the fixtures is made up.

import AppCore
import Foundation
import Testing

private let budapest = TimeZone(identifier: "Europe/Budapest") ?? .gmt
private let sep30 = CalendarDay(isoString: "2026-09-30") ?? CalendarDay.today(in: .gmt, now: .now)
private let eventsBase = "https://www.googleapis.com/calendar/v3/calendars/"
private let eventsQuery =
    "?timeMin=2026-09-29T22%3A00%3A00Z&timeMax=2026-09-30T22%3A00%3A00Z&singleEvents=true"
    + "&orderBy=startTime&maxResults=250&timeZone=Europe%2FBudapest"

private struct Unreachable: Error, Equatable {}

private func events(
    _ sender: FakeSender, calendarID: String = "ada@example.com"
) async throws -> [GoogleEvent] {
    try await GoogleCalendarClient(sender: sender).events(
        calendarID: calendarID, on: sep30, timeZone: budapest)
}

@Suite("Google Calendar client: calendars")
struct GoogleCalendarListTests {
    @Test("The calendar list request asks for readable calendars, 250 at a time")
    func request() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "calendar-list")
        _ = try await GoogleCalendarClient(sender: sender).calendars()
        let request = try #require(sender.requests.first)
        #expect(
            request.url.absoluteString
                == "https://www.googleapis.com/calendar/v3/users/me/calendarList"
                + "?minAccessRole=reader&maxResults=250")
        #expect(request.method == .get)
        #expect(sender.requests.count == 1)
    }

    @Test("Titles fall back from the override to the summary to the ID, and primary is read")
    func titles() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "calendar-list")
        let calendars = try await GoogleCalendarClient(sender: sender).calendars()
        #expect(
            calendars == [
                GoogleCalendar(id: "ada@example.com", title: "Ada's work", isPrimary: true),
                GoogleCalendar(
                    id: "team-9f8e@group.calendar.google.com", title: "Platform team",
                    isPrimary: false),
                GoogleCalendar(
                    id: "holidays-4c2d@group.calendar.google.com",
                    title: "holidays-4c2d@group.calendar.google.com", isPrimary: false),
            ])
    }

    @Test("A response with no items is an empty list")
    func empty() async throws {
        let sender = FakeSender()
        sender.enqueue(json: "{}")
        #expect(try await GoogleCalendarClient(sender: sender).calendars().isEmpty)
    }

    @Test("A body that is not a calendar list is an unexpected response")
    func malformed() async throws {
        let sender = FakeSender()
        sender.enqueue(json: "[1, 2]")
        await #expect(throws: GoogleAPIError.unexpectedResponse) {
            try await GoogleCalendarClient(sender: sender).calendars()
        }
    }

    @Test("An error from the sender passes through")
    func senderError() async throws {
        let sender = FakeSender([.failure(GoogleAPIError.rateLimited)])
        await #expect(throws: GoogleAPIError.rateLimited) {
            try await GoogleCalendarClient(sender: sender).calendars()
        }
    }
}

@Suite("Google Calendar client: events")
struct GoogleEventsTests {
    @Test("The request asks for the local day in UTC with no plus sign anywhere")
    func request() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "events-all-day")
        _ = try await events(sender)
        let url = try #require(sender.requests.first).url.absoluteString
        #expect(url == eventsBase + "ada@example.com/events" + eventsQuery)
        #expect(!url.contains("+"))
    }

    @Test("A calendar ID with a hash is percent-encoded in the path")
    func encodedCalendarID() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "events-all-day")
        _ = try await events(sender, calendarID: "a#b@group.calendar.google.com")
        let url = try #require(sender.requests.first).url.absoluteString
        #expect(url == eventsBase + "a%23b@group.calendar.google.com/events" + eventsQuery)
    }

    @Test("Two pages are read, the second asked for with the page token")
    func twoPages() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "events-page1")
        try sender.enqueue(fixture: "events-page2")
        let found = try await events(sender)
        #expect(found.map(\.id) == ["evt-standup-0930", "evt-review-1100", "evt-lunch-1230"])
        #expect(sender.requests.count == 2)
        let second = try #require(sender.requests.last).url.absoluteString
        let expected = eventsBase + "ada@example.com/events" + eventsQuery
        #expect(second == expected + "&pageToken=page-two-token")
    }

    @Test("A plus sign and other reserved characters in query values are percent-encoded")
    func escapedQueryValues() async throws {
        let sender = FakeSender()
        sender.enqueue(json: #"{"items": [], "nextPageToken": "a+b/c=d&e"}"#)
        sender.enqueue(json: #"{"items": []}"#)
        let zone = try #require(TimeZone(identifier: "Etc/GMT+5"))
        _ = try await GoogleCalendarClient(sender: sender).events(
            calendarID: "ada@example.com", on: sep30, timeZone: zone)
        let first = try #require(sender.requests.first).url.absoluteString
        #expect(first.hasSuffix("&timeZone=Etc%2FGMT%2B5"))
        #expect(!first.contains("+"))
        let second = try #require(sender.requests.last).url.absoluteString
        #expect(second.hasSuffix("&timeZone=Etc%2FGMT%2B5&pageToken=a%2Bb%2Fc%3Dd%26e"))
        let items = URLComponents(string: second)?.queryItems ?? []
        #expect(items.first { $0.name == "pageToken" }?.value == "a+b/c=d&e")
        #expect(items.first { $0.name == "timeZone" }?.value == "Etc/GMT+5")
    }

    @Test("Paging stops after ten pages even when Google keeps offering more")
    func pageCap() async throws {
        let sender = FakeSender()
        for _ in 0..<12 {
            sender.enqueue(json: #"{"items": [], "nextPageToken": "again"}"#)
        }
        let found = try await events(sender)
        #expect(found.isEmpty)
        #expect(sender.requests.count == 10)
    }

    @Test("Timed starts are read with and without fractional seconds")
    func timedStarts() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "events-page1")
        try sender.enqueue(fixture: "events-page2")
        let found = try await events(sender)
        let standup: TimeInterval = 1_790_753_400
        let review: TimeInterval = 1_790_758_800.25
        let lunch: TimeInterval = 1_790_764_200
        #expect(
            found.map(\.start) == [
                .timed(Date(timeIntervalSince1970: standup)),
                .timed(Date(timeIntervalSince1970: review)),
                .timed(Date(timeIntervalSince1970: lunch)),
            ])
    }

    @Test("All-day starts are read as days, with event type and status")
    func allDay() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "events-all-day")
        let found = try await events(sender)
        #expect(found.map(\.start) == [.allDay(sep30), .allDay(sep30)])
        #expect(found.map(\.eventType) == ["default", "outOfOffice"])
        #expect(found.map(\.status) == ["confirmed", "confirmed"])
        #expect(found.map(\.title) == ["Team offsite", "OOO"])
        #expect(found.map(\.calendarID) == ["ada@example.com", "ada@example.com"])
        #expect(found.map(\.attendees) == [[], []])
    }

    @Test("An event with neither a start date nor a start time is skipped")
    func noStart() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "events-page2")
        let found = try await events(sender)
        #expect(found.map(\.id) == ["evt-lunch-1230"])
    }

    @Test("An event whose start does not parse as either form is skipped")
    func unparseableStart() async throws {
        let sender = FakeSender()
        sender.enqueue(
            json: #"{"items": [{"id": "x", "start": {"dateTime": "tomorrow", "date": "soon"}}]}"#)
        #expect(try await events(sender).isEmpty)
    }

    @Test("The recurring series ID, iCalendar UID and own response are read")
    func identifiers() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "events-page1")
        sender.enqueue(json: "{}")
        let found = try await events(sender)
        let standup = try #require(found.first)
        #expect(standup.recurringEventID == "standup-series")
        #expect(standup.iCalUID == "standup-series@example.com")
        #expect(standup.selfResponse == "accepted")
        let review = try #require(found.last)
        #expect(review.recurringEventID == nil)
        #expect(review.selfResponse == nil)
        #expect(review.status == "tentative")
    }

    @Test("Attendees keep self, people and rooms, and skip entries with no address")
    func attendees() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "events-page1")
        sender.enqueue(json: "{}")
        let found = try await events(sender)
        let standup = try #require(found.first)
        #expect(
            standup.attendees == [
                GoogleAttendee(
                    email: "ada@example.com", displayName: "Ada Lovelace", isSelf: true,
                    isResource: false, responseStatus: "accepted"),
                GoogleAttendee(
                    email: "grace@example.com", displayName: "Grace Hopper", isSelf: false,
                    isResource: false, responseStatus: "tentative"),
                GoogleAttendee(
                    email: "room-12@resource.calendar.google.com", displayName: "Room 12",
                    isSelf: false, isResource: true, responseStatus: "accepted"),
                GoogleAttendee(
                    email: "Annex-3@Resource.Calendar.Google.com", displayName: nil,
                    isSelf: false, isResource: true, responseStatus: "needsAction"),
            ])
        #expect(try #require(found.last).attendees.isEmpty)
    }

    @Test("A body that does not decode is an unexpected response")
    func malformed() async throws {
        let sender = FakeSender()
        sender.enqueue(json: #"{"items": "none"}"#)
        await #expect(throws: GoogleAPIError.unexpectedResponse) {
            try await events(sender)
        }
    }

    @Test("A response with no items is an empty list")
    func empty() async throws {
        let sender = FakeSender()
        sender.enqueue(json: "{}")
        #expect(try await events(sender).isEmpty)
    }

    @Test("An error from the sender passes through")
    func senderError() async throws {
        let sender = FakeSender([.failure(Unreachable())])
        await #expect(throws: Unreachable()) {
            try await events(sender)
        }
    }
}

@Suite("Live Google data source: calendar")
struct LiveGoogleCalendarForwardingTests {
    @Test("Calendars and events are forwarded to the Calendar client")
    func forwards() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "calendar-list")
        try sender.enqueue(fixture: "events-all-day")
        let source = LiveGoogleDataSource(
            calendar: GoogleCalendarClient(sender: sender),
            tasks: GoogleTasksClient(sender: sender))
        #expect(try await source.calendars().count == 3)
        let found = try await source.events(
            calendarID: "ada@example.com", on: sep30, timeZone: budapest)
        #expect(found.count == 2)
        #expect(sender.requests.count == 2)
    }
}
