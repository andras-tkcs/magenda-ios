import Foundation

/// Turns what Google returned for a day into a draft to review.
public struct AgendaBuilder: Sendable {
    private let timeZone: TimeZone
    private let rules: BinderRules

    /// Creates a builder that reads local times in `timeZone` and applies `rules`.
    public init(timeZone: TimeZone, rules: BinderRules) {
        self.timeZone = timeZone
        self.rules = rules
    }

    /// The draft for `day` from its events, its personal tasks and its delegated tasks.
    public func draft(
        for day: CalendarDay, events: [GoogleEvent], tasks: [GoogleTask], delegated: [GoogleTask]
    ) -> AgendaDraft {
        let draftEvents = EventSelection.draftEvents(
            for: day, events: events, timeZone: timeZone, rules: rules)
        return AgendaDraft(
            date: day,
            notices: EventSelection.notices(
                for: day, events: events, timeZone: timeZone, rules: rules),
            titlePrefixes: rules.titlePrefixes,
            events: draftEvents,
            tasks: TaskSelection.draftTasks(
                for: day, tasks: tasks, events: draftEvents, rules: rules),
            delegated: TaskSelection.draftDelegated(for: day, tasks: delegated),
            summarySkills: rules.summarySkills)
    }
}
