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

    private static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        return calendar
    }

    private init(validYear year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day with these components, or nil when the date does not exist (for example 2026-02-30).
    public init?(year: Int, month: Int, day: Int) {
        let days = Self.epochDays(year: year, month: month, day: day)
        let back = Self.civil(epochDays: days)
        guard year >= 1, back == (year, month, day) else {
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

    private init(epochDays: Int) {
        let (year, month, day) = Self.civil(epochDays: epochDays)
        self.init(validYear: year, month: month, day: day)
    }

    /// The day `now` falls on in `timeZone`.
    public static func today(in timeZone: TimeZone, now: Date) -> CalendarDay {
        let local = now.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: now))
        return CalendarDay(epochDays: Int((local / 86_400).rounded(.down)))
    }

    /// The day as `YYYY-MM-DD`, for example `2026-10-01`.
    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Monday is 0 and Sunday is 6.
    public var weekdayIndex: Int {
        (Self.epochDays(year: year, month: month, day: day) % 7 + 10) % 7
    }

    /// The ISO 8601 week number, 1 to 53.
    public var isoWeek: Int {
        Self.isoCalendar.component(.weekOfYear, from: utcDate)
    }

    /// The day `days` after this one (before it when negative).
    public func adding(days: Int) -> CalendarDay {
        CalendarDay(epochDays: Self.epochDays(year: year, month: month, day: day) + days)
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
        let offset = Double(timeZone.secondsFromGMT(for: utcDate))
        // Six hours in lands inside the local day whichever way daylight saving shifts midnight.
        return calendar.startOfDay(for: utcDate.addingTimeInterval(6 * 3600 - offset))
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
        Date(
            timeIntervalSince1970: Double(Self.epochDays(year: year, month: month, day: day))
                * 86_400)
    }

    /// Days since 1970-01-01 of a proleptic Gregorian date (year 1 or later).
    private static func epochDays(year: Int, month: Int, day: Int) -> Int {
        let shifted = year - (14 - month) / 12
        let era = shifted / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The inverse of ``epochDays(year:month:day:)``.
    private static func civil(epochDays: Int) -> (Int, Int, Int) {
        let shifted = epochDays + 719_468
        let era = Int((Double(shifted) / 146_097).rounded(.down))
        let dayOfEra = shifted - era * 146_097
        let yearOfEra =
            (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = (monthIndex + 2) % 12 + 1
        return (yearOfEra + era * 400 + (14 - month) / 12, month, day)
    }
}
