// AppCore's `AgendaLayout` navigation links, measured with `FakeTextMeasurer`.

import Testing

@testable import AppCore

@Suite("Agenda layout links")
struct AgendaLayoutLinksTests {
    private let layout: AgendaLayout

    init() throws {
        layout = AgendaLayout(
            manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer(), theme: Theme())
    }

    private func plan(
        delegated: Bool = false, schedule: [ScheduleEntry] = [], meetings: [String] = ["A", "B"]
    ) throws -> RenderPlan {
        let day = try #require(CalendarDay(year: 2026, month: 9, day: 30))
        let items =
            delegated
            ? [
                DelegatedItem(
                    text: "Task", owner: "Owner", cadence: .daily, marked: false, status: [])
            ] : []
        return layout.plan(
            for: AgendaContent(
                date: day, todoItems: [], schedule: schedule, meetings: meetings, delegated: items))
    }

    private func links(_ page: PagePlan) -> [(rect: PlanRect, target: Int)] {
        page.operations.compactMap { operation -> (rect: PlanRect, target: Int)? in
            if case .link(let rect, let target) = operation {
                return (rect, target)
            }
            return nil
        }
    }

    private func run(_ text: String, on page: PagePlan) -> TextRun? {
        page.operations.compactMap { operation -> TextRun? in
            if case .text(let run) = operation, run.text == text {
                return run
            }
            return nil
        }.first
    }

    @Test("Every page but the first links back to the overview")
    func backLinks() throws {
        let plan = try plan(delegated: true)
        #expect(links(plan.pages[0]).filter { $0.target == 0 }.isEmpty)
        for page in plan.pages.dropFirst() {
            let back = links(page).filter { $0.target == 0 }
            #expect(back.count == 1)
            #expect(back.first?.rect == run("<< Overview", on: page)?.bounds)
        }
    }

    @Test("Every page but the last links on to the notes page")
    func notesLinks() throws {
        let plan = try plan(delegated: true)
        let last = plan.pages.count - 1
        #expect(links(plan.pages[last]).filter { $0.target == last }.isEmpty)
        for page in plan.pages.dropLast() {
            let forward = links(page).filter { $0.target == last }
            #expect(forward.count == 1)
            #expect(forward.first?.rect == run("Notes >>", on: page)?.bounds)
        }
    }

    @Test("Schedule entries link to their meeting page, after the delegated pages")
    func scheduleLinks() throws {
        let schedule = [
            ScheduleEntry(slot: 2, text: "Team", meetingIndex: 0),
            ScheduleEntry(slot: 5, text: "Solo", meetingIndex: nil),
            ScheduleEntry(slot: 7, text: "Second", meetingIndex: 1),
        ]
        for delegated in [false, true] {
            let plan = try plan(delegated: delegated, schedule: schedule)
            let last = plan.pages.count - 1
            let offset = delegated ? 2 : 1
            let found = links(plan.pages[0]).filter { $0.target != last }
            #expect(found.map(\.target) == [offset, offset + 1])
            #expect(found.first?.rect == run("Team", on: plan.pages[0])?.bounds)
            #expect(found.last?.rect == run("Second", on: plan.pages[0])?.bounds)
        }
    }

    @Test("A repeated schedule slot links only its first entry")
    func repeatedSlot() throws {
        let schedule = [
            ScheduleEntry(slot: 2, text: "First", meetingIndex: 0),
            ScheduleEntry(slot: 2, text: "Again", meetingIndex: 1),
        ]
        let plan = try plan(schedule: schedule)
        #expect(links(plan.pages[0]).filter { $0.target == 1 }.count == 1)
        #expect(links(plan.pages[0]).filter { $0.target == 2 }.isEmpty)
    }

    @Test("Links come last on each page, after the header")
    func linksAreLast() throws {
        let plan = try plan()
        for page in plan.pages {
            let operations = page.operations
            let firstLink = operations.firstIndex { if case .link = $0 { true } else { false } }
            #expect(firstLink != nil)
            #expect(operations[(firstLink ?? 0)...].allSatisfy { if case .link = $0 { true } else { false } })
        }
    }
}
