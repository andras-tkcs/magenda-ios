import AppCore
import CoreGraphics
import CoreText
import Foundation
import SwiftUI

/// Draws one page of a `RenderPlan`: the template's chrome and every operation but the links.
// Holds the template document and the font library, both immutable after `init`; each `draw`
// call draws with its own context.
final class PageDrawer: @unchecked Sendable {
    private let library: FontLibrary
    private let template: CGPDFDocument

    /// Loads the template from `bundle`; throws `missingTemplate` when it is absent,
    /// unreadable or has fewer than the four chrome pages.
    init(library: FontLibrary, bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "chrome", withExtension: "pdf"),
            let document = CGPDFDocument(url as CFURL),
            document.numberOfPages >= 4
        else {
            throw FontLibraryError.missingTemplate
        }
        self.library = library
        template = document
    }

    /// Draws the chrome of `page` and then its operations, except the links, into `context`,
    /// whose origin is the top-left corner of a page `pageHeight` points tall.
    func draw(_ page: PagePlan, in context: CGContext, pageHeight: Double) {
        drawChrome(page.chrome, in: context, height: pageHeight)
        for operation in page.operations {
            draw(operation, in: context)
        }
    }

    private func drawChrome(_ chrome: ChromePage, in context: CGContext, height: Double) {
        guard let page = template.page(at: chrome.rawValue + 1) else {
            return
        }
        context.saveGState()
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        context.drawPDFPage(page)
        context.restoreGState()
    }

    private func draw(_ operation: DrawOperation, in context: CGContext) {
        switch operation {
        case .fill(let rect, let color):
            context.setFillColor(Self.cgColor(color))
            context.fill(Self.cgRect(rect))
        case .stroke(let rect, let color, let lineWidth):
            context.setStrokeColor(Self.cgColor(color))
            context.setLineWidth(lineWidth)
            context.stroke(Self.cgRect(rect))
        case .line(let from, let to, let color, let lineWidth):
            context.setStrokeColor(Self.cgColor(color))
            context.setLineWidth(lineWidth)
            context.move(to: CGPoint(x: from.x, y: from.y))
            context.addLine(to: CGPoint(x: to.x, y: to.y))
            context.strokePath()
        case .text(let run):
            drawText(run, in: context)
        case .link:
            break
        }
    }

    private func drawText(_ run: TextRun, in context: CGContext) {
        let line = CoreTextMeasurer.line(for: run.text, font: library.font(run.font))
        context.saveGState()
        context.translateBy(x: run.x, y: run.baseline)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        context.setFillColor(Self.cgColor(run.color))
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func cgColor(_ color: RGBColor) -> CGColor {
        CGColor(
            srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255, alpha: 1)
    }

    private static func cgRect(_ rect: PlanRect) -> CGRect {
        CGRect(x: rect.x0, y: rect.y0, width: rect.x1 - rect.x0, height: rect.y1 - rect.y0)
    }
}

extension EnvironmentValues {
    /// The drawer the binder's pages are drawn with; nil in previews that have none.
    @Entry var pageDrawer: PageDrawer?
    /// Whether a finger, not only the Pencil, writes on a binder page.
    @Entry var allowsFingerDrawing = false
}
