import Foundation

/// The texts and dates the page header shows for a day.
public struct HeaderFields: Equatable, Sendable {
    /// Day of the month and weekday, for example `1 THURSDAY`.
    public let heading: String
    /// The ISO calendar week, for example `CW 40`.
    public let calendarWeek: String
    /// The month name in capitals, for example `OCTOBER`.
    public let month: String
    /// The year, for example `2026`.
    public let year: String
    /// The day-of-month numbers of the day's week, Monday to Sunday.
    public let weekDays: [Int]

    /// Creates header fields from their parts.
    public init(heading: String, calendarWeek: String, month: String, year: String, weekDays: [Int])
    {
        self.heading = heading
        self.calendarWeek = calendarWeek
        self.month = month
        self.year = year
        self.weekDays = weekDays
    }
}

/// One week of the "next four weeks" overview.
public struct WeekRow: Equatable, Sendable {
    /// The ISO calendar week, for example `CW 40`.
    public let calendarWeek: String
    /// The day-of-month numbers, Monday to Sunday.
    public let days: [Int]

    /// Creates a week row from its parts.
    public init(calendarWeek: String, days: [Int]) {
        self.calendarWeek = calendarWeek
        self.days = days
    }
}

/// Calendar facts the page header and the overview need.
public enum CalendarMath {
    /// Weekday names in capitals, Monday first.
    public static let weekdayNames = [
        "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY",
    ]

    /// Month names in capitals, January first.
    public static let monthNames = [
        "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER",
        "OCTOBER", "NOVEMBER", "DECEMBER",
    ]

    /// Three-letter month names, January first.
    public static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// The header texts for `day`.
    public static func header(for day: CalendarDay) -> HeaderFields {
        HeaderFields(
            heading: "\(day.day) \(weekdayNames[day.weekdayIndex])",
            calendarWeek: "CW \(day.isoWeek)",
            month: monthNames[day.month - 1],
            year: String(day.year),
            weekDays: weekDays(of: day))
    }

    /// The week of `day` and the three after it.
    public static func nextFourWeeks(from day: CalendarDay) -> [WeekRow] {
        let monday = day.adding(days: -day.weekdayIndex)
        return (0..<4).map { offset in
            let start = monday.adding(days: offset * 7)
            return WeekRow(calendarWeek: "CW \(start.isoWeek)", days: weekDays(of: start))
        }
    }

    private static func weekDays(of day: CalendarDay) -> [Int] {
        let monday = day.adding(days: -day.weekdayIndex)
        return (0..<7).map { monday.adding(days: $0).day }
    }
}

/// The half-hour rows of the daily schedule, 8:00 to 18:59.
public enum ScheduleSlot {
    /// The number of slots.
    public static let count = 22

    /// The slot a time falls in, or nil outside 8:00–18:59.
    public static func index(hour: Int, minute: Int) -> Int? {
        guard (8...18).contains(hour) else {
            return nil
        }
        return (hour - 8) * 2 + (minute < 30 ? 0 : 1)
    }
}
