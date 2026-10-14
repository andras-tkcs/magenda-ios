/// How a line sits horizontally in its box.
enum TextAlignment {
    case left
    case center
}

/// Turns already-fitted lines into positioned runs.
struct TextPlacer {
    let measurer: any TextMeasuring

    init(measurer: any TextMeasuring) {
        self.measurer = measurer
    }

    /// Places `lines` as one block centered vertically in `box`. Line *i* is indented by
    /// `indents[i]` when given (left alignment only); empty lines take space but produce no run.
    func place(
        _ lines: [String], font: FontSpec, color: RGBColor, in box: PlanRect, container: PlanRect,
        alignment: TextAlignment, indents: [Double] = []
    ) -> [TextRun] {
        let metrics = measurer.metrics(for: font)
        let blockHeight = Double(lines.count) * metrics.lineHeight
        let top = box.y0 + (box.height - blockHeight) / 2
        return lines.enumerated().compactMap { index, line in
            if line.isEmpty { return nil }
            let width = measurer.width(of: line, font: font)
            let x =
                switch alignment {
                case .left: box.x0 + (index < indents.count ? indents[index] : 0)
                case .center: box.x0 + (box.width - width) / 2
                }
            return TextRun(
                text: line, font: font, color: color, x: x,
                baseline: top + metrics.ascent + Double(index) * metrics.lineHeight, width: width,
                ascent: metrics.ascent, descent: metrics.descent, container: container)
        }
    }
}
