/// What Settings shows for the chosen calendars.
public enum CalendarSelection {
    /// "Primary calendar" when `selectedIDs` is empty; else the titles of the calendars of
    /// `calendars` whose ID is selected, in `calendars`' order: one title, "A, B" for two, or
    /// "A, B and N more" for more; "N selected" when no selected ID names a known calendar.
    public static func summary(selectedIDs: [String], calendars: [GoogleCalendar]) -> String {
        guard !selectedIDs.isEmpty else { return "Primary calendar" }
        let selected = Set(selectedIDs)
        let titles = calendars.filter { selected.contains($0.id) }.map(\.title)
        switch titles.count {
        case 0: return "\(selectedIDs.count) selected"
        case 1: return titles[0]
        case 2: return "\(titles[0]), \(titles[1])"
        default: return "\(titles[0]), \(titles[1]) and \(titles.count - 2) more"
        }
    }
}
