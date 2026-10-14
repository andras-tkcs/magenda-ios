// AppCore's `CalendarMath` and `ScheduleSlot`: header fields, the next four weeks, slot indexes.

import AppCore
import Testing

@Suite("Calendar math")
struct CalendarMathTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> CalendarDay {
        try #require(CalendarDay(year: year, month: month, day: day))
    }

    @Test("The header for a Thursday")
    func header() throws {
        let fields = CalendarMath.header(for: try day(2026, 10, 1))
        #expect(fields.heading == "1 THURSDAY")
        #expect(fields.calendarWeek == "CW 40")
        #expect(fields.month == "OCTOBER")
        #expect(fields.year == "2026")
        #expect(fields.weekDays == [28, 29, 30, 1, 2, 3, 4])
    }

    @Test("The next four weeks start with the day's week")
    func nextFourWeeks() throws {
        let rows = CalendarMath.nextFourWeeks(from: try day(2026, 10, 1))
        #expect(
            rows == [
                WeekRow(calendarWeek: "CW 40", days: [28, 29, 30, 1, 2, 3, 4]),
                WeekRow(calendarWeek: "CW 41", days: [5, 6, 7, 8, 9, 10, 11]),
                WeekRow(calendarWeek: "CW 42", days: [12, 13, 14, 15, 16, 17, 18]),
                WeekRow(calendarWeek: "CW 43", days: [19, 20, 21, 22, 23, 24, 25]),
            ])
    }

    @Test("Week numbers wrap at a year boundary")
    func yearBoundary() throws {
        let rows = CalendarMath.nextFourWeeks(from: try day(2026, 12, 30))
        #expect(rows.map(\.calendarWeek) == ["CW 53", "CW 1", "CW 2", "CW 3"])
        #expect(rows[0].days == [28, 29, 30, 31, 1, 2, 3])
    }

    @Test("The name tables are complete")
    func nameTables() {
        #expect(CalendarMath.weekdayNames.count == 7)
        #expect(CalendarMath.monthNames.count == 12)
        #expect(CalendarMath.monthAbbreviations.count == 12)
        #expect(CalendarMath.monthAbbreviations[9] == "Oct")
    }

    @Test(
        "A time maps to its half-hour slot",
        arguments: [
            (8, 0, 0), (8, 29, 0), (8, 30, 1), (18, 59, 21), (13, 45, 11),
        ])
    func slotIndex(hour: Int, minute: Int, expected: Int) {
        #expect(ScheduleSlot.index(hour: hour, minute: minute) == expected)
    }

    @Test("A time outside the schedule has no slot", arguments: [(7, 59), (19, 0), (0, 0)])
    func slotOutsideSchedule(hour: Int, minute: Int) {
        #expect(ScheduleSlot.index(hour: hour, minute: minute) == nil)
    }

    @Test("The last slot index is one less than the count")
    func slotCount() {
        #expect(ScheduleSlot.index(hour: 18, minute: 59) == ScheduleSlot.count - 1)
    }
}
