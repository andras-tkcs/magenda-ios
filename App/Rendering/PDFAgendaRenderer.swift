import AppCore
import CoreGraphics
import CoreText
import Foundation
import UIKit

/// Draws a `RenderPlan` on top of the template PDF's pages and writes the result to a file.
// Holds the template document and the font library, both immutable after `init`; each `render`
// call draws with its own context.
final class PDFAgendaRenderer: AgendaRendering, @unchecked Sendable {
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

    func render(_ plan: RenderPlan, ink: [Data?], fileName: String) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Agendas", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let bounds = CGRect(x: 0, y: 0, width: plan.pageWidth, height: plan.pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        try renderer.writePDF(to: url) { context in
            for (index, page) in plan.pages.enumerated() {
                context.beginPage()
                UIGraphicsAddPDFContextDestinationAtPoint("page-\(index)", .zero)
                drawChrome(page.chrome, in: context.cgContext, height: plan.pageHeight)
                for operation in page.operations {
                    draw(operation, in: context.cgContext, pageHeight: plan.pageHeight)
                }
            }
        }
        return url
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

    private func draw(_ operation: DrawOperation, in context: CGContext, pageHeight: Double) {
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
        case .link(let rect, let targetPage):
            // Link rects are taken in PDF default space (origin bottom-left), unlike the
            // flipped drawing context, so mirror the plan's top-left rect vertically.
            let flipped = PlanRect(
                x0: rect.x0, y0: pageHeight - rect.y1, x1: rect.x1, y1: pageHeight - rect.y0)
            UIGraphicsSetPDFContextDestinationForRect("page-\(targetPage)", Self.cgRect(flipped))
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
