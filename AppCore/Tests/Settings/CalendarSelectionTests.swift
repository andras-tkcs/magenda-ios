// AppCore's summary of the chosen calendars, which Settings shows on its Calendars row.

import AppCore
import Testing

@Suite("Calendar selection summary")
struct CalendarSelectionTests {
    private let calendars = [
        GoogleCalendar(id: "a", title: "Alpha", isPrimary: true),
        GoogleCalendar(id: "b", title: "Beta", isPrimary: false),
        GoogleCalendar(id: "c", title: "Gamma", isPrimary: false),
        GoogleCalendar(id: "d", title: "Delta", isPrimary: false),
    ]

    @Test("an empty selection is the primary calendar")
    func empty() {
        #expect(
            CalendarSelection.summary(selectedIDs: [], calendars: calendars) == "Primary calendar")
    }

    @Test("one calendar shows its title")
    func one() {
        #expect(CalendarSelection.summary(selectedIDs: ["b"], calendars: calendars) == "Beta")
    }

    @Test("two calendars show in the order of the calendars, not of the selection")
    func two() {
        #expect(
            CalendarSelection.summary(selectedIDs: ["c", "a"], calendars: calendars)
                == "Alpha, Gamma")
    }

    @Test("three calendars name two and count one more")
    func three() {
        #expect(
            CalendarSelection.summary(selectedIDs: ["c", "b", "a"], calendars: calendars)
                == "Alpha, Beta and 1 more")
    }

    @Test("four calendars name two and count two more")
    func four() {
        #expect(
            CalendarSelection.summary(selectedIDs: ["d", "c", "b", "a"], calendars: calendars)
                == "Alpha, Beta and 2 more")
    }

    @Test("unknown IDs are ignored when at least one is known")
    func unknownIgnored() {
        #expect(
            CalendarSelection.summary(selectedIDs: ["gone", "b"], calendars: calendars) == "Beta")
    }

    @Test("only unknown IDs show how many are selected")
    func onlyUnknown() {
        #expect(
            CalendarSelection.summary(selectedIDs: ["x", "y"], calendars: calendars)
                == "2 selected")
    }
}
