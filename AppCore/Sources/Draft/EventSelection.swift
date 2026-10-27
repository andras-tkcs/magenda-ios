import Foundation

/// The rules that decide which calendar events reach the agenda and why.
public enum EventSelection {
    private static let ignoredTypes: Set<String> = ["workingLocation", "outOfOffice", "birthday"]
    private static let duplicateWindow: TimeInterval = 120 * 60

    private struct Candidate {
        let event: GoogleEvent
        let start: Date
        let title: String
        let order: Int
    }

    private struct Kept {
        let key: String
        let title: String
        let start: Date
    }

    /// The events of `day` in start order, each with its default exclusion and page settings.
    public static func draftEvents(
        for day: CalendarDay, events: [GoogleEvent], timeZone: TimeZone, rules: BinderRules
    ) -> [DraftEvent] {
        var candidates: [Candidate] = []
        for (order, event) in events.enumerated() {
            if case .timed(let start) = event.start, event.status != "cancelled",
                !ignoredTypes.contains(event.eventType ?? ""),
                CalendarDay.today(in: timeZone, now: start) == day
            {
                candidates.append(
                    Candidate(
                        event: event, start: start, title: displayTitle(event.title), order: order))
            }
        }
        candidates.sort {
            ($0.start, $0.title, $0.order) < ($1.start, $1.title, $1.order)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var kept: [Kept] = []
        var result: [DraftEvent] = []
        for candidate in candidates {
            let event = candidate.event
            let key = event.iCalUID ?? event.id
            let exclusion = exclusion(for: candidate, key: key, kept: kept, rules: rules)
            if exclusion == nil {
                kept.append(
                    Kept(
                        key: key, title: BinderText.fold(candidate.title), start: candidate.start))
            }
            let others = event.attendees.filter {
                !$0.isSelf && !$0.isResource && $0.responseStatus != "declined"
            }
            let title = MeetingTitle.pageTitle(
                originalTitle: candidate.title, recurringEventID: event.recurringEventID,
                rules: rules)
            let hour = calendar.component(.hour, from: candidate.start)
            let minute = calendar.component(.minute, from: candidate.start)
            result.append(
                DraftEvent(
                    id: event.calendarID + "|" + event.id,
                    originalTitle: candidate.title,
                    title: title,
                    defaultTitle: title,
                    shortNameKey: MeetingTitle.key(
                        originalTitle: candidate.title, recurringEventID: event.recurringEventID),
                    start: candidate.start,
                    timeText: String(format: "%02d:%02d", hour, minute),
                    scheduleSlot: ScheduleSlot.index(hour: hour, minute: minute),
                    exclusion: exclusion,
                    hasOtherAttendees: !others.isEmpty,
                    attendeeEmails: others.map { $0.email.lowercased() },
                    attendeeFirstNames: others.map(firstName),
                    isIncluded: exclusion == nil,
                    includesMeetingPage: exclusion == nil && !others.isEmpty,
                    summaryRoutineIDs: SummaryRoutines.routineIDs(
                        pageTitle: title, originalTitle: candidate.title,
                        rules: rules.summaryRoutines)))
        }
        return result
    }

    /// Warnings about `day` shown above the lists: a weekend, or an out-of-office event.
    public static func notices(
        for day: CalendarDay, events: [GoogleEvent], timeZone: TimeZone, rules: BinderRules
    ) -> [String] {
        var result: [String] = []
        if day.weekdayIndex >= 5 {
            let weekday = CalendarMath.weekdayNames[day.weekdayIndex].capitalized
            let month = CalendarMath.monthNames[day.month - 1].capitalized
            result.append("\(weekday), \(day.day) \(month) is a weekend.")
        }
        let outOfOffice = events.first {
            isOutOfOffice($0, on: day, timeZone: timeZone, words: rules.outOfOfficeWords)
        }
        if let outOfOffice {
            result.append(
                "You're out of office on this day (“\(displayTitle(outOfOffice.title))”).")
        }
        return result
    }

    private static func displayTitle(_ title: String?) -> String {
        let normalized = TextFitter.normalized(title ?? "")
        return normalized.isEmpty ? "(No title)" : normalized
    }

    private static func exclusion(
        for candidate: Candidate, key: String, kept: [Kept], rules: BinderRules
    ) -> EventExclusion? {
        if candidate.event.selfResponse == "declined" {
            return .declined
        }
        if rules.personalBlocks.contains(where: {
            BinderText.startsWithPhrase(candidate.title, $0)
        }) {
            return .personalBlock
        }
        let folded = BinderText.fold(candidate.title)
        let isDuplicate = kept.contains {
            $0.key == key
                || ($0.title == folded
                    && candidate.start.timeIntervalSince($0.start) < duplicateWindow)
        }
        return isDuplicate ? .duplicate : nil
    }

    private static func firstName(of attendee: GoogleAttendee) -> String {
        let name = TextFitter.normalized(attendee.displayName ?? "")
        let source = name.isEmpty ? attendee.email : name
        let stops: Set<Character> = name.isEmpty ? [".", "_", "-", "+", "@"] : [" "]
        return BinderText.fold(String(source.prefix(while: { !stops.contains($0) })))
    }

    private static func isOutOfOffice(
        _ event: GoogleEvent, on day: CalendarDay, timeZone: TimeZone, words: [String]
    ) -> Bool {
        let isOutOfOfficeType = event.eventType == "outOfOffice"
        let startsInRange: Bool
        switch event.start {
        case .allDay(let start):
            startsInRange = start <= day
        case .timed(let start):
            startsInRange = isOutOfOfficeType && CalendarDay.today(in: timeZone, now: start) == day
        }
        return event.status != "cancelled" && startsInRange
            && (isOutOfOfficeType
                || words.contains { BinderText.containsPhrase(event.title ?? "", $0) })
    }
}
