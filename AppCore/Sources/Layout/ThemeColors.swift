import Foundation

/// An sRGB color with 8 bits per channel.
public struct RGBColor: Hashable, Codable, Sendable {
    /// The red channel.
    public let red: UInt8
    /// The green channel.
    public let green: UInt8
    /// The blue channel.
    public let blue: UInt8

    /// Creates a color from its channels.
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses exactly six hex digits, ignoring surrounding whitespace and one leading `#`.
    public init?(hex: String) {
        var digits = Substring(hex.trimmingCharacters(in: .whitespacesAndNewlines))
        if digits.hasPrefix("#") {
            digits = digits.dropFirst()
        }
        guard digits.utf8.count == 6, digits.utf8.allSatisfy({ $0.isASCIIHexDigit }),
            let value = UInt32(digits, radix: 16)
        else {
            return nil
        }
        self.init(
            red: UInt8(value >> 16), green: UInt8((value >> 8) & 0xFF), blue: UInt8(value & 0xFF))
    }

    /// Six uppercase hex digits without a `#`, such as `215E99`.
    public var hex: String {
        String(format: "%02X%02X%02X", red, green, blue)
    }

    /// Pure black.
    public static let black = RGBColor(red: 0, green: 0, blue: 0)
    /// Pure white.
    public static let white = RGBColor(red: 255, green: 255, blue: 255)
}

extension UInt8 {
    fileprivate var isASCIIHexDigit: Bool {
        (0x30...0x39).contains(self) || (0x41...0x46).contains(self)
            || (0x61...0x66).contains(self)
    }
}

/// What a piece of agenda text is for, which decides its color.
public enum TextRole: String, Codable, Sendable {
    case heading
    case label
    case accent
    case notes
    case weekend
    case body
}

/// The colors the user can change; body text is always black.
public struct ThemeColors: Equatable, Codable, Sendable {
    /// Weekend day numbers and names.
    public var weekend: RGBColor
    /// Headings.
    public var heading: RGBColor
    /// Labels.
    public var label: RGBColor
    /// Accents.
    public var accent: RGBColor
    /// Notes.
    public var notes: RGBColor

    /// Creates a set of colors.
    public init(
        weekend: RGBColor, heading: RGBColor, label: RGBColor, accent: RGBColor, notes: RGBColor
    ) {
        self.weekend = weekend
        self.heading = heading
        self.label = label
        self.accent = accent
        self.notes = notes
    }

    /// The colors of the original template.
    public static let `default` = ThemeColors(
        weekend: RGBColor(red: 0xEE, green: 0x00, blue: 0x00),
        heading: RGBColor(red: 0x21, green: 0x5E, blue: 0x99),
        label: RGBColor(red: 0xBF, green: 0x4E, blue: 0x14),
        accent: RGBColor(red: 0x3A, green: 0x7C, blue: 0x22),
        notes: RGBColor(red: 0x00, green: 0xB0, blue: 0xF0))

    /// The color text of `role` is set in.
    public func color(for role: TextRole) -> RGBColor {
        switch role {
        case .heading: heading
        case .label: label
        case .accent: accent
        case .notes: notes
        case .weekend: weekend
        case .body: .black
        }
    }

    private enum CodingKeys: String, CodingKey {
        case weekend, heading, label, accent, notes
    }

    /// Decodes colors written as hex strings; a missing or invalid one keeps its default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decoded(_ key: CodingKeys, _ fallback: RGBColor) -> RGBColor {
            (try? container.decodeIfPresent(String.self, forKey: key))
                .flatMap { RGBColor(hex: $0) } ?? fallback
        }
        let defaults = ThemeColors.default
        self.init(
            weekend: decoded(.weekend, defaults.weekend),
            heading: decoded(.heading, defaults.heading),
            label: decoded(.label, defaults.label),
            accent: decoded(.accent, defaults.accent),
            notes: decoded(.notes, defaults.notes))
    }

    /// Encodes each color as its hex string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weekend.hex, forKey: .weekend)
        try container.encode(heading.hex, forKey: .heading)
        try container.encode(label.hex, forKey: .label)
        try container.encode(accent.hex, forKey: .accent)
        try container.encode(notes.hex, forKey: .notes)
    }
}

/// The font family and colors the agenda is rendered with.
public struct Theme: Equatable, Sendable {
    /// The font family.
    public var fontPack: FontPack
    /// The colors.
    public var colors: ThemeColors

    /// Creates a theme; the defaults are the original template's look.
    public init(fontPack: FontPack = .outfit, colors: ThemeColors = .default) {
        self.fontPack = fontPack
        self.colors = colors
    }
}
