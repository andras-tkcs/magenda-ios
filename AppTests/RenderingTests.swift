// The real fonts, CoreText and PDFKit: what AppCore's fake font cannot show.
//
// Runs inside the app on a simulator (a hosted unit test), so `Bundle.main` holds the bundled
// fonts and the template. The layout's own rules are tested in AppCore; this proves they hold with
// the metrics of the real fonts, and that the PDF a plan becomes has its text the right way up and
// its links in place.

import AppCore
import CoreText
import Foundation
import PDFKit
import Testing

@testable import Magenda

/// Gives `Bundle(for:)` a class in the test bundle, which holds no fonts and no template.
private final class TestBundleToken: NSObject {}

@Suite("Rendering with the real fonts")
struct RenderingTests {
    private static let fixtures: [(name: String, content: AgendaContent)] = [
        ("typical", AgendaContentFixtures.typical),
        ("longText", AgendaContentFixtures.longText),
        ("overflow", AgendaContentFixtures.overflow),
        ("empty", AgendaContentFixtures.empty),
    ]

    private func loadLibrary() throws -> FontLibrary {
        try FontLibrary(bundle: .main)
    }

    private func makePlan(
        _ content: AgendaContent, pack: FontPack = .outfit, colors: ThemeColors = .default,
        library: FontLibrary
    ) throws -> RenderPlan {
        let layout = AgendaLayout(
            manifest: try TemplateManifest.bundled(), measurer: CoreTextMeasurer(library: library),
            theme: Theme(fontPack: pack, colors: colors))
        return layout.plan(for: content)
    }

    @Test("Every font pack and weight loads from the bundle")
    func fontsLoad() throws {
        let library = try loadLibrary()
        for pack in FontPack.allCases {
            for weight in FontWeight.allCases {
                let font = library.font(FontSpec.nominal(pack, weight, 12))
                let name = pack.fontFileName(weight)
                #expect(CTFontGetSize(font) > 0, Comment(rawValue: name))
                #expect(CTFontGetAscent(font) > 0, Comment(rawValue: name))
            }
        }
    }

    @Test("A library over a bundle without fonts throws missingFont")
    func missingFonts() {
        let bundle = Bundle(for: TestBundleToken.self)
        #expect {
            try FontLibrary(bundle: bundle)
        } throws: { error in
            if case FontLibraryError.missingFont = error {
                return true
            }
            return false
        }
    }

    @Test("A renderer over a bundle without the template throws missingTemplate")
    func missingTemplate() throws {
        let library = try loadLibrary()
        let bundle = Bundle(for: TestBundleToken.self)
        #expect(throws: FontLibraryError.missingTemplate) {
            try PDFAgendaRenderer(library: library, bundle: bundle)
        }
    }

    @Test("The measurer gives positive widths, and more text is wider")
    func measuring() throws {
        let measurer = CoreTextMeasurer(library: try loadLibrary())
        let font = FontSpec.nominal(.outfit, .regular, 12)
        let base = measurer.width(of: "TO-DO LIST", font: font)
        #expect(base > 0)
        #expect(measurer.width(of: "TO-DO LIST TO-DO LIST", font: font) > base)
        for text in AgendaContentFixtures.longStrings {
            #expect(measurer.width(of: text, font: font) > 0, Comment(rawValue: text))
        }
        let metrics = measurer.metrics(for: font)
        #expect(metrics.ascent > 0)
        #expect(metrics.descent > 0)
    }

    @Test("No fixture breaks the layout under any font pack")
    func layoutAudit() throws {
        let library = try loadLibrary()
        for pack in FontPack.allCases {
            for fixture in Self.fixtures {
                let violations = LayoutAudit.violations(
                    in: try makePlan(fixture.content, pack: pack, library: library))
                #expect(
                    violations.isEmpty,
                    Comment(rawValue: "\(pack.rawValue) / \(fixture.name): \(violations)"))
            }
        }
    }

    @Test("The typical plan becomes a PDF with upright text and working links")
    func typicalPDF() async throws {
        let library = try loadLibrary()
        let plan = try makePlan(AgendaContentFixtures.typical, library: library)
        let renderer = try PDFAgendaRenderer(library: library, bundle: .main)
        let url = try await renderer.render(plan, fileName: "rendering-tests-typical.pdf")

        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == plan.pages.count)
        let first = try #require(document.page(at: 0))
        let text = first.string ?? ""
        #expect(text.contains("TO-DO LIST"))
        #expect(text.contains("30 WEDNESDAY"))

        let second = try #require(document.page(at: 1))
        let linksToFirst = second.annotations.filter { annotation in
            Self.destinationPage(of: annotation).map { document.index(for: $0) } == 0
        }
        let pageBounds = second.bounds(for: .mediaBox)
        #expect(
            linksToFirst.allSatisfy {
                pageBounds.contains($0.bounds) && $0.bounds.minY > plan.pageHeight / 2
            },
            Comment(rawValue: "overview link should sit in the header, near the top of the page"))
        let seen = second.annotations.map { "\($0.type ?? "?") \($0.bounds)" }
        #expect(!linksToFirst.isEmpty, Comment(rawValue: "page 1 annotations: \(seen)"))

        let run = try #require(
            plan.pages[0].operations.compactMap { operation -> TextRun? in
                if case .text(let run) = operation, run.text == "TO-DO LIST" {
                    return run
                }
                return nil
            }.first)
        let selection = try #require(document.findString("TO-DO LIST", withOptions: []).first)
        let box = selection.bounds(for: first)
        let runCenter: Double = run.baseline - run.ascent / 2 + run.descent / 2
        let expected: Double = plan.pageHeight - runCenter
        let actual: Double = box.midY
        #expect(
            abs(actual - expected) < 12,
            Comment(rawValue: "found at y \(actual), expected near \(expected)"))
    }

    @Test("The overflow plan becomes a PDF with every page")
    func overflowPDF() async throws {
        let library = try loadLibrary()
        let plan = try makePlan(AgendaContentFixtures.overflow, library: library)
        let renderer = try PDFAgendaRenderer(library: library, bundle: .main)
        let url = try await renderer.render(plan, fileName: "rendering-tests-overflow.pdf")
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == plan.pages.count)
    }

    @Test("Theme colors reach the PDF's text, and the default look has none of them")
    func themeColorsAreDrawn() async throws {
        let library = try loadLibrary()
        let renderer = try PDFAgendaRenderer(library: library, bundle: .main)
        let magenta = RGBColor(red: 255, green: 0, blue: 255)
        let custom = ThemeColors(
            weekend: magenta, heading: magenta, label: magenta, accent: magenta, notes: magenta)

        let plainPlan = try makePlan(AgendaContentFixtures.typical, library: library)
        let plainURL = try await renderer.render(plainPlan, fileName: "rendering-tests-plain.pdf")
        let plain = Self.magentaPixels(in: plainURL)

        let themedPlan = try makePlan(
            AgendaContentFixtures.typical, colors: custom, library: library)
        let themedURL = try await renderer.render(
            themedPlan, fileName: "rendering-tests-themed.pdf")
        let themed = Self.magentaPixels(in: themedURL)

        #expect(plain == 0, Comment(rawValue: "default page: \(plain) magenta pixels"))
        #expect(themed > 50, Comment(rawValue: "themed page: \(themed) magenta pixels"))
    }

    /// The number of nearly-magenta pixels on the first page, rasterized at twice its size.
    private static func magentaPixels(in url: URL) -> Int {
        guard let page = PDFDocument(url: url)?.page(at: 0)?.pageRef else {
            return -1
        }
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width * 2)
        let height = Int(box.height * 2)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                return false
            }
            context.scaleBy(x: 2, y: 2)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            return true
        }
        guard drawn else {
            return -1
        }
        var count = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[offset] > 200 && pixels[offset + 1] < 60 && pixels[offset + 2] > 200 {
                count += 1
            }
        }
        return count
    }

    private static func destinationPage(of annotation: PDFAnnotation) -> PDFPage? {
        if let page = annotation.destination?.page {
            return page
        }
        return (annotation.action as? PDFActionGoTo)?.destination.page
    }
}
