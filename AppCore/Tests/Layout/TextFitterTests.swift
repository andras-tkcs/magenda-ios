// AppCore's `TextFitter`, measured with `FakeTextMeasurer` (each Character is 0.5 × the size wide).

import AppCore
import Testing

@Suite("Fitting text")
struct TextFitterTests {
    private let fitter = TextFitter(measurer: FakeTextMeasurer())
    private let font = FontSpec(pack: .outfit, weight: .regular, size: 10)  // 5 per Character

    private func width(_ text: String) -> Double {
        FakeTextMeasurer().width(of: text, font: font)
    }

    @Test("Whitespace and control characters collapse to single spaces")
    func normalizes() {
        #expect(TextFitter.normalized("  a\n\tb\r\n  c\u{07}d  ") == "a b c d")
        #expect(TextFitter.normalized("a    b") == "a b")
        #expect(TextFitter.normalized(" \n ") == "")
    }

    @Test("Ellipsizing never splits a joined family")
    func ellipsizeKeepsCharacters() {
        let family = "👩‍👩‍👧‍👦"
        let text = "ab" + family + "cd"
        for characters in 1...6 {
            let result = fitter.ellipsized(text, font: font, maxWidth: Double(characters) * 5)
            #expect(width(result) <= Double(characters) * 5)
            #expect(result.hasSuffix("…"))
            let prefix = String(result.dropLast())
            #expect(prefix == "" || text.hasPrefix(prefix))
            #expect(!prefix.contains(family) || prefix.hasPrefix("ab" + family))
        }
        #expect(fitter.ellipsized(text, font: font, maxWidth: 20) == "ab" + family + "…")
    }

    @Test("Ellipsizing returns an empty string when the ellipsis does not fit")
    func ellipsisDoesNotFit() {
        #expect(fitter.ellipsized("abc", font: font, maxWidth: 4) == "")
        #expect(fitter.ellipsized("abc", font: font, maxWidth: 5) == "…")
    }

    @Test("Ellipsizing strips trailing spaces before the ellipsis")
    func ellipsizeStripsSpaces() {
        #expect(fitter.ellipsized("ab  cd", font: font, maxWidth: 20) == "ab…")
    }

    @Test("A single line that fits is unchanged; a long one ends in an ellipsis")
    func singleLine() {
        #expect(fitter.singleLine(" short \n text ", font: font, maxWidth: 100) == "short text")
        let cut = fitter.singleLine(String(repeating: "x", count: 50), font: font, maxWidth: 50)
        #expect(cut.hasSuffix("…"))
        #expect(width(cut) <= 50)
        #expect(cut.count == 10)
    }

    @Test("Words wrap greedily")
    func wrapsWords() {
        let lines = fitter.wrap("aa bb cc dd", font: font, maxWidth: 25, maxLines: 5)
        #expect(lines == ["aa bb", "cc dd"])
    }

    @Test("A word wider than a line is broken into lines that each fit")
    func breaksLongWords() {
        let word = String(repeating: "w", count: 200)
        let lines = fitter.wrap(word, font: font, maxWidth: 50, maxLines: 100)
        #expect(lines.count == 20)
        #expect(lines.allSatisfy { width($0) <= 50 })
        #expect(lines.joined().count == 200)
    }

    @Test("A long word after a short one starts a new line")
    func longWordAfterShortOne() {
        let text = "ab " + String(repeating: "w", count: 15)
        let lines = fitter.wrap(text, font: font, maxWidth: 50, maxLines: 10)
        #expect(lines == ["ab", "wwwwwwwwww", "wwwww"])
    }

    @Test("Text without spaces wraps at character boundaries")
    func wrapsCJK() {
        let lines = fitter.wrap("今日は会議があります", font: font, maxWidth: 20, maxLines: 10)
        #expect(lines == ["今日は会", "議があり", "ます"])
    }

    @Test("A too-narrow width still makes progress one Character at a time")
    func tooNarrow() {
        let lines = fitter.wrap("abc", font: font, maxWidth: 1, maxLines: 10)
        #expect(lines == ["a", "b", "c"])
    }

    @Test("Wrapping stops at maxLines with an ellipsized last line")
    func capsLines() {
        let lines = fitter.wrap("aa bb cc dd ee", font: font, maxWidth: 25, maxLines: 2)
        #expect(lines == ["aa bb", "cc d…"])
        #expect(fitter.wrap("aa bb cc dd ee", font: font, maxWidth: 25, maxLines: 0).count == 1)
    }

    @Test("Blank text has no lines")
    func blankText() {
        #expect(fitter.wrap(" \n ", font: font, maxWidth: 25, maxLines: 3) == [])
    }

    @Test("The largest fitting size wins")
    func downsizes() {
        // "abcdefgh" is 8 Characters; at size s it is 4s wide.
        let result = fitter.downsizeOrWrap(
            "abcdefgh", pack: .outfit, weight: .regular, maxPoints: 12, minPoints: 6,
            maxWidth: 40, maxLines: 3)
        #expect(result.lines == ["abcdefgh"])
        #expect(result.font == .nominal(.outfit, .regular, 10))
        let unscaled = fitter.downsizeOrWrap(
            "abcdefgh", pack: .outfit, weight: .regular, maxPoints: 5, minPoints: 3,
            maxWidth: 40, maxLines: 3)
        #expect(unscaled.font.size == 5)
    }

    @Test("Text that fits at no size wraps at the minimum")
    func wrapsAtMinimum() {
        let result = fitter.downsizeOrWrap(
            "aaaa bbbb", pack: .jetbrainsMono, weight: .regular, maxPoints: 10, minPoints: 8,
            maxWidth: 15, maxLines: 3)
        #expect(result.font == .nominal(.jetbrainsMono, .regular, 8))
        #expect(result.lines == ["aaaa", "bbbb"])
    }
}
