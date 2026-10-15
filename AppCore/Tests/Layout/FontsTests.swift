// AppCore's font packs, weights and scaled font specs.

import AppCore
import Testing

@Suite("Font packs")
struct FontsTests {
    @Test("Every pack and weight has the expected file name")
    func fileNames() {
        let suffixes: [FontWeight: String] = [
            .thin: "Thin", .extralight: "ExtraLight", .regular: "Regular", .semibold: "SemiBold",
            .black: "Black",
        ]
        let families: [FontPack: String] = [
            .outfit: "Outfit", .roboto: "Roboto", .jetbrainsMono: "JetBrainsMono",
        ]
        var checked = 0
        for pack in FontPack.allCases {
            for weight in FontWeight.allCases {
                let expected = "\(families[pack] ?? "")-\(suffixes[weight] ?? "")"
                #expect(pack.fontFileName(weight) == expected)
                checked += 1
            }
        }
        #expect(checked == 15)
        #expect(FontPack.jetbrainsMono.fontFileName(.extralight) == "JetBrainsMono-ExtraLight")
    }

    @Test("Display names, scales and raw values")
    func packProperties() {
        #expect(FontPack.allCases.map(\.displayName) == ["Outfit", "Roboto", "JetBrains Mono"])
        #expect(FontPack.allCases.map(\.sizeScale) == [1.0, 1.0, 0.9])
        #expect(FontPack.jetbrainsMono.rawValue == "jetbrains_mono")
    }

    @Test("A nominal size is scaled by the pack")
    func nominalSize() {
        #expect(FontSpec.nominal(.outfit, .regular, 10).size == 10)
        #expect(FontSpec.nominal(.jetbrainsMono, .black, 10).size == 9)
        let spec = FontSpec(pack: .roboto, weight: .thin, size: 7)
        #expect(spec == FontSpec.nominal(.roboto, .thin, 7))
    }

    @Test("Font metrics add up to a line height")
    func lineHeight() {
        #expect(FontMetrics(ascent: 8, descent: 2).lineHeight == 10)
    }
}
