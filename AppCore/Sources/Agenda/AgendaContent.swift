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
public struct TodoItem: Equatable, Sendable {
    /// The task title.
    public var text: String
    /// The task's notes, empty when it has none.
    public var notes: String
    /// The due date as `MM/DD`, or empty.
    public var due: String

    /// Creates a to-do row.
    public init(text: String, notes: String, due: String) {
        self.text = text
        self.notes = notes
        self.due = due
    }
}

/// One line of the daily schedule.
public struct ScheduleEntry: Equatable, Sendable {
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
public struct DelegatedItem: Equatable, Sendable {
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

    /// Creates a delegated-task row.
    public init(text: String, owner: String, cadence: Cadence, marked: Bool, status: [String]) {
        self.text = text
        self.owner = owner
        self.cadence = cadence
        self.marked = marked
        self.status = status
    }
}

/// The plain data an agenda PDF is drawn from.
public struct AgendaContent: Equatable, Sendable {
    /// The day the agenda is for.
    public var date: CalendarDay
    /// The to-do list rows.
    public var todoItems: [TodoItem]
    /// At most one entry per slot; the layout uses the first if there are more.
    public var schedule: [ScheduleEntry]
    /// One meeting page each; empty means one blank meeting page.
    public var meetings: [String]
    /// The delegated-tasks rows.
    public var delegated: [DelegatedItem]

    /// Creates agenda content.
    public init(
        date: CalendarDay, todoItems: [TodoItem], schedule: [ScheduleEntry], meetings: [String],
        delegated: [DelegatedItem]
    ) {
        self.date = date
        self.todoItems = todoItems
        self.schedule = schedule
        self.meetings = meetings
        self.delegated = delegated
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
