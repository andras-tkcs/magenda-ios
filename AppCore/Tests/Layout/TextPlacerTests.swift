// AppCore's `TextPlacer`, measured with `FakeTextMeasurer` (width 5 per Character, line height 10).

import Testing

@testable import AppCore

@Suite("Placing text")
struct TextPlacerTests {
    private let placer = TextPlacer(measurer: FakeTextMeasurer())
    private let font = FontSpec(pack: .outfit, weight: .regular, size: 10)  // ascent 8, descent 2
    private let box = PlanRect(x0: 100, y0: 200, x1: 200, y1: 240)  // 100 × 40
    private let container = PlanRect(x0: 90, y0: 190, x1: 210, y1: 250)

    private func place(
        _ lines: [String], alignment: TextAlignment = .left, indents: [Double] = []
    ) -> [TextRun] {
        placer.place(
            lines, font: font, color: .black, in: box, container: container, alignment: alignment,
            indents: indents)
    }

    @Test("One line is centered vertically")
    func oneLine() {
        let runs = place(["abcd"])
        #expect(runs.count == 1)
        #expect(runs[0].text == "abcd")
        #expect(runs[0].x == 100)
        #expect(runs[0].baseline == 223)  // top 215, ascent 8
        #expect(runs[0].width == 20)
        #expect(runs[0].ascent == 8)
        #expect(runs[0].descent == 2)
        #expect(runs[0].font == font)
        #expect(runs[0].color == .black)
        #expect(runs[0].container == container)
    }

    @Test("Lines sit one line height apart as a block centered vertically")
    func threeLines() {
        let runs = place(["a", "b", "c"])
        let expected: [Double] = [213, 223, 233]
        #expect(runs.map(\.baseline) == expected)
    }

    @Test("Centered lines are centered in the box")
    func centered() {
        let runs = place(["abcd", "ab"], alignment: .center)
        let expected: [Double] = [140, 145]
        #expect(runs.map(\.x) == expected)
    }

    @Test("Indents shift left-aligned lines; lines without one start at the box edge")
    func indents() {
        let runs = place(["a", "b", "c"], indents: [0, 12])
        let expected: [Double] = [100, 112, 100]
        #expect(runs.map(\.x) == expected)
    }

    @Test("Empty strings take their place in the block but produce no run")
    func emptyStrings() {
        let runs = place(["a", "", "c"])
        #expect(runs.map(\.text) == ["a", "c"])
        let expected: [Double] = [213, 233]
        #expect(runs.map(\.baseline) == expected)
        #expect(place([]).isEmpty)
    }
}
