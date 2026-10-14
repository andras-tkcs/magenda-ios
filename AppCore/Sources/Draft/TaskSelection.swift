import Foundation

/// The rules that decide which Google Tasks reach the agenda and why.
public enum TaskSelection {
    private struct Candidate {
        let task: GoogleTask
        let title: String
        let due: CalendarDay
        /// 1 when Google gave the task no position, so those sort after positioned ones.
        let unpositioned: Int
        let position: String
        let order: Int
    }

    /// The personal tasks that are overdue, due on `day` or due within the look-ahead window, in
    /// the order they are listed on the agenda.
    public static func draftTasks(
        for day: CalendarDay, tasks: [GoogleTask], events: [DraftEvent], rules: BinderRules
    ) -> [DraftTask] {
        let limit = day.adding(days: min(max(rules.lookAheadDays, 0), 14))
        var candidates: [Candidate] = []
        for (order, task) in tasks.enumerated() {
            let title = TextFitter.normalized(task.title ?? "")
            if task.status == "needsAction", !title.isEmpty, let due = task.due, due <= limit {
                candidates.append(
                    Candidate(
                        task: task, title: title, due: due,
                        unpositioned: task.position == nil ? 1 : 0, position: task.position ?? "",
                        order: order))
            }
        }
        candidates.sort {
            ($0.due, $0.unpositioned, $0.position, $0.order)
                < ($1.due, $1.unpositioned, $1.position, $1.order)
        }
        return candidates.map { draftTask($0, day: day, events: events, rules: rules) }
    }

    /// The open tasks of the delegated list, parsed, in input order.
    public static func draftDelegated(for day: CalendarDay, tasks: [GoogleTask])
        -> [DraftDelegated]
    {
        tasks.filter {
            $0.status == "needsAction" && !TextFitter.normalized($0.title ?? "").isEmpty
        }.map { task in
            let parsed = DelegatedTask.parse(title: task.title, notes: task.notes)
            return DraftDelegated(
                id: task.id, originalText: parsed.text, text: parsed.text, owner: parsed.owner,
                cadence: parsed.cadence, marked: task.due.map { $0 <= day } ?? false,
                status: parsed.status, warning: parsed.warning, isIncluded: true)
        }
    }

    private static func draftTask(
        _ candidate: Candidate, day: CalendarDay, events: [DraftEvent], rules: BinderRules
    ) -> DraftTask {
        let bucket = bucket(of: candidate.due, on: day)
        var reason: String?
        var isIncluded = true
        if bucket == .upcoming && TaskTitle.isDiscussion(candidate.title) {
            let name = TaskTitle.discussionName(candidate.title)
            let meeting = name.flatMap { name in
                events.first { attends($0, name: name, rules: rules) }
            }
            if let name, let meeting {
                reason = "Kept: \(name) is in “\(meeting.originalTitle)” on this day"
            } else {
                isIncluded = false
                reason =
                    name.map { "To be discussed: no meeting with \($0) on this day" }
                    ?? "To be discussed"
            }
        }
        let due = candidate.due
        return DraftTask(
            id: candidate.task.id, originalText: candidate.title, text: candidate.title,
            notes: TextFitter.normalized(candidate.task.notes ?? ""),
            dueText: String(format: "%02d/%02d", due.month, due.day), bucket: bucket,
            reason: reason, isIncluded: isIncluded)
    }

    private static func bucket(of due: CalendarDay, on day: CalendarDay) -> TaskBucket {
        if due < day {
            return .overdue
        }
        return due == day ? .today : .upcoming
    }

    private static func attends(_ event: DraftEvent, name: String, rules: BinderRules) -> Bool {
        let folded = BinderText.fold(name)
        return event.isIncluded && event.hasOtherAttendees
            && (event.attendeeFirstNames.contains(folded)
                || rules.personAliases[folded].map { event.attendeeEmails.contains($0) } ?? false)
    }
}
