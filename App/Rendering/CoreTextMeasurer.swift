import AppCore
import CoreText
import Foundation

/// Measures text with CoreText and the bundled fonts, so the layout is fitted to what is drawn.
// Holds only an immutable `FontLibrary`; CoreText lines and fonts are created per call.
struct CoreTextMeasurer: TextMeasuring, @unchecked Sendable {
    private let library: FontLibrary

    init(library: FontLibrary) {
        self.library = library
    }

    /// The line the measurer measures and the renderer draws; CoreText's font fallback covers
    /// emoji, CJK and Arabic.
    static func line(for text: String, font: CTFont) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            // Without this CTLineDraw ignores the context's fill color and draws black.
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        return CTLineCreateWithAttributedString(string)
    }

    func width(of text: String, font: FontSpec) -> Double {
        let line = Self.line(for: text, font: library.font(font))
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    func metrics(for font: FontSpec) -> FontMetrics {
        let ctFont = library.font(font)
        return FontMetrics(ascent: CTFontGetAscent(ctFont), descent: CTFontGetDescent(ctFont))
    }
}
