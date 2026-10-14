// AppCore's colors, theme and hex handling.

import AppCore
import Foundation
import Testing

@Suite("Theme colors")
struct ThemeColorsTests {
    @Test("Valid hex strings parse", arguments: ["215e99", "#215E99", " 215E99 "])
    func parsesHex(text: String) {
        #expect(RGBColor(hex: text) == RGBColor(red: 0x21, green: 0x5E, blue: 0x99))
    }

    @Test(
        "Invalid hex strings are rejected",
        arguments: ["215E9", "215E99F", "GGGGGG", "##215E99", "+12345", ""])
    func rejectsHex(text: String) {
        #expect(RGBColor(hex: text) == nil)
    }

    @Test("Hex is uppercase without a hash; black and white are fixed")
    func hexOutput() {
        #expect(RGBColor(red: 0x21, green: 0x5E, blue: 0x99).hex == "215E99")
        #expect(RGBColor(red: 0, green: 0, blue: 0x0A).hex == "00000A")
        #expect(RGBColor.black.hex == "000000")
        #expect(RGBColor.white.hex == "FFFFFF")
    }

    @Test("Defaults and roles")
    func defaults() {
        let colors = ThemeColors.default
        #expect(colors.weekend.hex == "EE0000")
        #expect(colors.heading.hex == "215E99")
        #expect(colors.label.hex == "BF4E14")
        #expect(colors.accent.hex == "3A7C22")
        #expect(colors.notes.hex == "00B0F0")
        #expect(colors.color(for: .body).hex == "000000")
        #expect(colors.color(for: .heading) == colors.heading)
        #expect(colors.color(for: .label) == colors.label)
        #expect(colors.color(for: .accent) == colors.accent)
        #expect(colors.color(for: .notes) == colors.notes)
        #expect(colors.color(for: .weekend) == colors.weekend)
    }

    @Test("Colors survive a JSON round trip as hex strings")
    func roundTrip() throws {
        var colors = ThemeColors.default
        colors.accent = RGBColor(red: 1, green: 2, blue: 3)
        let data = try JSONEncoder().encode(colors)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"accent\":\"010203\""))
        #expect(try JSONDecoder().decode(ThemeColors.self, from: data) == colors)
    }

    @Test("An invalid, missing or mistyped color keeps its default")
    func tolerantDecoding() throws {
        let decoder = JSONDecoder()
        let invalid = try decoder.decode(ThemeColors.self, from: Data(#"{"weekend":"nope"}"#.utf8))
        #expect(invalid == .default)
        let mixed = try decoder.decode(
            ThemeColors.self, from: Data(#"{"heading":"000001","label":5}"#.utf8))
        #expect(mixed.heading.hex == "000001")
        #expect(mixed.label == ThemeColors.default.label)
    }

    @Test("A theme defaults to Outfit and the default colors")
    func themeDefaults() {
        let theme = Theme()
        #expect(theme.fontPack == .outfit)
        #expect(theme.colors == .default)
    }
}
