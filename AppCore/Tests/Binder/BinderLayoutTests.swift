// AppCore's `BinderLayout`: composing the content's, retained and added pages, remapping links,
// titling an added copy of a meeting page as continued, and rebasing a day onto new content,
// measured with `FakeTextMeasurer`.

import Testing

@testable import AppCore

@Suite("Binder layout")
struct BinderLayoutTests {
    private let layout: BinderLayout
    private let day: CalendarDay

    init() throws {
        layout = BinderLayout(
            manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer())
        day = try #require(CalendarDay(year: 2026, month: 9, day: 30))
    }

    private func content(
        _ ids: [String] = ["a", "b"], delegated: Bool = false
    ) -> AgendaContent {
        AgendaContent(
            date: day, todoItems: [],
            schedule: ids.enumerated().map {
                ScheduleEntry(slot: 2 + 3 * $0.offset, text: $0.element, meetingIndex: $0.offset)
            },
            meetings: ids.map { $0.uppercased() }, meetingIDs: ids,
            delegated: delegated
                ? [
                    DelegatedItem(
                        text: "Task", owner: "Owner", cadence: .daily, marked: false, status: [])
                ] : [])
    }

    private func binder(
        _ content: AgendaContent? = nil, extras: [ExtraPage] = [],
        retained: [RetainedPage] = []
    ) -> BinderDay {
        BinderDay(
            content: content ?? self.content(), theme: Theme(), extras: extras, retained: retained)
    }

    private func keys(_ plan: RenderPlan) -> [PageKey] {
        plan.pages.map(\.key)
    }

    private func targets(_ page: PagePlan) -> [Int] {
        page.operations.compactMap { operation -> Int? in
            if case .link(_, let target) = operation {
                return target
            }
            return nil
        }
    }

    private func texts(_ page: PagePlan) -> [String] {
        page.operations.compactMap { operation -> String? in
            if case .text(let run) = operation {
                return run.text
            }
            return nil
        }
    }

    @Test("A day without added or retained pages is the agenda layout's plan")
    func plainDay() throws {
        let agenda = AgendaLayout(
            manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer(), theme: Theme())
        let expected = agenda.plan(for: content())
        let plan = layout.plan(for: binder())
        #expect(keys(plan) == keys(expected))
        #expect(plan.pages.map(\.chrome) == expected.pages.map(\.chrome))
        #expect(plan.pages.map(\.operations) == expected.pages.map(\.operations))
        #expect(plan == expected)
    }

    @Test("An added page sits right after its page, copies it and links to the composed pages")
    func addedPage() {
        var day = binder()
        day.addPage(after: .meeting("a"), id: "x")
        let plan = layout.plan(for: day)
        #expect(keys(plan) == [.overview, .meeting("a"), .extra("x"), .meeting("b"), .notes])
        #expect(plan.pages[2].chrome == plan.pages[1].chrome)
        #expect(texts(plan.pages[2]).contains("cont. A"))
        #expect(!texts(plan.pages[2]).contains("A"))
        #expect(texts(plan.pages[1]).contains("A"))
        #expect(targets(plan.pages[2]) == [0, 4])
    }

    @Test("Every added copy of a meeting page is titled as continued")
    func everyCopyIsContinued() {
        var day = binder()
        day.addPage(after: .meeting("a"), id: "x")
        day.addPage(after: .extra("x"), id: "y")
        let plan = layout.plan(for: day)
        #expect(keys(plan).prefix(4) == [.overview, .meeting("a"), .extra("x"), .extra("y")])
        #expect(texts(plan.pages[2]).contains("cont. A"))
        #expect(texts(plan.pages[3]).contains("cont. A"))
    }

    @Test("An added copy of a meeting page carries the same summary operations")
    func copyKeepsSummary() throws {
        var day = binder(
            AgendaContent(
                date: self.day, todoItems: [], schedule: [], meetings: ["A"], meetingIDs: ["a"],
                delegated: [], meetingSummarySkills: ["board-summary"]))
        day.addPage(after: .meeting("a"), id: "x")
        let plan = layout.plan(for: day)
        let source = try #require(plan.pages.first { $0.key == .meeting("a") })
        let copy = try #require(plan.pages.first { $0.key == .extra("x") })
        #expect(texts(copy).contains("Summary:"))
        #expect(texts(copy).contains("board-summary"))
        #expect(texts(copy).filter { $0 == "board-summary" } == ["board-summary"])
        #expect(texts(source).contains("cont. A") == false)
        #expect(texts(copy).contains("cont. A"))
    }

    @Test("An added copy of the blank meeting page is titled cont.")
    func blankMeetingCopy() throws {
        var day = binder(content([]))
        day.addPage(after: .meeting(""), id: "x")
        let plan = layout.plan(for: day)
        let page = try #require(plan.pages.first { $0.key == .extra("x") })
        let words = texts(page)
        let label = try #require(words.firstIndex(of: "Meeting title:"))
        #expect(words.contains("cont."))
        #expect(words.firstIndex(of: "cont.") == label + 1)
    }

    @Test("An added copy of a retained meeting page is titled from its own content")
    func retainedMeetingCopy() throws {
        var day = binder(
            retained: [RetainedPage(key: .meeting("gone"), content: content(["gone"]))])
        day.addPage(after: .meeting("gone"), id: "x")
        let plan = layout.plan(for: day)
        let page = try #require(plan.pages.first { $0.key == .extra("x") })
        #expect(texts(page).contains("cont. GONE"))
    }

    @Test("Added copies of other pages keep their text")
    func otherCopiesKeepText() throws {
        var day = binder()
        day.addPage(after: .overview, id: "o")
        day.addPage(after: .notes, id: "n")
        let plan = layout.plan(for: day)
        for (extra, source) in [(PageKey.extra("o"), PageKey.overview), (.extra("n"), .notes)] {
            let copy = try #require(plan.pages.first { $0.key == extra })
            let original = try #require(plan.pages.first { $0.key == source })
            #expect(texts(copy) == texts(original))
        }
    }

    @Test("Schedule links point at the right meeting after pages were added before it")
    func scheduleLinks() {
        var day = binder()
        day.addPage(after: .meeting("a"), id: "x")
        day.addPage(after: .overview, id: "o")
        let plan = layout.plan(for: day)
        #expect(
            keys(plan) == [
                .overview, .extra("o"), .meeting("a"), .extra("x"), .meeting("b"), .notes,
            ])
        #expect(Set(targets(plan.pages[0])) == [5, 2, 4])
    }

    @Test("A retained meeting page follows the last meeting page")
    func retainedMeeting() {
        let old = content(["old"])
        let plan = layout.plan(
            for: binder(retained: [RetainedPage(key: .meeting("old"), content: old)]))
        #expect(keys(plan) == [.overview, .meeting("a"), .meeting("b"), .meeting("old"), .notes])
        #expect(texts(plan.pages[3]).contains("OLD"))
        #expect(targets(plan.pages[3]) == [0, 4])
    }

    @Test("A retained delegated page lands before the notes page when nothing is delegated")
    func retainedDelegated() {
        let old = content(delegated: true)
        let plan = layout.plan(
            for: binder(retained: [RetainedPage(key: .delegated(0), content: old)]))
        #expect(keys(plan) == [.overview, .meeting("a"), .meeting("b"), .delegated(0), .notes])
        #expect(plan.pages[3].chrome == .delegated)
    }

    @Test("Retained pages that are shown already or missing from their content are skipped")
    func retainedSkipped() {
        let old = content(["old", "older"])
        let plan = layout.plan(
            for: binder(retained: [
                RetainedPage(key: .meeting("a"), content: old),
                RetainedPage(key: .meeting("missing"), content: old),
                RetainedPage(key: .meeting("old"), content: old),
                RetainedPage(key: .meeting("older"), content: old),
            ]))
        #expect(
            keys(plan) == [
                .overview, .meeting("a"), .meeting("b"), .meeting("old"), .meeting("older"),
                .notes,
            ])
        let base = layout.plan(for: binder())
        #expect(texts(plan.pages[1]) == texts(base.pages[1]))
        #expect(targets(plan.pages[1]) == [0, 5])
    }

    @Test("An added page whose page is gone follows its source's run; one without source goes")
    func danglingExtras() {
        let extras = [
            ExtraPage(id: "y", after: .meeting("a"), source: .meeting("a")),
            ExtraPage(id: "x", after: .meeting("gone"), source: .meeting("a")),
            ExtraPage(id: "x2", after: .extra("x"), source: .meeting("a")),
            ExtraPage(id: "z", after: .meeting("gone"), source: .meeting("nowhere")),
            ExtraPage(id: "w", after: .extra("z"), source: .meeting("b")),
        ]
        let plan = layout.plan(for: binder(extras: extras))
        #expect(
            keys(plan) == [
                .overview, .meeting("a"), .extra("y"), .extra("x"), .extra("x2"), .meeting("b"),
                .extra("w"), .notes,
            ])
    }

    @Test("Plans with two added pages and a retained page pass the layout audit")
    func audit() throws {
        let fixtures = [
            AgendaContentFixtures.typical, AgendaContentFixtures.longText,
            AgendaContentFixtures.overflow, AgendaContentFixtures.empty,
        ]
        for fixture in fixtures {
            let agenda = AgendaLayout(
                manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer(),
                theme: Theme())
            let base = keys(agenda.plan(for: fixture))
            var bound = BinderDay(
                content: fixture, theme: Theme(),
                retained: [RetainedPage(key: .meeting("gone"), content: content(["gone"]))])
            bound.addPage(after: base[1], id: "e1")
            bound.addPage(after: .notes, id: "e2")
            let meeting = try #require(
                base.first { if case .meeting = $0 { true } else { false } })
            bound.addPage(after: meeting, id: "e3")
            let plan = layout.plan(for: bound)
            #expect(plan.pages.count == base.count + 4)
            #expect(LayoutAudit.violations(in: plan) == [])
        }
    }

    @Test("Rebasing keeps a dropped meeting with ink, with the old content, and takes the new ones")
    func rebasedKeepsInked() {
        let theme = Theme(fontPack: .roboto)
        let new = content(["b"])
        let rebased = layout.rebased(
            binder(), onto: new, theme: theme, inkedKeys: [.meeting("a")])
        #expect(rebased.retained == [RetainedPage(key: .meeting("a"), content: content())])
        #expect(rebased.content == new)
        #expect(rebased.theme == theme)
        #expect(rebased.extras.isEmpty)
    }

    @Test("Rebasing drops a dropped meeting without ink")
    func rebasedDropsBlank() {
        let rebased = layout.rebased(binder(), onto: content(["b"]), theme: Theme(), inkedKeys: [])
        #expect(rebased.retained.isEmpty)
    }

    @Test("Rebasing keeps a dropped meeting whose added page has ink, and the added page")
    func rebasedKeepsForExtraInk() {
        var day = binder()
        day.addPage(after: .meeting("a"), id: "x")
        let rebased = layout.rebased(
            day, onto: content(["b"]), theme: Theme(), inkedKeys: [.extra("x")])
        #expect(rebased.retained.map(\.key) == [.meeting("a")])
        #expect(rebased.extras == day.extras)
    }

    @Test("Rebasing keeps a retained page's original content")
    func rebasedKeepsRetainedContent() {
        let first = layout.rebased(
            binder(), onto: content(["b"]), theme: Theme(), inkedKeys: [.meeting("a")])
        let second = layout.rebased(
            first, onto: content(["c"]), theme: Theme(), inkedKeys: [.meeting("a")])
        #expect(second.retained == [RetainedPage(key: .meeting("a"), content: content())])
    }

    @Test("Rebasing keeps added pages whose source survives and drops the others")
    func rebasedExtras() {
        var day = binder()
        day.addPage(after: .meeting("a"), id: "x")
        day.addPage(after: .meeting("b"), id: "y")
        let rebased = layout.rebased(day, onto: content(["b"]), theme: Theme(), inkedKeys: [])
        #expect(rebased.extras == [ExtraPage(id: "y", after: .meeting("b"), source: .meeting("b"))])
    }
}
