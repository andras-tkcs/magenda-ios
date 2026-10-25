// AppCore's plan geometry: rectangle decoding, intersection, containment and text bounds.

import AppCore
import Foundation
import Testing

@Suite("Render plan geometry")
struct RenderPlanTests {
    private let rect = PlanRect(x0: 10, y0: 20, x1: 30, y1: 60)

    @Test("Width and height")
    func size() {
        #expect(rect.width == 20)
        #expect(rect.height == 40)
    }

    @Test("Rectangles intersect only when they overlap deeper than the tolerance on both axes")
    func intersects() {
        let deep = PlanRect(x0: 25, y0: 50, x1: 40, y1: 70)  // overlaps 5 × 10
        #expect(rect.intersects(deep, tolerance: 4.9))
        #expect(!rect.intersects(deep, tolerance: 5))
        let shallowY = PlanRect(x0: 25, y0: 59, x1: 40, y1: 70)  // overlaps 5 × 1
        #expect(!rect.intersects(shallowY, tolerance: 1))
        #expect(rect.intersects(shallowY, tolerance: 0.5))
        let apart = PlanRect(x0: 100, y0: 100, x1: 110, y1: 110)
        #expect(!rect.intersects(apart, tolerance: 0))
    }

    @Test("A rectangle contains another up to the tolerance on every side")
    func contains() {
        #expect(rect.contains(PlanRect(x0: 12, y0: 22, x1: 28, y1: 58), tolerance: 0))
        #expect(rect.contains(rect, tolerance: 0))
        #expect(rect.contains(PlanRect(x0: 9, y0: 20, x1: 30, y1: 60), tolerance: 1))
        #expect(!rect.contains(PlanRect(x0: 9, y0: 20, x1: 30, y1: 60), tolerance: 0.5))
        #expect(rect.contains(PlanRect(x0: 10, y0: 19, x1: 30, y1: 60), tolerance: 1))
        #expect(!rect.contains(PlanRect(x0: 10, y0: 19, x1: 30, y1: 60), tolerance: 0.5))
        #expect(rect.contains(PlanRect(x0: 10, y0: 20, x1: 31, y1: 60), tolerance: 1))
        #expect(!rect.contains(PlanRect(x0: 10, y0: 20, x1: 31, y1: 60), tolerance: 0.5))
        #expect(rect.contains(PlanRect(x0: 10, y0: 20, x1: 30, y1: 61), tolerance: 1))
        #expect(!rect.contains(PlanRect(x0: 10, y0: 20, x1: 30, y1: 61), tolerance: 0.5))
    }

    @Test("A run's bounds extend from the ascent above to the descent below its baseline")
    func bounds() {
        let run = TextRun(
            text: "ab", font: FontSpec(pack: .outfit, weight: .regular, size: 10),
            color: .black, x: 5, baseline: 50, width: 10, ascent: 8, descent: 2,
            container: rect)
        #expect(run.bounds == PlanRect(x0: 5, y0: 42, x1: 15, y1: 52))
    }

    @Test("Rectangles and points decode from arrays and reject other lengths")
    func decoding() throws {
        let decoder = JSONDecoder()
        let decodedRect = try decoder.decode(PlanRect.self, from: Data("[1,2,3,4.5]".utf8))
        #expect(decodedRect == PlanRect(x0: 1, y0: 2, x1: 3, y1: 4.5))
        #expect(throws: DecodingError.self) {
            try decoder.decode(PlanRect.self, from: Data("[1,2,3]".utf8))
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(PlanRect.self, from: Data("[1,2,3,4,5]".utf8))
        }
        let point = try decoder.decode(PlanPoint.self, from: Data("[1.5,2]".utf8))
        #expect(point == PlanPoint(x: 1.5, y: 2))
        #expect(throws: DecodingError.self) {
            try decoder.decode(PlanPoint.self, from: Data("[1]".utf8))
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(PlanPoint.self, from: Data("[1,2,3]".utf8))
        }
    }

    @Test("Plans hold their pages and omitted items")
    func plan() {
        var page = PagePlan(key: .meeting("a"), chrome: .meeting, operations: [.fill(rect, .white)])
        page.operations.append(.link(rect, targetPage: 1))
        let omitted = TodoItem(text: "t", notes: "", due: "")
        let plan = RenderPlan(
            pageWidth: 100, pageHeight: 200, pages: [page], omittedTodoItems: [omitted])
        #expect(plan.pages[0].chrome.rawValue == 2)
        #expect(plan.pages[0].operations.count == 2)
        #expect(plan.omittedTodoItems == [omitted])
    }

    private func linkPlan() -> RenderPlan {
        let linked = PagePlan(
            key: .overview, chrome: .overview,
            operations: [
                .fill(rect, .white),
                .link(rect, targetPage: 1),
                .link(PlanRect(x0: 20, y0: 30, x1: 50, y1: 70), targetPage: 2),
            ])
        let plain = PagePlan(key: .notes, chrome: .furtherNotes, operations: [.fill(rect, .white)])
        return RenderPlan(
            pageWidth: 100, pageHeight: 200, pages: [linked, plain], omittedTodoItems: [])
    }

    @Test("A point inside a link finds its target")
    func linkInside() {
        #expect(linkPlan().linkTarget(at: PlanPoint(x: 12, y: 25), onPage: 0) == 1)
    }

    @Test("A point on a link's edge or corner counts as inside")
    func linkOnEdge() {
        #expect(linkPlan().linkTarget(at: PlanPoint(x: 10, y: 20), onPage: 0) == 1)
        #expect(linkPlan().linkTarget(at: PlanPoint(x: 30, y: 25), onPage: 0) == 1)
    }

    @Test("A point outside every link finds nothing")
    func linkOutside() {
        #expect(linkPlan().linkTarget(at: PlanPoint(x: 9.9, y: 25), onPage: 0) == nil)
        #expect(linkPlan().linkTarget(at: PlanPoint(x: 25, y: 19.9), onPage: 0) == nil)
        #expect(linkPlan().linkTarget(at: PlanPoint(x: 51, y: 25), onPage: 0) == nil)
        #expect(linkPlan().linkTarget(at: PlanPoint(x: 25, y: 71), onPage: 0) == nil)
    }

    @Test("Where links overlap, the last one wins")
    func linkOverlap() {
        #expect(linkPlan().linkTarget(at: PlanPoint(x: 25, y: 40), onPage: 0) == 2)
    }

    @Test("A page that does not exist has no link")
    func linkPageOutOfRange() {
        #expect(linkPlan().linkTarget(at: PlanPoint(x: 12, y: 25), onPage: 2) == nil)
        #expect(linkPlan().linkTarget(at: PlanPoint(x: 12, y: 25), onPage: -1) == nil)
    }

    @Test("A page without links has no target")
    func linkNone() {
        #expect(linkPlan().linkTarget(at: PlanPoint(x: 12, y: 25), onPage: 1) == nil)
    }

    private func subsetPlan() -> RenderPlan {
        func page(_ key: PageKey, links: [Int]) -> PagePlan {
            PagePlan(
                key: key, chrome: .meeting,
                operations: [.fill(rect, .white)] + links.map { .link(rect, targetPage: $0) })
        }
        return RenderPlan(
            pageWidth: 100, pageHeight: 200,
            pages: [
                page(.overview, links: [1, 2, 3]),
                page(.meeting("a"), links: [0, 2]),
                page(.meeting("b"), links: [0]),
                page(.notes, links: [7, -1]),
            ],
            omittedTodoItems: [TodoItem(text: "t", notes: "", due: "")])
    }

    @Test("A subset keeps the plan's order, whatever order the keys come in")
    func subsetOrder() {
        let subset = subsetPlan().subset([.notes, .meeting("a"), .overview])
        #expect(subset.pages.map(\.key) == [.overview, .meeting("a"), .notes])
        #expect(subset.pageWidth == 100 && subset.pageHeight == 200)
        #expect(subsetPlan().subset([]).pages.isEmpty)
    }

    @Test("A subset points each link at its target's new position")
    func subsetRemapsLinks() {
        let subset = subsetPlan().subset([.meeting("a"), .meeting("b")])
        #expect(subset.pages[0].operations == [.fill(rect, .white), .link(rect, targetPage: 1)])
        #expect(subset.pages[1].operations == [.fill(rect, .white)])
        let other = subsetPlan().subset([.meeting("b"), .overview, .notes])
        #expect(
            other.pages[0].operations == [
                .fill(rect, .white), .link(rect, targetPage: 1), .link(rect, targetPage: 2),
            ])
        #expect(other.pages[1].operations == [.fill(rect, .white), .link(rect, targetPage: 0)])
    }

    @Test("A subset drops links to pages left out and to targets out of range")
    func subsetDropsLinks() {
        let subset = subsetPlan().subset([.overview, .notes])
        #expect(subset.pages[0].operations == [.fill(rect, .white)])
        #expect(subset.pages[1].operations == [.fill(rect, .white)])
    }

    @Test("A subset has no omitted to-do items")
    func subsetOmitted() {
        #expect(subsetPlan().omittedTodoItems.count == 1)
        #expect(subsetPlan().subset([.overview]).omittedTodoItems.isEmpty)
    }
}
