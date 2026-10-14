import Foundation

/// Why an event is left out of the agenda by default.
public enum EventExclusion: String, Equatable, Sendable {
    case declined
    case personalBlock
    case duplicate

    /// The reason shown next to the event.
    public var label: String {
        switch self {
        case .declined: "Declined"
        case .personalBlock: "Personal block"
        case .duplicate: "Duplicate of an earlier event"
        }
    }
}

/// One calendar event as the review screen shows it.
public struct DraftEvent: Equatable, Identifiable, Sendable {
    /// `<calendarID>|<event id>`.
    public let id: String
    /// The normalized calendar title; "(No title)" when it is empty.
    public let originalTitle: String
    /// The meeting-page title.
    public var title: String
    /// What a blank edit restores.
    public var defaultTitle: String
    /// The key a saved short name is stored under.
    public let shortNameKey: String
    /// When the event starts.
    public let start: Date
    /// The local start as `HH:mm`.
    public let timeText: String
    /// The half-hour schedule slot, nil when the event starts outside 8:00–18:59.
    public let scheduleSlot: Int?
    /// Why the event is excluded by default, if it is.
    public let exclusion: EventExclusion?
    /// Whether anyone other than the user and rooms is attending.
    public let hasOtherAttendees: Bool
    /// The lowercased emails of the other attendees.
    public let attendeeEmails: [String]
    /// The folded first names of the other attendees.
    public let attendeeFirstNames: [String]
    /// Whether the event is on the agenda.
    public var isIncluded: Bool
    /// Whether the event gets a meeting page.
    public var includesMeetingPage: Bool

    /// Creates an event with every field given.
    public init(
        id: String, originalTitle: String, title: String, defaultTitle: String,
        shortNameKey: String, start: Date, timeText: String, scheduleSlot: Int?,
        exclusion: EventExclusion?, hasOtherAttendees: Bool, attendeeEmails: [String],
        attendeeFirstNames: [String], isIncluded: Bool, includesMeetingPage: Bool
    ) {
        self.id = id
        self.originalTitle = originalTitle
        self.title = title
        self.defaultTitle = defaultTitle
        self.shortNameKey = shortNameKey
        self.start = start
        self.timeText = timeText
        self.scheduleSlot = scheduleSlot
        self.exclusion = exclusion
        self.hasOtherAttendees = hasOtherAttendees
        self.attendeeEmails = attendeeEmails
        self.attendeeFirstNames = attendeeFirstNames
        self.isIncluded = isIncluded
        self.includesMeetingPage = includesMeetingPage
    }

    /// Why the event is treated the way it is, in display order.
    public var reasons: [String] {
        var result = exclusion.map { [$0.label] } ?? []
        if exclusion == nil && !hasOtherAttendees {
            result.append("No meeting page: no other attendees")
        }
        if scheduleSlot == nil {
            result.append("Not on the schedule: outside 8:00–18:59")
        }
        if includesMeetingPage && title != originalTitle {
            result.append("Page title: \(title)")
        }
        return result
    }
}
