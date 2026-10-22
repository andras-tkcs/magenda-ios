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
}
