// AppCore's `AgendaLayout` page list, header, meeting pages and further-notes page, measured with
// `FakeTextMeasurer` against the bundled template manifest.

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

    @Test("A blank meeting page draws only its label besides the header")
    func blankMeetingPage() throws {
        let plan = try layout().plan(for: content())
        let texts = runs(plan.pages[1]).map(\.text)
        #expect(texts.contains("Meeting title:"))
        #expect(!texts.contains(""))
        #expect(texts.count == 21)
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
        #expect(runs(plan.pages[2]).first { $0.text == "Further notes from today" }?.color
            == colors.notes)
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
