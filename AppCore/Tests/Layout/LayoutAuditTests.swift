// AppCore's `LayoutAudit`, run on hand-built plans.

import Testing

@testable import AppCore

@Suite("Layout audit")
struct LayoutAuditTests {
    private let font = FontSpec.nominal(.outfit, .regular, 10)
    private let container = PlanRect(x0: 10, y0: 10, x1: 110, y1: 30)

    private func run(
        _ text: String, x: Double = 12, baseline: Double = 22, width: Double = 40,
        container: PlanRect? = nil
    ) -> DrawOperation {
        .text(
            TextRun(
                text: text, font: font, color: .black, x: x, baseline: baseline, width: width,
                ascent: 8, descent: 2, container: container ?? self.container))
    }

    private func plan(_ pages: [[DrawOperation]]) -> RenderPlan {
        RenderPlan(
            pageWidth: 200, pageHeight: 300,
            pages: pages.enumerated().map { index, operations in
                PagePlan(key: .extra("\(index)"), chrome: .overview, operations: operations)
            },
            omittedTodoItems: [])
    }

    @Test("A sound plan has no violations")
    func clean() {
        let operations: [DrawOperation] = [
            .fill(container, .white),
            run("One"),
            run("Two", baseline: 220, container: PlanRect(x0: 10, y0: 200, x1: 110, y1: 240)),
            .link(container, targetPage: 1),
        ]
        #expect(LayoutAudit.violations(in: plan([operations, []])).isEmpty)
    }

    @Test("A repeated page key is flagged on the repeat")
    func duplicateKey() {
        let page = PagePlan(key: .notes, chrome: .furtherNotes, operations: [])
        let repeated = RenderPlan(
            pageWidth: 200, pageHeight: 300, pages: [page, page, page], omittedTodoItems: [])
        #expect(
            LayoutAudit.violations(in: repeated) == [
                LayoutViolation(page: 1, kind: .duplicatePageKey(.notes)),
                LayoutViolation(page: 2, kind: .duplicatePageKey(.notes)),
            ])
    }

    @Test("A plan with no pages is flagged")
    func noPages() {
        #expect(
            LayoutAudit.violations(in: plan([]))
                == [LayoutViolation(page: 0, kind: .noPages)])
    }

    @Test("A run sticking out of its container is flagged")
    func outsideContainer() {
        let found = LayoutAudit.violations(in: plan([[], [run("Wide", width: 150)]]))
        #expect(found == [LayoutViolation(page: 1, kind: .outsideContainer(text: "Wide"))])
    }

    @Test("A run inside its container's tolerance is not flagged")
    func withinTolerance() {
        #expect(LayoutAudit.violations(in: plan([[run("Edge", x: 9.6)]])).isEmpty)
    }

    @Test("A container reaching beyond the page is flagged")
    func outsidePage() {
        let big = PlanRect(x0: 10, y0: 10, x1: 250, y1: 30)
        let found = LayoutAudit.violations(in: plan([[run("Big", container: big)]]))
        #expect(found == [LayoutViolation(page: 0, kind: .outsidePage(text: "Big"))])
    }

    @Test("Two runs covering the same area are flagged once")
    func overlap() {
        let found = LayoutAudit.violations(
            in: plan([[run("A"), run("B", x: 30), run("C", baseline: 28.5, container: container)]]))
        #expect(
            found == [
                LayoutViolation(page: 0, kind: .overlap("A", "B")),
                LayoutViolation(page: 0, kind: .overlap("A", "C")),
                LayoutViolation(page: 0, kind: .overlap("B", "C")),
            ])
    }

    @Test("Runs that only touch are not an overlap")
    func touching() {
        #expect(LayoutAudit.violations(in: plan([[run("A"), run("B", x: 52)]])).isEmpty)
    }

    @Test("A link to a page that does not exist is flagged")
    func badLinks() {
        let found = LayoutAudit.violations(
            in: plan([
                [.link(container, targetPage: 1), .link(container, targetPage: 2)],
                [.link(container, targetPage: -1)],
            ]))
        #expect(
            found == [
                LayoutViolation(page: 0, kind: .badLinkTarget(2)),
                LayoutViolation(page: 1, kind: .badLinkTarget(-1)),
            ])
    }
}
