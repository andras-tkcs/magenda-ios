import Foundation

/// How a personal task relates to the day being planned.
public enum TaskBucket: String, Equatable, Sendable {
    case overdue
    case today
    case upcoming

    /// The name shown next to the task.
    public var label: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Due today"
        case .upcoming: "Upcoming"
        }
    }
}

/// One personal task as the review screen shows it.
public struct DraftTask: Equatable, Identifiable, Sendable {
    /// Google's task ID.
    public let id: String
    /// The normalized title from Google Tasks.
    public let originalText: String
    /// The title shown on the to-do list.
    public var text: String
    /// The normalized notes, empty when there are none.
    public let notes: String
    /// The due date as `MM/DD`.
    public let dueText: String
    /// Whether the task is overdue, due on the day or coming up.
    public let bucket: TaskBucket
    /// Why a discussion task was kept or left out.
    public let reason: String?
    /// Whether the task is on the agenda.
    public var isIncluded: Bool

    /// Creates a task with every field given.
    public init(
        id: String, originalText: String, text: String, notes: String, dueText: String,
        bucket: TaskBucket, reason: String?, isIncluded: Bool
    ) {
        self.id = id
        self.originalText = originalText
        self.text = text
        self.notes = notes
        self.dueText = dueText
        self.bucket = bucket
        self.reason = reason
        self.isIncluded = isIncluded
    }
}

/// One delegated task as the review screen shows it.
public struct DraftDelegated: Equatable, Identifiable, Sendable {
    /// Google's task ID.
    public let id: String
    /// The task text parsed from the title.
    public let originalText: String
    /// The task text shown on the delegated page.
    public var text: String
    /// Who the task was delegated to, empty when the title has no owner.
    public let owner: String
    /// How often it is checked in on.
    public let cadence: Cadence
    /// Whether a check-in is due on or before the day.
    public let marked: Bool
    /// The last log lines, oldest first.
    public let status: [String]
    /// What was missing from the task, if anything.
    public let warning: String?
    /// Whether the task is on the delegated page.
    public var isIncluded: Bool

    /// Creates a delegated task with every field given.
    public init(
        id: String, originalText: String, text: String, owner: String, cadence: Cadence,
        marked: Bool, status: [String], warning: String?, isIncluded: Bool
    ) {
        self.id = id
        self.originalText = originalText
        self.text = text
        self.owner = owner
        self.cadence = cadence
        self.marked = marked
        self.status = status
        self.warning = warning
        self.isIncluded = isIncluded
    }
}
