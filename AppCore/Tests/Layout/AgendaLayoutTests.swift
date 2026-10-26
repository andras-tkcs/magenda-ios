// AppCore's `AgendaLayout` page list, header, meeting pages and further-notes page, measured with
// `FakeTextMeasurer` against the bundled template manifest, and the continued title of a copied
// meeting page.

import Testing

@testable import AppCore

@Suite("Agenda layout pages")
struct AgendaLayoutTests {
    private func day() throws -> CalendarDay {
        try #require(CalendarDay(year: 2026, month: 9, day: 30))
    }

    private func content(meetings: [String] = []) throws -> AgendaContent {
        AgendaContent(
            date: try day(), todoItems: [], schedule: [], meetings: meetings, delegated: [])
    }

    private func layout(theme: Theme = Theme()) throws -> AgendaLayout {
        AgendaLayout(
            manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer(), theme: theme)
    }

    private func runs(_ page: PagePlan) -> [TextRun] {
        page.operations.compactMap { operation -> TextRun? in
            if case .text(let run) = operation {
                return run
            }
            return nil
        }
    }

    @Test("A day without meetings has the overview, one blank meeting page and the notes page")
    func pageOrderWithoutMeetings() throws {
        let plan = try layout().plan(for: content())
        #expect(plan.pages.map(\.chrome) == [.overview, .meeting, .furtherNotes])
        #expect(plan.omittedTodoItems.isEmpty)
    }

    @Test("Pages are keyed: a blank meeting page without meetings")
    func keysWithoutMeetings() throws {
        let plan = try layout().plan(for: content())
        #expect(plan.pages.map(\.key) == [.overview, .meeting(""), .notes])
    }

    @Test("Meeting pages are keyed by event ID, or by position without one")
    func meetingKeys() throws {
        let day = try day()
        let withIDs = AgendaContent(
            date: day, todoItems: [], schedule: [], meetings: ["A", "B"], meetingIDs: ["x", "y"],
            delegated: [])
        #expect(
            try layout().plan(for: withIDs).pages.map(\.key)
                == [.overview, .meeting("x"), .meeting("y"), .notes])
        let hash = "#"
        let withoutIDs = try content(meetings: ["A", "B"])
        #expect(
            try layout().plan(for: withoutIDs).pages.map(\.key)
                == [.overview, .meeting("\(hash)0"), .meeting("\(hash)1"), .notes])
    }

    @Test("Each meeting gets its own page between the overview and the notes page")
    func pageOrderWithMeetings() throws {
        let plan = try layout().plan(for: content(meetings: ["A", "B", "C"]))
        let expected: [ChromePage] = [.overview, .meeting, .meeting, .meeting, .furtherNotes]
        #expect(plan.pages.map(\.chrome) == expected)
        #expect(runs(plan.pages[2]).contains { $0.text == "B" })
    }

    @Test("The plan carries the template's page size")
    func pageSize() throws {
        let plan = try layout().plan(for: content())
        #expect(abs(plan.pageWidth - 595.304) < 0.001)
        #expect(abs(plan.pageHeight - 841.890) < 0.001)
    }

    @Test("Every page carries the header for the day")
    func headerOnEveryPage() throws {
        let plan = try layout().plan(for: content(meetings: ["A", "B"]))
        for page in plan.pages {
            let texts = runs(page).map(\.text)
            for expected in ["30 WEDNESDAY", "CW 40", "SEPTEMBER", "2026", "MON", "28", "4"] {
                #expect(texts.contains(expected))
            }
        }
    }

    @Test("Header text may run to the content's right edge")
    func headerContainer() throws {
        let plan = try layout().plan(for: content())
        let heading = try #require(runs(plan.pages[0]).first { $0.text == "30 WEDNESDAY" })
        #expect(heading.container.x1 == 574.1)
    }

    @Test("A blank meeting page draws only its title label besides the header")
    func blankMeetingPage() throws {
        let plan = try layout().plan(for: content())
        let texts = runs(plan.pages[1]).map(\.text)
        #expect(texts.contains("Meeting title:"))
        #expect(!texts.contains("Summary:"))
        #expect(!texts.contains(""))
        #expect(texts.count == 21)
        #expect(lines(plan.pages[1]).isEmpty)
    }

    private func lines(_ page: PagePlan) -> [(from: PlanPoint, to: PlanPoint, width: Double)] {
        page.operations.compactMap { operation in
            if case .line(let from, let to, _, let width) = operation {
                return (from, to, width)
            }
            return nil
        }
    }

    private func summaryContent(routines: [String]) throws -> AgendaContent {
        AgendaContent(
            date: try day(), todoItems: [], schedule: [], meetings: ["Team sync"],
            delegated: [],
            meetingSummaryRoutines: [
                routines.enumerated().map { SummaryRoutine(id: "id-\($0.offset)", name: $0.element) }
            ])
    }

    @Test("A meeting with one routine prints Summary: and its name after it")
    func meetingWithRoutine() throws {
        let plan = try layout().plan(for: summaryContent(routines: ["Board summary"]))
        let page = runs(plan.pages[1])
        let label = try #require(page.first { $0.text == "Summary:" })
        let name = try #require(page.first { $0.text == "Board summary" })
        #expect(label.font.size == 12)
        #expect(name.font == label.font)
        #expect(name.x == label.x + label.width + TemplateGeometry.meetingSummaryGap)
        #expect(name.container.x1 == TemplateGeometry.meetingTitleRight)
        #expect(lines(plan.pages[1]).isEmpty)
    }

    @Test("A meeting with two routines prints their names joined with a comma in one run")
    func meetingWithTwoRoutines() throws {
        let plan = try layout().plan(for: summaryContent(routines: ["Recap", "Board"]))
        let page = runs(plan.pages[1])
        #expect(page.filter { $0.text == "Recap, Board" }.count == 1)
        #expect(page.contains { $0.text == "Summary:" })
    }

    @Test("A routine name of 40 characters is fitted to the box")
    func longRoutineName() throws {
        let name = String(repeating: "W", count: SummaryRoutine.maxNameLength)
        let plan = try layout().plan(for: summaryContent(routines: [name, name]))
        let label = try #require(runs(plan.pages[1]).first { $0.text == "Summary:" })
        let printed = try #require(runs(plan.pages[1]).first { $0.text.hasPrefix("WWW") })
        #expect(printed.text.hasSuffix("…"))
        #expect(printed.x + printed.width <= TemplateGeometry.meetingTitleRight)
        #expect(printed.x == label.x + label.width + TemplateGeometry.meetingSummaryGap)
    }

    @Test("A meeting with no routine prints nothing: no Summary: run and no line")
    func noRoutinePrintsNothing() throws {
        let plan = try layout().plan(for: summaryContent(routines: []))
        let page = runs(plan.pages[1])
        #expect(!page.contains { $0.text == "Summary:" })
        #expect(lines(plan.pages[1]).isEmpty)
        #expect(page.contains { $0.text == "Team sync" })
    }

    @Test("The Summary: label comes after the title runs")
    func summaryAfterTitle() throws {
        let plan = try layout().plan(for: summaryContent(routines: ["x"]))
        let words = runs(plan.pages[1]).map(\.text)
        let title = try #require(words.firstIndex(of: "Team sync"))
        let summary = try #require(words.firstIndex(of: "Summary:"))
        #expect(title < summary)
    }

    @Test("A meeting title longer than its box ends with an ellipsis and fits")
    func longMeetingTitle() throws {
        let title = String(repeating: "m", count: 50)
        let plan = try layout().plan(for: content(meetings: [title]))
        let run = try #require(runs(plan.pages[1]).first { $0.text.hasPrefix("mmm") })
        #expect(run.text.hasSuffix("…"))
        #expect(run.width <= 330.15)
        #expect(run.container.x1 == 566.95)
        #expect(run.bounds.x1 <= run.container.x1)
    }

    @Test("A short meeting title is drawn unchanged")
    func shortMeetingTitle() throws {
        let plan = try layout().plan(for: content(meetings: ["Team sync"]))
        let run = try #require(runs(plan.pages[1]).first { $0.text == "Team sync" })
        #expect(run.font.weight == .extralight)
        #expect(run.font.size == 20)
    }

    @Test("A continued title that is too wide is ellipsized to the title width")
    func longContinuedTitle() throws {
        let title = String(repeating: "x", count: 200)
        let content = try content(meetings: [title])
        let layout = try layout()
        let page = try #require(layout.plan(for: content).pages.dropFirst().first)
        let operations = layout.continuedOperations(of: page, in: content)
        let continued = operations.compactMap { operation -> TextRun? in
            if case .text(let run) = operation, run.text.hasPrefix("cont. ") {
                return run
            }
            return nil
        }
        #expect(continued.count == 1)
        // The title is drawn right after the "Meeting title:" label runs.
        let titleIndex = layout.labelRuns(of: layout.slots(on: "meeting_unit")).count
        try #require(operations.indices.contains(titleIndex))
        guard case .text(let run) = operations[titleIndex] else {
            Issue.record("Expected a text run after the label runs")
            return
        }
        #expect(run.text.hasPrefix("cont. "))
        #expect(run.text.hasSuffix("…"))
        #expect(run.width <= TemplateGeometry.meetingTitleWidth)
    }

    @Test("A page whose key is not in the content keeps its operations")
    func unknownKeyKeepsOperations() throws {
        let content = try content(meetings: ["A"])
        let layout = try layout()
        let page = try #require(layout.plan(for: content).pages.dropFirst().first)
        let stray = PagePlan(key: .meeting("zz"), chrome: page.chrome, operations: page.operations)
        #expect(layout.continuedOperations(of: stray, in: content) == page.operations)
    }

    @Test("A page that is not a meeting page keeps its operations")
    func nonMeetingPageKeepsOperations() throws {
        let content = try content(meetings: ["A"])
        let layout = try layout()
        let page = try #require(layout.plan(for: content).pages.first)
        #expect(layout.continuedOperations(of: page, in: content) == page.operations)
    }

    @Test("The further-notes page draws only its label besides the header")
    func furtherNotesPage() throws {
        let plan = try layout().plan(for: content())
        let texts = runs(plan.pages[2]).map(\.text)
        #expect(texts.contains("Further notes from today"))
        #expect(texts.count == 21)
    }

    @Test("Theme colors reach the runs by role")
    func themeColors() throws {
        let colors = ThemeColors(
            weekend: RGBColor(red: 1, green: 2, blue: 3),
            heading: RGBColor(red: 4, green: 5, blue: 6),
            label: RGBColor(red: 7, green: 8, blue: 9),
            accent: RGBColor(red: 10, green: 11, blue: 12),
            notes: RGBColor(red: 13, green: 14, blue: 15))
        let plan = try layout(theme: Theme(fontPack: .outfit, colors: colors))
            .plan(for: content(meetings: ["A"]))
        let overview = runs(plan.pages[0])
        #expect(overview.first { $0.text == "30 WEDNESDAY" }?.color == colors.heading)
        #expect(overview.first { $0.text == "SAT" }?.color == colors.weekend)
        #expect(overview.first { $0.text == "MON" }?.color == RGBColor.black)
        #expect(runs(plan.pages[1]).first { $0.text == "Meeting title:" }?.color == colors.accent)
        let notesRun = runs(plan.pages[2]).first { $0.text == "Further notes from today" }
        #expect(notesRun?.color == colors.notes)
    }

    @Test("JetBrains Mono runs use 0.9 × the nominal size")
    func scaledFont() throws {
        let manifest = try TemplateManifest.bundled()
        let slot = try #require(manifest.slot("todo.col.task"))
        let plan = try layout(theme: Theme(fontPack: .jetbrainsMono, colors: .default))
            .plan(for: content())
        let run = try #require(runs(plan.pages[0]).first { $0.text == "Task" })
        #expect(run.font.pack == .jetbrainsMono)
        #expect(run.font.size == slot.points * 0.9)
    }
}
