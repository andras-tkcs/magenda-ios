// AppCore's event selection rules, reasons and notices.

import Foundation
import Testing

@testable import AppCore

@Suite("Event selection")
struct EventSelectionTests {
    private let zone = TimeZone(identifier: "Europe/Budapest") ?? .gmt
    private let rules = BinderRules.default
    private let day = EventSelectionTests.calendarDay(2026, 9, 30)
    private let saturday = EventSelectionTests.calendarDay(2026, 10, 3)

    private static func calendarDay(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        guard let result = CalendarDay(year: year, month: month, day: day) else {
            fatalError("Invalid test date")
        }
        return result
    }

    private let me = GoogleAttendee(
        email: "me@example.com", displayName: "Me", isSelf: true, isResource: false,
        responseStatus: "accepted")
    private let room = GoogleAttendee(
        email: "room-1@resource.calendar.google.com", displayName: nil, isSelf: false,
        isResource: true, responseStatus: "accepted")

    private func person(
        _ email: String, name: String? = nil, response: String? = "accepted"
    ) -> GoogleAttendee {
        GoogleAttendee(
            email: email, displayName: name, isSelf: false, isResource: false,
            responseStatus: response)
    }

    private func at(_ hour: Int, _ minute: Int = 0, on date: CalendarDay? = nil) -> Date {
        (date ?? day).startDate(in: zone).addingTimeInterval(Double(hour * 3600 + minute * 60))
    }

    private func event(
        _ title: String?, id: String = "e", calendar: String = "primary", uid: String? = nil,
        recurring: String? = nil, status: String? = "confirmed", start: EventStart? = nil,
        type: String? = nil, selfResponse: String? = nil, attendees: [GoogleAttendee] = []
    ) -> GoogleEvent {
        GoogleEvent(
            calendarID: calendar, id: id, iCalUID: uid, recurringEventID: recurring, title: title,
            status: status, start: start ?? .timed(at(9)), eventType: type,
            selfResponse: selfResponse, attendees: attendees)
    }

    private func drafts(_ events: [GoogleEvent], rules custom: BinderRules? = nil) -> [DraftEvent] {
        EventSelection.draftEvents(
            for: day, events: events, timeZone: zone, rules: custom ?? rules)
    }

    private func notices(_ events: [GoogleEvent], on date: CalendarDay? = nil) -> [String] {
        EventSelection.notices(for: date ?? day, events: events, timeZone: zone, rules: rules)
    }

    @Test("Cancelled, ignored types, all-day and other-day events are not listed")
    func notListed() {
        let tomorrow = day.adding(days: 1)
        let events = [
            event("Cancelled", id: "a", status: "cancelled"),
            event("Where", id: "b", type: "workingLocation"),
            event("Away", id: "c", type: "outOfOffice"),
            event("Birthday", id: "d", type: "birthday"),
            event("All day", id: "e", start: .allDay(day)),
            event("Tomorrow", id: "f", start: .timed(at(9, on: tomorrow))),
            event(
                "Late last night", id: "g", start: .timed(at(23, 30, on: day.adding(days: -1)))),
            event("Keep", id: "h", type: "default"),
        ]
        #expect(drafts(events).map(\.id) == ["primary|h"])
    }

    @Test("Events sort by start, then title, then input order")
    func sorting() {
        let events = [
            event("Zed", id: "1", start: .timed(at(10))),
            event("Beta", id: "2", start: .timed(at(9))),
            event("Alpha", id: "3", start: .timed(at(9))),
            event("Gamma", id: "4", uid: "x", start: .timed(at(9, 30))),
            event("Gamma", id: "5", uid: "y", start: .timed(at(9, 30))),
        ]
        let expected = ["primary|3", "primary|2", "primary|4", "primary|5", "primary|1"]
        #expect(drafts(events).map(\.id) == expected)
        let swapped = [events[4], events[3]]
        #expect(drafts(swapped).map(\.id) == ["primary|5", "primary|4"])
    }

    @Test("Declined wins over a personal block, and blocks match by prefix")
    func exclusions() {
        let events = [
            event("Lunch", id: "a", start: .timed(at(8)), selfResponse: "declined"),
            event("Lunch with Sam", id: "b", start: .timed(at(9))),
            event("Lunchtime talk", id: "c", start: .timed(at(10))),
            event("Start the day", id: "d", start: .timed(at(11))),
        ]
        let result = drafts(events)
        let expected: [EventExclusion?] = [.declined, .personalBlock, nil, .personalBlock]
        #expect(result.map(\.exclusion) == expected)
        #expect(result.map(\.isIncluded) == [false, false, true, false])
    }

    @Test("Copies of one event across calendars are duplicates, by iCalUID or by id")
    func duplicateByIdentity() {
        let events = [
            event("Planning", id: "a", calendar: "work", uid: "u1", start: .timed(at(9))),
            event(
                "Planning (copy)", id: "b", calendar: "family", uid: "u1", start: .timed(at(15))),
            event("Review", id: "same", calendar: "work", start: .timed(at(10))),
            event("Other", id: "same", calendar: "family", start: .timed(at(16))),
        ]
        let expected: [EventExclusion?] = [nil, nil, .duplicate, .duplicate]
        #expect(drafts(events).map(\.exclusion) == expected)
    }

    @Test("A same-title event within two hours is a duplicate, later ones are kept")
    func duplicateByTitle() {
        let summit = [
            event("Quarterly Summit", id: "a", start: .timed(at(8))),
            event("quarterly summit", id: "b", start: .timed(at(8, 30))),
        ]
        let firstExpected: [EventExclusion?] = [nil, .duplicate]
        #expect(drafts(summit).map(\.exclusion) == firstExpected)
        let sync = [
            event("Team sync", id: "a", start: .timed(at(9))),
            event("Team sync", id: "b", start: .timed(at(15))),
        ]
        let secondExpected: [EventExclusion?] = [nil, nil]
        #expect(drafts(sync).map(\.exclusion) == secondExpected)
        let near = [
            event("Team sync", id: "a", start: .timed(at(9))),
            event("Team sync", id: "b", start: .timed(at(10, 59))),
        ]
        let thirdExpected: [EventExclusion?] = [nil, .duplicate]
        #expect(drafts(near).map(\.exclusion) == thirdExpected)
        let boundary = [
            event("Team sync", id: "a", start: .timed(at(9))),
            event("Team sync", id: "b", start: .timed(at(11))),
        ]
        let fourthExpected: [EventExclusion?] = [nil, nil]
        #expect(drafts(boundary).map(\.exclusion) == fourthExpected)
    }

    @Test("An excluded event does not make a later same-title event a duplicate")
    func excludedIsNotAnAnchor() {
        let events = [
            event("Sync", id: "a", start: .timed(at(9)), selfResponse: "declined"),
            event("Sync", id: "b", start: .timed(at(9, 30))),
        ]
        let expected: [EventExclusion?] = [.declined, nil]
        #expect(drafts(events).map(\.exclusion) == expected)
    }

    @Test("Other attendees exclude the user, rooms and people who declined")
    func otherAttendees() {
        let cases: [([GoogleAttendee], Bool)] = [
            ([me], false),
            ([me, room], false),
            ([me, person("a@example.com", response: "declined")], false),
            ([me, person("a@example.com")], true),
            ([me, person("a@example.com", response: "needsAction")], true),
            ([me, person("a@example.com", response: nil)], true),
        ]
        for (attendees, expected) in cases {
            let result = drafts([event("Talk", attendees: attendees)])
            #expect(result[0].hasOtherAttendees == expected)
            #expect(result[0].includesMeetingPage == expected)
            #expect(result[0].isIncluded)
        }
    }

    @Test("Attendee emails and first names come from the other attendees")
    func attendeeNames() {
        let attendees = [
            me, room,
            person("Zoltan.K@Example.com", name: "Zoltán Kovács"),
            person("peter.brown@example.com"),
            person("anna_smith@example.com", name: "  "),
            person("ben-x@example.com"),
            person("cara+tag@example.com"),
            person("dave@example.com"),
        ]
        let result = drafts([event("Talk", attendees: attendees)])[0]
        #expect(result.attendeeFirstNames == ["zoltan", "peter", "anna", "ben", "cara", "dave"])
        #expect(result.attendeeEmails.first == "zoltan.k@example.com")
        #expect(result.attendeeEmails.count == 6)
    }

    @Test("Page titles strip prefixes and a saved short name wins")
    func titles() {
        let original = "REMINDER // Decision about the office move"
        let plain = drafts([event(original, recurring: "rec-office")])[0]
        #expect(plain.originalTitle == original)
        #expect(plain.title == "Decision about the office move")
        #expect(plain.defaultTitle == plain.title)
        #expect(plain.shortNameKey == "r:rec-office")
        #expect(plain.id == "primary|e")
        var custom = rules
        custom.shortNames["r:rec-office"] = "Office move"
        let named = drafts([event(original, recurring: "rec-office")], rules: custom)[0]
        #expect(named.title == "Office move")
        #expect(named.defaultTitle == "Office move")
        #expect(named.originalTitle == original)
    }

    @Test("A missing or blank title becomes (No title)")
    func noTitle() {
        let result = drafts([
            event(nil, id: "a", start: .timed(at(9))),
            event(" \n ", id: "b", start: .timed(at(10))),
        ])
        #expect(result.map(\.originalTitle) == ["(No title)", "(No title)"])
        #expect(result.map(\.shortNameKey) == ["t:(no title)", "t:(no title)"])
    }

    @Test("Times and schedule slots follow the local start")
    func slots() {
        let events = [
            event("Early", id: "a", start: .timed(at(7))),
            event("First", id: "b", start: .timed(at(8))),
            event("Half", id: "c", start: .timed(at(9, 45))),
            event("Last", id: "d", start: .timed(at(18, 59))),
            event("Evening", id: "e", start: .timed(at(19))),
        ]
        let result = drafts(events)
        #expect(result.map(\.timeText) == ["07:00", "08:00", "09:45", "18:59", "19:00"])
        #expect(result.map(\.scheduleSlot) == [nil, 0, 3, 21, nil])
        #expect(result[0].start == at(7))
    }

    @Test("Every reason string, in order")
    func reasons() {
        let others = [me, person("a@example.com")]
        let result = drafts([
            event("Lunch", id: "a", start: .timed(at(7))),
            event("Solo", id: "b", start: .timed(at(9)), attendees: [me]),
            event("FW: Budget", id: "d", start: .timed(at(10)), attendees: others),
            event("Sync", id: "e", start: .timed(at(11)), attendees: others),
            event("Dinner", id: "c", start: .timed(at(19)), attendees: others),
        ])
        #expect(
            result.map(\.reasons) == [
                ["Personal block", "Not on the schedule: outside 8:00–18:59"],
                ["No meeting page: no other attendees"],
                ["Page title: Budget"],
                [],
                ["Not on the schedule: outside 8:00–18:59"],
            ])
        #expect(
            [EventExclusion.declined, .personalBlock, .duplicate].map(\.label) == [
                "Declined", "Personal block", "Duplicate of an earlier event",
            ])
    }

    @Test("Reasons follow the current meeting-page toggle")
    func pageToggle() {
        var draft = drafts([event("FW: Budget", attendees: [me, person("a@example.com")])])[0]
        draft.includesMeetingPage = false
        #expect(draft.reasons.isEmpty)
        draft.includesMeetingPage = true
        draft.title = "Budget"
        #expect(draft.reasons == ["Page title: Budget"])
    }

    @Test("A weekend day gets a notice")
    func weekend() {
        #expect(notices([], on: saturday) == ["Saturday, 3 October is a weekend."])
        #expect(notices([]).isEmpty)
    }

    @Test("Out-of-office events give a notice")
    func outOfOffice() {
        let message = "You're out of office on this day (“Vacation”)."
        #expect(notices([event("Vacation", start: .allDay(day))]) == [message])
        #expect(notices([event("Home", start: .allDay(day))]).isEmpty)
        let began = Self.calendarDay(2026, 9, 28)
        #expect(notices([event("Vacation", start: .allDay(began))]) == [message])
        #expect(notices([event("Vacation", start: .allDay(day.adding(days: 1)))]).isEmpty)
        #expect(
            notices([event(nil, start: .allDay(day), type: "outOfOffice")])
                == ["You're out of office on this day (“(No title)”)."])
        #expect(
            notices([event("Away  trip", type: "outOfOffice")])
                == ["You're out of office on this day (“Away trip”)."])
        #expect(notices([event("Vacation", status: "cancelled", start: .allDay(day))]).isEmpty)
    }

    @Test("Untitled and unrelated events give no out-of-office notice")
    func notOutOfOffice() {
        let events = [
            event(nil, id: "a", start: .allDay(day)),
            event("Vacation", id: "b", start: .timed(at(9))),
            event(
                "Away", id: "c", start: .timed(at(9, on: day.adding(days: 1))),
                type: "outOfOffice"),
        ]
        #expect(notices(events).isEmpty)
    }

    @Test("A weekend with an out-of-office event gives both notices in order")
    func weekendAndOutOfOffice() {
        #expect(
            notices([event("OOO - Budapest", start: .allDay(saturday))], on: saturday) == [
                "Saturday, 3 October is a weekend.",
                "You're out of office on this day (“OOO - Budapest”).",
            ])
    }
}
