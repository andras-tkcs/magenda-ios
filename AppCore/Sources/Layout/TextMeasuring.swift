/// The vertical extent of a font, both values positive.
public struct FontMetrics: Equatable, Sendable {
    /// Distance from the baseline to the top of the tallest glyph.
    public let ascent: Double
    /// Distance from the baseline to the bottom of the lowest glyph.
    public let descent: Double

    /// Creates metrics from an ascent and a descent.
    public init(ascent: Double, descent: Double) {
        self.ascent = ascent
        self.descent = descent
    }

    /// The height of one line of text.
    public var lineHeight: Double { ascent + descent }
}

/// Measures text. The app implements it with CoreText; tests use a fake.
public protocol TextMeasuring: Sendable {
    /// The advance width of `text` set in `font`.
    func width(of text: String, font: FontSpec) -> Double

    /// The ascent and descent of `font`.
    func metrics(for font: FontSpec) -> FontMetrics
}
