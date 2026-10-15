// AppCore's `AgendaLayout` overview page: the to-do grid, the schedule and the static labels,
// measured with `FakeTextMeasurer` (5 per Character at 10 pt, line height equal to the size).

import Testing

@testable import AppCore

@Suite("Agenda layout overview")
struct AgendaLayoutOverviewTests {
    private let manifest: TemplateManifest
    private let layout: AgendaLayout

    init() throws {
        manifest = try TemplateManifest.bundled()
        layout = AgendaLayout(manifest: manifest, measurer: FakeTextMeasurer(), theme: Theme())
    }

    private func plan(
        todo: [TodoItem] = [], schedule: [ScheduleEntry] = []
    ) throws -> RenderPlan {
        let day = try #require(CalendarDay(year: 2026, month: 9, day: 30))
        return layout.plan(
            for: AgendaContent(
                date: day, todoItems: todo, schedule: schedule, meetings: [], delegated: []))
    }

    private func runs(_ page: PagePlan) -> [TextRun] {
        page.operations.compactMap { operation -> TextRun? in
            if case .text(let run) = operation {
                return run
            }
            return nil
        }
    }

    private func taskRuns(_ page: PagePlan) -> [TextRun] {
        runs(page).filter { $0.container.x0 == 97.4 }
    }

    private func dueRuns(_ page: PagePlan) -> [TextRun] {
        runs(page).filter { $0.container.x0 == 222.4 }
    }

    private func ruledLineYs(_ page: PagePlan) -> [Double] {
        page.operations.compactMap { operation -> Double? in
            if case .line(let from, _, _, _) = operation {
                return from.y
            }
            return nil
        }
    }

    private func checkboxes(_ page: PagePlan) -> [PlanRect] {
        page.operations.compactMap { operation -> PlanRect? in
            if case .stroke(let rect, _, _) = operation {
                return rect
            }
            return nil
        }
    }

    private func near(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 1e-6
    }

    private func item(_ text: String, notes: String = "", due: String = "") -> TodoItem {
        TodoItem(text: text, notes: notes, due: due)
    }

    private let longWords = String(repeating: "word ", count: 400)

    @Test("The overview starts by erasing the template's to-do grid")
    func startsWithErase() throws {
        let page = try plan().pages[0]
        #expect(page.operations.first == DrawOperation.fill(TemplateGeometry.todoErase, .white))
    }

    @Test("The band labels are centered in their bands")
    func bandLabels() throws {
        let overview = runs(try plan().pages[0])
        let todo = try #require(overview.first { $0.text == "TO-DO LIST" })
        let schedule = try #require(overview.first { $0.text == "DAILY SCHEDULE" })
        #expect(near(todo.x + todo.width / 2, (56.7 + 293.15) / 2))
        #expect(near(schedule.x + schedule.width / 2, (326.0 + 574.05) / 2))
        #expect(overview.contains { $0.text == "Due" })
    }

    @Test("The next four weeks are filled in")
    func nextFourWeeks() throws {
        let texts = runs(try plan().pages[0]).map(\.text)
        for expected in ["CW 41", "CW 42", "CW 43", "12", "25"] {
            #expect(texts.contains(expected))
        }
    }

    @Test("A to-do item that fits keeps 12 pt and one base row")
    func fittingItem() throws {
        let page = try plan(todo: [item("Call the bank", due: "09/30")]).pages[0]
        let task = taskRuns(page)
        #expect(task.map(\.text) == ["Call the bank"])
        #expect(task[0].font.size == 12)
        #expect(near(task[0].container.height, 28.35))
        #expect(dueRuns(page).map(\.text) == ["09/30"])
        #expect(dueRuns(page)[0].font.size == 12)
    }

    @Test("A longer item shrinks to the largest size that fits one line")
    func shrinkingItem() throws {
        let page = try plan(todo: [item("abcdefghij klmnopqrst")]).pages[0]
        let task = taskRuns(page)
        #expect(task.count == 1)
        #expect(task[0].font.size == 11)
        #expect(near(task[0].container.height, 28.35))
    }

    @Test("An item that cannot fit one line wraps at 9 pt and the row grows with a notes line")
    func wrappingItem() throws {
        let text = Array(repeating: "abcd", count: 12).joined(separator: " ")
        let page = try plan(todo: [item(text, notes: "n"), item("Next")]).pages[0]
        let task = taskRuns(page)
        #expect(task.count == 5)
        #expect(task.prefix(4).allSatisfy { $0.font.size == 9 })
        #expect(task[0].text == "abcd abcd abcd abcd abcd")
        #expect(task[2].text == "abcd abcd:")
        #expect(task[3].text == "n")
        #expect(near(task[0].container.height, 28.35 + 9))
        #expect(ruledLineYs(page).first.map { near($0, 144.95 + 28.35 + 9) } == true)
    }

    @Test("Without notes a long item is capped at three lines inside one base row")
    func cappedItem() throws {
        let page = try plan(todo: [item(longWords)]).pages[0]
        let task = taskRuns(page)
        #expect(task.count == 3)
        #expect(task[2].text.hasSuffix("…"))
        #expect(near(task[0].container.height, 28.35))
    }

    @Test("Notes take one line after the title and its colon")
    func notesLine() throws {
        let page = try plan(todo: [
            item("Send the slides", notes: "Ask Ben for the Q3 numbers first")
        ]).pages[0]
        let task = taskRuns(page)
        #expect(task.count == 2)
        #expect(task[0].text == "Send the slides:")
        #expect(task[1].text.hasSuffix("…"))
        #expect(task[1].width <= 119.0)
    }

    @Test("Very long notes still take one line ending in an ellipsis")
    func longNotes() throws {
        let page = try plan(todo: [item("Title", notes: longWords)]).pages[0]
        let task = taskRuns(page)
        #expect(task.map(\.text).first == "Title:")
        #expect(task.count == 2)
        #expect(task[1].text.hasSuffix("…"))
    }

    @Test("An item without notes has no colon and no notes line")
    func noNotes() throws {
        let page = try plan(todo: [item("Book flights", notes: "  \n ", due: "10/02")]).pages[0]
        #expect(taskRuns(page).map(\.text) == ["Book flights"])
    }

    @Test("Separators sit at every row top except the first, and blank rows fill the grid")
    func gridRows() throws {
        let page = try plan(todo: [item("A"), item("B"), item("C")]).pages[0]
        let ys = ruledLineYs(page)
        #expect(ys.count == 17)
        #expect(ys.allSatisfy { $0 > 144.95 })
        #expect(near(ys[0], 144.95 + 28.35))
        let boxes = checkboxes(page)
        #expect(boxes.count == 18)
        #expect(near(boxes[0].width, 6.48))
        #expect(near((boxes[0].x0 + boxes[0].x1) / 2, 65.8))
        #expect(near((boxes[0].y0 + boxes[0].y1) / 2, 144.95 + 28.35 / 2))
        #expect(boxes.allSatisfy { $0.y1 <= 655.75 })
    }

    @Test("Rules and checkboxes use the template's colors and widths")
    func gridStyle() throws {
        let page = try plan().pages[0]
        let line = page.operations.first { operation in
            if case .line = operation { true } else { false }
        }
        let rule = RGBColor(red: 0x08, green: 0x30, blue: 0x50)
        let from = PlanPoint(x: 56.7, y: 144.95 + 28.35)
        let to = PlanPoint(x: 297.0, y: 144.95 + 28.35)
        #expect(line == DrawOperation.line(from: from, to: to, rule, lineWidth: 0.75))
        let box = page.operations.first { operation in
            if case .stroke = operation { true } else { false }
        }
        guard case .stroke(_, let color, let width)? = box else {
            Issue.record("No checkbox")
            return
        }
        #expect(color == .black)
        #expect(width == 0.75)
    }

    @Test("Items that do not fit go to the omitted list in order")
    func overflow() throws {
        let items = (0..<30).map { item(longWords, notes: longWords, due: String($0)) }
        let result = try plan(todo: items)
        let page = result.pages[0]
        #expect(checkboxes(page).count == 13)
        #expect(result.omittedTodoItems == Array(items[13...]))
        #expect(result.omittedTodoItems.map(\.due).first == "13")
        #expect(taskRuns(page).allSatisfy { $0.container.y1 <= 655.75 })
        #expect(checkboxes(page).allSatisfy { $0.y1 <= 655.75 })
    }

    @Test("Everything fits when there are exactly 18 base rows of items")
    func fullGrid() throws {
        let items = (0..<18).map { item("Task \($0)") }
        let result = try plan(todo: items)
        #expect(result.omittedTodoItems.isEmpty)
        #expect(checkboxes(result.pages[0]).count == 18)
    }

    @Test("A schedule entry is drawn in its slot's row")
    func scheduleEntry() throws {
        let page = try plan(schedule: [ScheduleEntry(slot: 2, text: "Team sync", meetingIndex: 0)])
            .pages[0]
        let slot = try #require(manifest.slot("schedule.slot.2"))
        let run = try #require(runs(page).first { $0.text == "Team sync" })
        #expect(near(run.x, 366.9 - 1.5))
        #expect(near(run.container.x1, 568.7))
        #expect(run.baseline > slot.rect.y0 && run.baseline < slot.rect.y1 + 4)
        #expect(run.font.size == 12)
    }

    @Test("A schedule entry longer than its box ends with an ellipsis and fits")
    func longScheduleEntry() throws {
        let text = String(repeating: "x", count: 40)
        let page = try plan(schedule: [ScheduleEntry(slot: 0, text: text, meetingIndex: nil)])
            .pages[0]
        let run = try #require(runs(page).first { $0.text.hasPrefix("xxx") })
        #expect(run.text.hasSuffix("…"))
        #expect(run.width <= 201.8)
        #expect(run.bounds.x1 <= run.container.x1)
    }

    @Test("Only the first entry of a slot is drawn, and slots outside the grid are skipped")
    func scheduleSlots() throws {
        let page = try plan(schedule: [
            ScheduleEntry(slot: 3, text: "first", meetingIndex: nil),
            ScheduleEntry(slot: 3, text: "second", meetingIndex: nil),
            ScheduleEntry(slot: 99, text: "ghost", meetingIndex: nil),
        ]).pages[0]
        let texts = runs(page).map(\.text)
        #expect(texts.contains("first"))
        #expect(!texts.contains("second"))
        #expect(!texts.contains("ghost"))
    }
}
