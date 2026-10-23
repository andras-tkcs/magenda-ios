// Every content fixture laid out in every font pack must pass the layout audit.

import Testing

@testable import AppCore

@Suite("Agenda layout fixtures")
struct AgendaLayoutFixtureTests {
    private static let fixtures: [(name: String, content: AgendaContent)] = [
        ("typical", AgendaContentFixtures.typical),
        ("longText", AgendaContentFixtures.longText),
        ("overflow", AgendaContentFixtures.overflow),
        ("empty", AgendaContentFixtures.empty),
    ]

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let content: AgendaContent
        let pack: FontPack
        var testDescription: String { "\(name) in \(pack.displayName)" }
    }

    static let cases: [Case] = fixtures.flatMap { fixture in
        FontPack.allCases.map { Case(name: fixture.name, content: fixture.content, pack: $0) }
    }

    private func plan(_ testCase: Case) throws -> RenderPlan {
        AgendaLayout(
            manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer(),
            theme: Theme(fontPack: testCase.pack)
        ).plan(for: testCase.content)
    }

    @Test("The audit finds nothing", arguments: AgendaLayoutFixtureTests.cases)
    func auditIsClean(_ testCase: Case) throws {
        #expect(LayoutAudit.violations(in: try plan(testCase)).isEmpty)
    }

    @Test("Every page has its own key", arguments: AgendaLayoutFixtureTests.cases)
    func keysAreUnique(_ testCase: Case) throws {
        let plan = try plan(testCase)
        #expect(Set(plan.pages.map(\.key)).count == plan.pages.count)
        #expect(
            !LayoutAudit.violations(in: plan).contains {
                if case .duplicatePageKey = $0.kind { return true }
                return false
            })
    }

    @Test("Every run is one non-empty line", arguments: AgendaLayoutFixtureTests.cases)
    func runsAreSingleLines(_ testCase: Case) throws {
        for page in try plan(testCase).pages {
            for case .text(let run) in page.operations {
                #expect(!run.text.isEmpty)
                #expect(!run.text.contains("\n"))
                #expect(!run.text.contains("\t"))
            }
        }
    }

    @Test("The overflow fixture pushes to-dos off the page", arguments: FontPack.allCases)
    func overflowOmitsTodos(_ pack: FontPack) throws {
        let testCase = Case(name: "overflow", content: AgendaContentFixtures.overflow, pack: pack)
        let omitted = try plan(testCase).omittedTodoItems
        #expect(!omitted.isEmpty)
    }

    @Test("The fixtures hold what the layout rules need")
    func fixtureShapes() {
        #expect(AgendaContentFixtures.longStrings.count == 7)
        #expect(AgendaContentFixtures.longStrings[1].count == 200)
        #expect(AgendaContentFixtures.longText.todoItems.count == 6)
        #expect(AgendaContentFixtures.overflow.todoItems.count == 30)
        #expect(AgendaContentFixtures.overflow.schedule.count == 22)
        #expect(AgendaContentFixtures.overflow.meetings.count == 25)
        #expect(AgendaContentFixtures.overflow.delegated.count == 40)
        #expect(AgendaContentFixtures.empty.meetings.isEmpty)
        #expect(AgendaContentFixtures.typical.date.isoString == "2026-09-30")
        #expect(AgendaContentFixtures.typical.date.weekdayIndex == 2)
    }
}
