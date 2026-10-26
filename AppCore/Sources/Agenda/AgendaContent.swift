/// How often a delegated task is checked in on.
public enum Cadence: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly

    /// The name shown on the page: `Daily`, `Weekly` or `Monthly`.
    public var label: String {
        rawValue.capitalized
    }
}

/// One row of the to-do list.
public struct TodoItem: Equatable, Codable, Sendable {
    /// The task title.
    public var text: String
    /// The task's notes, empty when it has none.
    public var notes: String
    /// The due date as `MM/DD`, or empty.
    public var due: String
    /// The ID of the task the row came from, if it came from one.
    public var taskID: String?

    /// Creates a to-do row.
    public init(text: String, notes: String, due: String, taskID: String? = nil) {
        self.text = text
        self.notes = notes
        self.due = due
        self.taskID = taskID
    }
}

/// One line of the daily schedule.
public struct ScheduleEntry: Equatable, Codable, Sendable {
    /// The half-hour slot, see ``ScheduleSlot``.
    public var slot: Int
    /// The title shown in the slot.
    public var text: String
    /// The meeting page this entry links to, if it has one.
    public var meetingIndex: Int?

    /// Creates a schedule entry.
    public init(slot: Int, text: String, meetingIndex: Int?) {
        self.slot = slot
        self.text = text
        self.meetingIndex = meetingIndex
    }
}

/// One row of the delegated-tasks page.
public struct DelegatedItem: Equatable, Codable, Sendable {
    /// The task.
    public var text: String
    /// Who owns it.
    public var owner: String
    /// How often it is checked in on.
    public var cadence: Cadence
    /// Whether a check-in is due.
    public var marked: Bool
    /// The latest log lines, oldest first.
    public var status: [String]
    /// The ID of the task the row came from, if it came from one.
    public var taskID: String?

    /// Creates a delegated-task row.
    public init(
        text: String, owner: String, cadence: Cadence, marked: Bool, status: [String],
        taskID: String? = nil
    ) {
        self.text = text
        self.owner = owner
        self.cadence = cadence
        self.marked = marked
        self.status = status
        self.taskID = taskID
    }
}

/// The plain data an agenda PDF is drawn from.
public struct AgendaContent: Equatable, Codable, Sendable {
    /// The day the agenda is for.
    public var date: CalendarDay
    /// The to-do list rows.
    public var todoItems: [TodoItem]
    /// At most one entry per slot; the layout uses the first if there are more.
    public var schedule: [ScheduleEntry]
    /// One meeting page each; empty means one blank meeting page.
    public var meetings: [String]
    /// The event ID of each meeting page, in the order of `meetings`; a meeting without one is
    /// keyed by its position.
    public var meetingIDs: [String]
    /// The delegated-tasks rows.
    public var delegated: [DelegatedItem]
    /// The summary routines of each meeting page, in the order of `meetings`, with the names they
    /// had when the day was rendered; an empty array means none.
    public var meetingSummaryRoutines: [[SummaryRoutine]]

    /// Creates agenda content.
    public init(
        date: CalendarDay, todoItems: [TodoItem], schedule: [ScheduleEntry], meetings: [String],
        meetingIDs: [String] = [], delegated: [DelegatedItem],
        meetingSummaryRoutines: [[SummaryRoutine]] = []
    ) {
        self.date = date
        self.todoItems = todoItems
        self.schedule = schedule
        self.meetings = meetings
        self.meetingIDs = meetingIDs
        self.delegated = delegated
        self.meetingSummaryRoutines = meetingSummaryRoutines
    }

    private enum CodingKeys: String, CodingKey {
        case date, todoItems, schedule, meetings, meetingIDs, delegated, meetingSummaryRoutines
    }

    /// Decodes content written by any build; a missing `meetingSummaryRoutines`, as in a day stored
    /// with the old `meetingSummarySkills`, is empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(CalendarDay.self, forKey: .date)
        todoItems = try container.decode([TodoItem].self, forKey: .todoItems)
        schedule = try container.decode([ScheduleEntry].self, forKey: .schedule)
        meetings = try container.decode([String].self, forKey: .meetings)
        meetingIDs = try container.decode([String].self, forKey: .meetingIDs)
        delegated = try container.decode([DelegatedItem].self, forKey: .delegated)
        meetingSummaryRoutines =
            try container.decodeIfPresent([[SummaryRoutine]].self, forKey: .meetingSummaryRoutines)
            ?? []
    }
}

extension Array where Element == DelegatedItem {
    /// Marked rows first, then daily, weekly and monthly; input order is kept within a group.
    public func sortedForPage() -> [DelegatedItem] {
        [true, false].flatMap { marked in
            Cadence.allCases.flatMap { cadence in
                filter { $0.marked == marked && $0.cadence == cadence }
            }
        }
    }
}
