import Foundation

/// What the review screen shows and edits: every candidate event and task with its toggles.
public struct AgendaDraft: Equatable, Sendable {
    /// The day the agenda is for.
    public let date: CalendarDay
    /// Warnings shown above the lists; never in the PDF.
    public var notices: [String]
    /// The title prefixes a removed short name falls back to stripping.
    public let titlePrefixes: [String]
    /// The day's events in start order.
    public var events: [DraftEvent]
    /// The personal tasks in agenda order.
    public var tasks: [DraftTask]
    /// The delegated tasks.
    public var delegated: [DraftDelegated]
    /// The summary routine IDs per meeting title, see ``SummaryRoutines``.
    public let summaryRules: [String: [String]]
    /// The summary routines the person set up, in Settings order.
    public let summaryRoutines: [SummaryRoutine]

    /// Creates a draft with every field given.
    public init(
        date: CalendarDay, notices: [String], titlePrefixes: [String], events: [DraftEvent],
        tasks: [DraftTask], delegated: [DraftDelegated], summaryRules: [String: [String]] = [:],
        summaryRoutines: [SummaryRoutine] = []
    ) {
        self.date = date
        self.notices = notices
        self.titlePrefixes = titlePrefixes
        self.events = events
        self.tasks = tasks
        self.delegated = delegated
        self.summaryRules = summaryRules
        self.summaryRoutines = summaryRoutines
    }

    /// Sets an event's meeting-page title; a blank title restores the default.
    public mutating func setTitle(_ text: String, forEvent id: String) {
        let title = TextFitter.normalized(text)
        let rules = summaryRules
        Self.update(&events, id: id) {
            $0.title = title.isEmpty ? $0.defaultTitle : title
            $0.summaryRoutineIDs = SummaryRoutines.routineIDs(
                pageTitle: $0.title, originalTitle: $0.originalTitle, rules: rules)
        }
    }

    /// Sets the summary routines one event asks for; IDs naming no routine of `summaryRoutines`
    /// are dropped.
    public mutating func setSummaryRoutineIDs(_ ids: [String], forEvent id: String) {
        let known = Set(summaryRoutines.map(\.id))
        Self.update(&events, id: id) {
            $0.summaryRoutineIDs = ids.filter { known.contains($0) }
        }
    }

    /// Sets the title and default title of every event with `key`; a blank `title` goes back to
    /// the prefix-stripped calendar title.
    public mutating func applyShortName(_ title: String, key: String) {
        let name = TextFitter.normalized(title)
        let prefixes = titlePrefixes
        for index in events.indices where events[index].shortNameKey == key {
            let value =
                name.isEmpty
                ? MeetingTitle.stripped(events[index].originalTitle, prefixes: prefixes) : name
            events[index].title = value
            events[index].defaultTitle = value
            events[index].summaryRoutineIDs = SummaryRoutines.routineIDs(
                pageTitle: value, originalTitle: events[index].originalTitle, rules: summaryRules)
        }
    }

    /// Sets a task's text; a blank text restores the original.
    public mutating func setText(_ text: String, forTask id: String) {
        let value = TextFitter.normalized(text)
        Self.update(&tasks, id: id) {
            $0.text = value.isEmpty ? $0.originalText : value
        }
    }

    /// Sets a delegated task's text; a blank text restores the original.
    public mutating func setText(_ text: String, forDelegated id: String) {
        let value = TextFitter.normalized(text)
        Self.update(&delegated, id: id) {
            $0.text = value.isEmpty ? $0.originalText : value
        }
    }

    /// Puts an event on or off the agenda. Off also drops its meeting page; on gives it one when
    /// anyone else is attending.
    public mutating func setIncluded(_ on: Bool, forEvent id: String) {
        Self.update(&events, id: id) {
            $0.isIncluded = on
            $0.includesMeetingPage = on && $0.hasOtherAttendees
        }
    }

    /// Gives an included event a meeting page or takes it away; ignored for a left-out event.
    public mutating func setMeetingPage(_ on: Bool, forEvent id: String) {
        Self.update(&events, id: id) {
            if $0.isIncluded {
                $0.includesMeetingPage = on
            }
        }
    }

    /// Puts a personal task on or off the agenda.
    public mutating func setIncluded(_ on: Bool, forTask id: String) {
        Self.update(&tasks, id: id) { $0.isIncluded = on }
    }

    /// Puts a delegated task on or off the agenda.
    public mutating func setIncluded(_ on: Bool, forDelegated id: String) {
        Self.update(&delegated, id: id) { $0.isIncluded = on }
    }

    /// The plain data the PDF is drawn from.
    ///
    /// The schedule shows each included event's calendar title; two events in one slot share an
    /// entry joined with " / " and, as no single meeting page fits both, link to none.
    public func content() -> AgendaContent {
        var meetingIndexes: [String: Int] = [:]
        var meetings: [String] = []
        var meetingIDs: [String] = []
        var meetingSummaryRoutines: [[SummaryRoutine]] = []
        for event in events where event.includesMeetingPage {
            meetingIndexes[event.id] = meetings.count
            meetings.append(event.title)
            meetingIDs.append(event.id)
            meetingSummaryRoutines.append(
                SummaryRoutines.routines(ids: event.summaryRoutineIDs, in: summaryRoutines))
        }
        let scheduled = events.filter { $0.isIncluded && $0.scheduleSlot != nil }
        let schedule = Set(scheduled.compactMap(\.scheduleSlot)).sorted().map { slot in
            let group = scheduled.filter { $0.scheduleSlot == slot }
            return ScheduleEntry(
                slot: slot, text: group.map(\.originalTitle).joined(separator: " / "),
                meetingIndex: group.count == 1 ? meetingIndexes[group[0].id] : nil)
        }
        return AgendaContent(
            date: date,
            todoItems: tasks.filter(\.isIncluded).map {
                TodoItem(text: $0.text, notes: $0.notes, due: $0.dueText, taskID: $0.id)
            },
            schedule: schedule, meetings: meetings, meetingIDs: meetingIDs,
            delegated: delegated.filter(\.isIncluded).map {
                DelegatedItem(
                    text: $0.text, owner: $0.owner, cadence: $0.cadence, marked: $0.marked,
                    status: $0.status, taskID: $0.id)
            },
            meetingSummaryRoutines: meetingSummaryRoutines)
    }

    private static func update<Element: Identifiable>(
        _ items: inout [Element], id: Element.ID, change: (inout Element) -> Void
    ) {
        for index in items.indices where items[index].id == id {
            change(&items[index])
        }
    }
}
