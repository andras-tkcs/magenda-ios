/// A bundled font family the agenda can be set in.
public enum FontPack: String, Codable, CaseIterable, Sendable {
    case outfit
    case roboto
    case jetbrainsMono = "jetbrains_mono"

    /// The name shown in settings.
    public var displayName: String {
        switch self {
        case .outfit: "Outfit"
        case .roboto: "Roboto"
        case .jetbrainsMono: "JetBrains Mono"
        }
    }

    /// The factor applied to every nominal size, so a wider family fills the same space.
    public var sizeScale: Double {
        switch self {
        case .outfit, .roboto: 1.0
        case .jetbrainsMono: 0.9
        }
    }

    /// The file name, without extension, of this family's font at `weight`.
    public func fontFileName(_ weight: FontWeight) -> String {
        let family =
            switch self {
            case .outfit: "Outfit"
            case .roboto: "Roboto"
            case .jetbrainsMono: "JetBrainsMono"
            }
        return "\(family)-\(weight.fileSuffix)"
    }
}

/// A weight of a bundled font family.
public enum FontWeight: String, Codable, CaseIterable, Sendable {
    case thin
    case extralight
    case regular
    case semibold
    case black

    /// The suffix the weight has in font file names.
    var fileSuffix: String {
        switch self {
        case .thin: "Thin"
        case .extralight: "ExtraLight"
        case .regular: "Regular"
        case .semibold: "SemiBold"
        case .black: "Black"
        }
    }
}

/// A concrete font: family, weight and a size that already includes the family's scale.
public struct FontSpec: Hashable, Sendable {
    /// The font family.
    public let pack: FontPack
    /// The weight within the family.
    public let weight: FontWeight
    /// The size in points, after `FontPack.sizeScale`.
    public let size: Double

    /// Creates a font with an exact, already scaled size.
    public init(pack: FontPack, weight: FontWeight, size: Double) {
        self.pack = pack
        self.weight = weight
        self.size = size
    }

    /// The font for a nominal size, scaled by the family's `sizeScale`.
    public static func nominal(
        _ pack: FontPack, _ weight: FontWeight, _ points: Double
    ) -> FontSpec {
        FontSpec(pack: pack, weight: weight, size: points * pack.sizeScale)
    }
}
