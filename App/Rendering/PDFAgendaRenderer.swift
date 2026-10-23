import AppCore
import CoreGraphics
import Foundation
import PencilKit
import UIKit

/// Draws a `RenderPlan` and the handwriting on its pages, and writes the result to a PDF file.
// Holds the page drawer, immutable after `init`; each `render` call draws with its own context.
final class PDFAgendaRenderer: AgendaRendering, @unchecked Sendable {
    private let drawer: PageDrawer

    init(drawer: PageDrawer) {
        self.drawer = drawer
    }

    func render(_ plan: RenderPlan, ink: [Data?], fileName: String) async throws -> URL {
        try write(plan, ink: ink, fileName: fileName)
    }

    /// The work of `render` without the `async`, so a test can run it under a trait collection.
    func write(_ plan: RenderPlan, ink: [Data?], fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Agendas", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: FileProtection.attributes)
        try FileManager.default.setAttributes(
            FileProtection.attributes, ofItemAtPath: directory.path)
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
                drawer.draw(page, in: context.cgContext, pageHeight: plan.pageHeight)
                if index < ink.count, let data = ink[index] {
                    Self.drawInk(data, in: bounds)
                }
                for operation in page.operations {
                    if case .link(let rect, let targetPage) = operation {
                        // Link rects are taken in PDF default space (origin bottom-left), unlike
                        // the flipped drawing context, so mirror the plan's top-left rect.
                        UIGraphicsSetPDFContextDestinationForRect(
                            "page-\(targetPage)",
                            CGRect(
                                x: rect.x0, y: plan.pageHeight - rect.y1,
                                width: rect.x1 - rect.x0, height: rect.y1 - rect.y0))
                    }
                }
            }
        }
        try FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: url.path)
        return url
    }

    /// Draws `data`'s handwriting over the page; data that is not a drawing is skipped. The
    /// drawing is imaged with the light trait collection, as dark mode would turn black ink white.
    private static func drawInk(_ data: Data, in bounds: CGRect) {
        guard let drawing = try? PKDrawing(data: data) else {
            return
        }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: 3)
        }
        image?.draw(in: bounds)
    }
}
