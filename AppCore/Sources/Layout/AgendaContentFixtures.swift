import Foundation

/// Agenda content used to prove the layout copes with ordinary, extreme and empty input.
public enum AgendaContentFixtures {
    /// Strings that stress fitting: long prose, an unbroken word, emoji, CJK, right-to-left text,
    /// control characters, and a very long run of words.
    public static let longStrings: [String] = [
        "Quarterly business review with the extended leadership team, finance, legal and the regional sales directors to agree next year's targets and hiring plan",
        String(repeating: "Supercalifragilistic", count: 10),
        String(repeating: "🎉🚀 Launch party 👩‍👩‍👧‍👦👩🏽‍💻 ", count: 8),
        String(repeating: "四半期業務レビュー会議と来年度の目標設定および採用計画", count: 3),
        "مراجعة الأعمال الفصلية مع فريق القيادة الموسع والمالية والشؤون القانونية والمبيعات",
        "Line one\nline two\ttabbed   and   spaced",
        String(repeating: "word ", count: 400),
    ]

    // A Wednesday in September: the widest month and weekday names. 2026-09-30 00:00 UTC.
    private static let day = CalendarDay.today(
        in: .gmt, now: Date(timeIntervalSince1970: 1_790_726_400))

    /// A normal day.
    public static let typical = AgendaContent(
        date: day,
        todoItems: [
            TodoItem(text: "Call the bank", notes: "", due: "09/30"),
            TodoItem(
                text: "Send the slides", notes: "Ask Ben for the Q3 numbers first", due: "09/28"),
            TodoItem(text: "Book flights", notes: "", due: "10/02"),
        ],
        schedule: [
            ScheduleEntry(slot: 2, text: "Team sync", meetingIndex: 0),
            ScheduleEntry(slot: 5, text: "1:1 with Anna", meetingIndex: 1),
        ],
        meetings: ["Team sync", "1:1 with Anna"],
        delegated: [
            DelegatedItem(
                text: "Hire a designer", owner: "Anna", cadence: .weekly, marked: true,
                status: ["Interviews scheduled", "Two candidates left"]),
            DelegatedItem(
                text: "Renew the office lease", owner: "Ben", cadence: .monthly, marked: false,
                status: ["Waiting for the landlord"]),
        ])

    /// Every kind of long text in every field, a little of each.
    public static let longText = AgendaContent(
        date: day,
        todoItems: (0...5).map { index in
            TodoItem(
                text: longStrings[index], notes: longStrings[(index + 1) % 7],
                due: longStrings[index])
        },
        schedule: (0...5).map { index in
            ScheduleEntry(slot: index * 4, text: longStrings[index], meetingIndex: index)
        },
        meetings: (0...5).map { longStrings[$0] },
        delegated: (0...5).map { index in
            DelegatedItem(
                text: longStrings[index], owner: longStrings[index],
                cadence: Cadence.allCases[index % 3], marked: index % 2 == 0,
                status: [
                    longStrings[index], longStrings[(index + 1) % 7], longStrings[(index + 2) % 7],
                ])
        })

    /// Far more than fits: to-dos past the grid, a full schedule, many meetings, many delegated
    /// pages.
    public static let overflow = AgendaContent(
        date: day,
        todoItems: (0..<30).map { _ in
            TodoItem(text: longStrings[0], notes: longStrings[6], due: "09/30")
        },
        schedule: (0..<22).map { index in
            ScheduleEntry(slot: index, text: longStrings[1], meetingIndex: index)
        },
        meetings: (0..<25).map { "Meeting \($0): " + longStrings[0] },
        delegated: (0..<40).map { index in
            DelegatedItem(
                text: "Delegated task \(index): " + longStrings[0],
                owner: "Alexandra Montgomery-Smith", cadence: Cadence.allCases[index % 3],
                marked: index % 4 == 0, status: Array(repeating: longStrings[0], count: 5))
        })

    /// Nothing but the date.
    public static let empty = AgendaContent(
        date: day, todoItems: [], schedule: [], meetings: [], delegated: [])
}
