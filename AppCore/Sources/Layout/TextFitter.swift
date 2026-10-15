/// Text fitted to a width: the lines to draw and the font to draw them in.
public struct FittedText: Equatable, Sendable {
    /// The lines, top to bottom.
    public let lines: [String]
    /// The font the lines were fitted with.
    public let font: FontSpec

    /// Creates fitted text.
    public init(lines: [String], font: FontSpec) {
        self.lines = lines
        self.font = font
    }
}

/// The only place text is shortened, wrapped or sized to fit. All cutting is by `Character`, so an
/// emoji or a joined family is never split.
public struct TextFitter: Sendable {
    private let measurer: any TextMeasuring

    /// Creates a fitter that measures with `measurer`.
    public init(measurer: any TextMeasuring) {
        self.measurer = measurer
    }

    /// `text` with every run of whitespace or control characters turned into one space and the
    /// ends trimmed.
    public static func normalized(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in text {
            if character.isWhitespace
                || character.asciiValue.map({ $0 < 0x20 || $0 == 0x7F }) == true
            {
                pendingSpace = true
            } else {
                if pendingSpace && !result.isEmpty {
                    result.append(" ")
                }
                pendingSpace = false
                result.append(character)
            }
        }
        return result
    }

    /// The longest prefix of `text` that fits `maxWidth` with `…` appended, or `""` if not even
    /// the ellipsis fits.
    public func ellipsized(_ text: String, font: FontSpec, maxWidth: Double) -> String {
        let characters = Array(text)
        let count = longestPrefix(characters.count) {
            measurer.width(of: String(characters[..<$0]) + "…", font: font) <= maxWidth
        }
        guard measurer.width(of: "…", font: font) <= maxWidth else {
            return ""
        }
        var prefix = String(characters[..<count])
        while prefix.last == " " {
            prefix.removeLast()
        }
        return prefix + "…"
    }

    /// `text` normalized onto one line, cut with `…` if it is wider than `maxWidth`.
    public func singleLine(_ text: String, font: FontSpec, maxWidth: Double) -> String {
        let line = Self.normalized(text)
        if measurer.width(of: line, font: font) <= maxWidth {
            return line
        }
        return ellipsized(line, font: font, maxWidth: maxWidth)
    }

    /// `text` wrapped greedily by words into at most `maxLines` lines, breaking words wider than
    /// `maxWidth`; the last line is ellipsized when text remains.
    public func wrap(_ text: String, font: FontSpec, maxWidth: Double, maxLines: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in Self.normalized(text).split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if measurer.width(of: candidate, font: font) <= maxWidth {
                current = candidate
                continue
            }
            if !current.isEmpty {
                lines.append(current)
            }
            var rest = Array(word)
            while rest.count > 1, measurer.width(of: String(rest), font: font) > maxWidth {
                let count = max(
                    1,
                    longestPrefix(rest.count) {
                        measurer.width(of: String(rest[..<$0]), font: font) <= maxWidth
                    })
                lines.append(String(rest[..<count]))
                rest.removeFirst(count)
            }
            current = String(rest)
        }
        if !current.isEmpty {
            lines.append(current)
        }
        let limit = max(1, maxLines)
        guard lines.count > limit else {
            return lines
        }
        let remaining = lines[(limit - 1)...].joined(separator: " ")
        return Array(lines[..<(limit - 1)])
            + [ellipsized(remaining, font: font, maxWidth: maxWidth)]
    }

    /// The text on one line at the largest nominal size from `maxPoints` down to `minPoints` (in
    /// steps of one point) that fits, or wrapped at `minPoints` when none does.
    public func downsizeOrWrap(
        _ text: String, pack: FontPack, weight: FontWeight, maxPoints: Double,
        minPoints: Double, maxWidth: Double, maxLines: Int
    ) -> FittedText {
        let line = Self.normalized(text)
        for points in stride(from: maxPoints, through: minPoints, by: -1) {
            let font = FontSpec.nominal(pack, weight, points)
            if measurer.width(of: line, font: font) <= maxWidth {
                return FittedText(lines: [line], font: font)
            }
        }
        let font = FontSpec.nominal(pack, weight, minPoints)
        return FittedText(
            lines: wrap(line, font: font, maxWidth: maxWidth, maxLines: maxLines), font: font)
    }

    /// The largest `n` in `0...upperBound` for which `fits(n)` holds, assuming it holds for
    /// every smaller count too; 0 when nothing fits.
    private func longestPrefix(_ upperBound: Int, fits: (Int) -> Bool) -> Int {
        var low = 0
        var high = upperBound
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(middle) {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }
}
