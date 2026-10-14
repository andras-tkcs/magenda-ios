import Foundation

/// A calendar date without a time or a time zone: the day an agenda is for.
///
/// Arithmetic runs in UTC on the Gregorian calendar, so it is never shifted by daylight saving.
public struct CalendarDay: Hashable, Comparable, Codable, Sendable {
    /// The year, for example 2026.
    public let year: Int
    /// The month, 1 to 12.
    public let month: Int
    /// The day of the month, 1 to 31.
    public let day: Int

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private init(validYear year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day with these components, or nil when the date does not exist (for example 2026-02-30).
    public init?(year: Int, month: Int, day: Int) {
        let components = DateComponents(year: year, month: month, day: day)
        let calendar = Self.utcCalendar
        guard let date = calendar.date(from: components),
            calendar.dateComponents([.year, .month, .day], from: date) == components
        else {
            return nil
        }
        self.init(validYear: year, month: month, day: day)
    }

    /// The day written as `YYYY-MM-DD`; anything after the first 10 characters is ignored.
    public init?(isoString: String) {
        let parts = isoString.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.map(\.count) == [4, 2, 2],
            parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// The day `now` falls on in `timeZone`.
    public static func today(in timeZone: TimeZone, now: Date) -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return CalendarDay(
            validYear: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// The day as `YYYY-MM-DD`, for example `2026-10-01`.
    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Monday is 0 and Sunday is 6.
    public var weekdayIndex: Int {
        (Self.utcCalendar.component(.weekday, from: utcDate) + 5) % 7
    }

    /// The ISO 8601 week number, 1 to 53.
    public var isoWeek: Int {
        Self.isoCalendar.component(.weekOfYear, from: utcDate)
    }

    /// The day `days` after this one (before it when negative).
    public func adding(days: Int) -> CalendarDay {
        let parts = Self.utcCalendar.dateComponents(
            [.year, .month, .day], from: utcDate.addingTimeInterval(Double(days) * 86_400))
        return CalendarDay(
            validYear: parts.year ?? year, month: parts.month ?? month, day: parts.day ?? day)
    }

    /// The first Monday to Friday after this day.
    public func nextWeekday() -> CalendarDay {
        var next = adding(days: 1)
        while next.weekdayIndex >= 5 {
            next = next.adding(days: 1)
        }
        return next
    }

    /// Midnight at the start of this day in `timeZone`.
    public func startDate(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = DateComponents(year: year, month: month, day: day)
        return calendar.date(from: parts) ?? utcDate
    }

    /// Whether this day comes before `other`.
    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Decodes the `YYYY-MM-DD` string, failing for anything else.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = CalendarDay(isoString: text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not a YYYY-MM-DD date: \(text)")
        }
        self = day
    }

    /// Encodes the day as its `YYYY-MM-DD` string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }

    private var utcDate: Date {
        let parts = DateComponents(year: year, month: month, day: day)
        return Self.utcCalendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }
}
