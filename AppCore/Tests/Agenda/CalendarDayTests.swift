// AppCore's `CalendarDay`: validation, ISO strings, weekdays and day arithmetic.

import AppCore
import Foundation
import Testing

@Suite("Calendar days")
struct CalendarDayTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> CalendarDay {
        try #require(CalendarDay(year: year, month: month, day: day))
    }

    @Test(
        "An impossible date is rejected",
        arguments: [
            (2026, 2, 30), (2026, 13, 1), (2026, 0, 1), (2026, 4, 31), (2025, 2, 29), (0, 1, 1),
        ])
    func rejectsImpossibleDates(year: Int, month: Int, day: Int) {
        #expect(CalendarDay(year: year, month: month, day: day) == nil)
    }

    @Test("A leap day is accepted")
    func acceptsLeapDay() {
        #expect(CalendarDay(year: 2028, month: 2, day: 29) != nil)
    }

    @Test("The ISO string round-trips")
    func isoStringRoundTrips() throws {
        let value = try day(2026, 10, 1)
        #expect(value.isoString == "2026-10-01")
        #expect(CalendarDay(isoString: value.isoString) == value)
    }

    @Test("A timestamp's date part is accepted")
    func acceptsTimestamp() throws {
        #expect(CalendarDay(isoString: "2026-10-01T00:00:00.000Z") == (try day(2026, 10, 1)))
    }

    @Test(
        "A malformed string is rejected",
        arguments: ["2026-1-1", "", "2026/10/01", "abcd-ef-gh", "2026-02-30", "２０２６-１０-０１"])
    func rejectsMalformedStrings(text: String) {
        #expect(CalendarDay(isoString: text) == nil)
    }

    @Test("The weekday index counts from Monday")
    func weekdayIndex() throws {
        #expect(try day(2026, 10, 1).weekdayIndex == 3)
        #expect(try day(2026, 10, 5).weekdayIndex == 0)
        #expect(try day(2026, 10, 4).weekdayIndex == 6)
    }

    @Test("The ISO week follows the ISO year")
    func isoWeek() throws {
        #expect(try day(2026, 12, 31).isoWeek == 53)
        #expect(try day(2027, 1, 4).isoWeek == 1)
        #expect(try day(2026, 10, 1).isoWeek == 40)
    }

    @Test("Adding days crosses month and year ends")
    func addingDays() throws {
        #expect(try day(2026, 10, 30).adding(days: 3) == (try day(2026, 11, 2)))
        #expect(try day(2026, 12, 31).adding(days: 1) == (try day(2027, 1, 1)))
        #expect(try day(2026, 3, 1).adding(days: -1) == (try day(2026, 2, 28)))
        #expect(try day(2026, 10, 1).adding(days: 0) == (try day(2026, 10, 1)))
    }

    @Test(
        "The next weekday skips the weekend",
        arguments: [(1, 2), (2, 5), (3, 5), (4, 5)])
    func nextWeekday(from: Int, expected: Int) throws {
        #expect(try day(2026, 10, from).nextWeekday() == (try day(2026, 10, expected)))
    }

    @Test("Today depends on the time zone")
    func todayInTimeZones() throws {
        let now = Date(timeIntervalSince1970: 1_790_897_400)  // 2026-10-01 23:30 UTC
        let utc = try #require(TimeZone(identifier: "UTC"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(CalendarDay.today(in: utc, now: now) == (try day(2026, 10, 1)))
        #expect(CalendarDay.today(in: tokyo, now: now) == (try day(2026, 10, 2)))
    }

    @Test("The start date is local midnight")
    func startDate() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        let value = try day(2026, 10, 1)
        #expect(value.startDate(in: utc).timeIntervalSince1970 == 1_790_812_800)
        #expect(value.startDate(in: tokyo).timeIntervalSince1970 == 1_790_812_800 - 9 * 3600)
    }

    @Test("Days are ordered by date")
    func ordering() throws {
        #expect(try day(2026, 10, 1) < day(2026, 10, 2))
        #expect(try day(2026, 9, 30) < day(2026, 10, 1))
        #expect(try day(2025, 12, 31) < day(2026, 1, 1))
        #expect(!(try day(2026, 10, 1) < day(2026, 10, 1)))
    }

    @Test("A day encodes as its ISO string and decodes back")
    func codableRoundTrip() throws {
        let value = try day(2026, 10, 1)
        let data = try JSONEncoder().encode([value])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-10-01\"]")
        #expect(try JSONDecoder().decode([CalendarDay].self, from: data) == [value])
    }

    @Test("Decoding a malformed string fails")
    func decodingFails() {
        let data = Data("[\"nope\"]".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([CalendarDay].self, from: data)
        }
    }
}
