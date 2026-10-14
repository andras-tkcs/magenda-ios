// AppCore's `AgendaLayout` delegated-task pages: fitting, row heights, pagination, marks and
// status bullets, measured with `FakeTextMeasurer` (half a font size per Character).

import Testing

@testable import AppCore

@Suite("Agenda layout delegated pages")
struct AgendaLayoutDelegatedTests {
    private let layout: AgendaLayout
    private let left: Double = 56.796
    private let numberRight: Double = 56.796 + 30.75
    private let taskX: Double = 56.796 + 30.75 + 5.4
    private let ownerX: Double = 56.796 + 30.75 + 173.2 + 5.4
    private let statusX: Double = 56.796 + 30.75 + 173.2 + 84.45 + 5.4

    init() throws {
        layout = AgendaLayout(
            manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer(), theme: Theme())
    }

    private func plan(_ delegated: [DelegatedItem]) throws -> RenderPlan {
        let day = try #require(CalendarDay(year: 2026, month: 9, day: 30))
        return layout.plan(
            for: AgendaContent(
                date: day, todoItems: [], schedule: [], meetings: [], delegated: delegated))
    }

    private func item(
        _ text: String = "Task", owner: String = "Owner", cadence: Cadence = .daily,
        marked: Bool = false, status: [String] = ["Status"]
    ) -> DelegatedItem {
        DelegatedItem(
            text: text, owner: owner, cadence: cadence, marked: marked, status: status)
    }

    private func runs(_ page: PagePlan) -> [TextRun] {
        page.operations.compactMap { operation -> TextRun? in
            if case .text(let run) = operation {
                return run
            }
            return nil
        }
    }

    private func delegatedPages(_ plan: RenderPlan) -> [PagePlan] {
        plan.pages.filter { $0.chrome == .delegated }
    }

    private func column(_ page: PagePlan, x0: Double) -> [TextRun] {
        runs(page).filter { abs($0.container.x0 - x0) < 0.001 && $0.container.y0 >= 129.5 }
            .filter { $0.container.y0 < 628.2 }
    }

    private func borders(_ page: PagePlan) -> [(y: Double, width: Double)] {
        page.operations.compactMap { operation -> (y: Double, width: Double)? in
            if case .line(let from, _, let color, let width) = operation, color == .black {
                return (from.y, width)
            }
            return nil
        }
    }

    @Test("No delegated items means no delegated page")
    func noItems() throws {
        let plan = try plan([])
        #expect(plan.pages.map(\.chrome) == [.overview, .meeting, .furtherNotes])
    }

    @Test("A delegated page sits between the overview and the meetings and carries its labels")
    func pageLabels() throws {
        let plan = try plan([item()])
        #expect(plan.pages.map(\.chrome) == [.overview, .delegated, .meeting, .furtherNotes])
        let page = plan.pages[1]
        #expect(page.operations.first == .fill(TemplateGeometry.delegatedErase, .white))
        let texts = runs(page).map(\.text)
        for label in ["Task & cadence", "Owner", "Status", "Notes and updates"] {
            #expect(texts.contains(label))
        }
    }

    @Test("Items are drawn in page order and numbered from 1")
    func order() throws {
        let items = [
            item(owner: "monthly", cadence: .monthly),
            item(owner: "weekly", cadence: .weekly),
            item(owner: "marked", cadence: .weekly, marked: true),
            item(owner: "daily", cadence: .daily),
        ]
        let page = try delegatedPages(plan(items))[0]
        #expect(column(page, x0: ownerX).map(\.text) == ["marked", "daily", "weekly", "monthly"])
        #expect(column(page, x0: left).map(\.text) == ["1", "2", "3", "4"])
    }

    @Test("A marked row is filled before its border, and the first border is the thick one")
    func markAndBorders() throws {
        let page = try delegatedPages(plan([item(marked: true), item(cadence: .weekly)]))[0]
        let fills = page.operations.enumerated().filter {
            if case .fill(_, let color) = $0.element { return color == TemplateGeometry.markedFill }
            return false
        }
        #expect(fills.count == 1)
        guard case .line(_, _, _, let width) = page.operations[fills[0].offset + 1] else {
            Issue.record("The border does not follow the fill")
            return
        }
        #expect(width == 3.0)
        #expect(borders(page).map(\.width) == [3.0, 0.5])
    }

    @Test("The cadence label is the first line of the task cell")
    func cadenceLabel() throws {
        let page = try delegatedPages(plan([item("Do it", cadence: .monthly)]))[0]
        #expect(column(page, x0: taskX).map(\.text) == ["Monthly", "Do it"])
    }

    @Test("A row grows by one line height for each line beyond two")
    func rowHeight() throws {
        let long = (1...5).map { "Line \($0)" }
        let page = try delegatedPages(
            plan([item(status: long), item(status: ["Short"]), item(status: ["Short"])]))[0]
        let tops = borders(page).map(\.y)
        #expect(abs(tops[1] - tops[0] - (49.8 + 3 * 11)) < 0.001)
        #expect(abs(tops[2] - tops[1] - 49.8) < 0.001)
    }

    @Test("A status of several strings is bulleted, with continuation lines indented")
    func bulletsAndIndents() throws {
        let page = try delegatedPages(
            plan([item(status: [String(repeating: "word ", count: 30), "Second"])]))[0]
        let lines = column(page, x0: statusX)
        #expect(lines.first?.text.hasPrefix("• ") == true)
        #expect(lines.last?.text == "• Second")
        #expect(abs(lines[1].x - lines[0].x - 11.0) < 0.001)
        #expect(lines.last?.x == lines.first?.x)
    }

    @Test("A status of more than ten lines ends with an ellipsis")
    func statusBudget() throws {
        let page = try delegatedPages(
            plan([item(status: [String(repeating: "word ", count: 400)])]))[0]
        let lines = column(page, x0: statusX)
        #expect(lines.count == 10)
        #expect(lines.last?.text.hasSuffix("…") == true)
    }

    @Test("Strings left over when the budget runs out are folded into the last line")
    func statusLeftovers() throws {
        let page = try delegatedPages(
            plan([item(status: [String(repeating: "word ", count: 400), "Second", "Third"])]))[0]
        let lines = column(page, x0: statusX)
        #expect(lines.count == 10)
        #expect(lines.last?.text.hasSuffix("…") == true)
        #expect(lines.last?.text.hasPrefix("• ") == false)
    }

    @Test("Strings left over after a budget that ends on a bullet keep the bullet")
    func statusLeftoversOnBullet() throws {
        let nine = String(repeating: "word ", count: 63)
        let page = try delegatedPages(plan([item(status: [nine, "Second", "Third"])]))[0]
        let lines = column(page, x0: statusX)
        #expect(lines.count == 10)
        #expect(lines.last?.text.hasPrefix("• Second") == true)
        #expect(lines.last?.text.hasSuffix("…") == true)
    }

    @Test("Forty items with long statuses paginate within the page and appear once each")
    func pagination() throws {
        let items = (0..<40).map {
            item(
                "Task \($0)", owner: "Owner \($0)", cadence: Cadence.allCases[$0 % 3],
                marked: $0 % 4 == 0,
                status: Array(repeating: String(repeating: "word ", count: 40), count: 3))
        }
        let pages = try delegatedPages(plan(items))
        #expect(pages.count > 1)
        let owners = pages.flatMap { column($0, x0: ownerX).map(\.text) }
        #expect(owners.count == 40)
        #expect(Set(owners).count == 40)
        let numbers = pages.flatMap { column($0, x0: left).map(\.text) }
        #expect(numbers == (1...40).map(String.init))
        for page in pages {
            for run in column(page, x0: statusX) + column(page, x0: taskX) {
                #expect(run.container.y1 <= 628.2 + 0.001)
            }
            let rows = column(page, x0: left).count
            let isLast = page == pages[pages.count - 1]
            #expect(borders(page).count == rows + (isLast ? 0 : 1))
        }
    }
}
