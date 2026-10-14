// A deterministic `TextMeasuring` for tests: every Character is half a font size wide.

import AppCore

struct FakeTextMeasurer: TextMeasuring {
    func width(of text: String, font: FontSpec) -> Double {
        Double(text.count) * font.size * 0.5
    }

    func metrics(for font: FontSpec) -> FontMetrics {
        FontMetrics(ascent: 0.8 * font.size, descent: 0.2 * font.size)
    }
}
