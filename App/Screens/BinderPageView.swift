import AppCore
import PencilKit
import SwiftUI
import UIKit

/// The canvases of the pages on screen, so undo and redo can reach the one last drawn on.
@MainActor
final class CanvasRegistry {
    private struct Entry {
        weak var canvas: PKCanvasView?
    }

    private var entries: [PageKey: Entry] = [:]

    /// Remembers `canvas` as the canvas of the page `key`.
    func register(_ canvas: PKCanvasView, for key: PageKey) {
        entries[key] = Entry(canvas: canvas)
    }

    /// The canvas of the page `key`, or nil when it is not on screen.
    func canvas(for key: PageKey) -> PKCanvasView? {
        entries[key]?.canvas
    }
}

/// One page of the binder: the page as `PageDrawer` draws it, with a PencilKit canvas on top that
/// keeps its strokes in page points.
struct BinderPageView: UIViewRepresentable {
    let page: PagePlan
    let pageWidth: Double
    let pageHeight: Double
    /// The page's handwriting as PencilKit data, or nil when it has none.
    let ink: Data?
    let allowsFingerDrawing: Bool
    /// What a touch on the canvas does.
    let tool: BinderTool
    /// Where this page's canvas is registered for undo and redo.
    let registry: CanvasRegistry
    /// The page a tap at a point of this page jumps to, if the point is on a link.
    let linkTarget: (PlanPoint) -> Int?
    /// Called with the index of the page a tapped link jumps to.
    let onLinkTap: (Int) -> Void
    /// Called with the new handwriting after each change on the canvas; empty when it was erased.
    let onInkChange: (Data) -> Void

    @Environment(\.pageDrawer) private var drawer

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> BinderPageUIView {
        let view = BinderPageUIView()
        view.canvas.delegate = context.coordinator
        registry.register(view.canvas, for: page.key)
        // Only a finger follows links; the pencil writes.
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.cancelsTouchesInView = false
        view.canvas.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: BinderPageUIView, context: Context) {
        context.coordinator.parent = self
        view.pageSize = CGSize(width: pageWidth, height: pageHeight)
        view.background.page = page
        view.background.drawer = drawer
        view.canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        context.coordinator.apply(tool, to: view.canvas)
        context.coordinator.apply(ink, to: view.canvas)
    }

    /// Puts saved handwriting on the canvas and reports the person's changes, never echoing back
    /// what it applied itself.
    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: BinderPageView
        // The handwriting last applied to or reported from the canvas; nil for none.
        private var lastData: Data?
        private var isApplying = false
        private var appliedTool: BinderTool?

        init(parent: BinderPageView) {
            self.parent = parent
        }

        /// Makes `tool` the canvas's tool unless it already is.
        func apply(_ tool: BinderTool, to canvas: PKCanvasView) {
            guard tool != appliedTool else {
                return
            }
            appliedTool = tool
            switch tool {
            case .pen(let pen):
                let color = pen.color
                canvas.tool = PKInkingTool(
                    .pen,
                    color: UIColor(
                        red: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
                        blue: CGFloat(color.blue) / 255, alpha: 1),
                    width: 2)
            case .eraser:
                canvas.tool = PKEraserTool(.bitmap, width: 12)
            }
        }

        /// Follows the link under a finger's tap, if there is one.
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let canvas = recognizer.view as? PKCanvasView, canvas.zoomScale > 0 else {
                return
            }
            let location = recognizer.location(in: canvas)
            let point = PlanPoint(
                x: Double(location.x / canvas.zoomScale), y: Double(location.y / canvas.zoomScale))
            if let target = parent.linkTarget(point) {
                parent.onLinkTap(target)
            }
        }

        /// Shows `ink` on `canvas` unless it is what the canvas already holds.
        func apply(_ ink: Data?, to canvas: PKCanvasView) {
            guard ink != lastData else {
                return
            }
            lastData = ink
            isApplying = true
            canvas.drawing = ink.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
            isApplying = false
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplying else {
                return
            }
            let drawing = canvasView.drawing
            let data = drawing.strokes.isEmpty ? Data() : drawing.dataRepresentation()
            lastData = data.isEmpty ? nil : data
            parent.onInkChange(data)
        }
    }
}

/// A binder page's view: the drawn page under a transparent canvas, both filling the bounds. The
/// canvas is zoomed to the view's width so its strokes are stored in page points.
final class BinderPageUIView: UIView {
    let background: PageBackgroundView
    let canvas: PKCanvasView

    /// The page's size in points.
    var pageSize = CGSize.zero {
        didSet {
            guard pageSize != oldValue else {
                return
            }
            background.pageSize = pageSize
            appliedScale = 0
            setNeedsLayout()
        }
    }

    private var appliedScale: CGFloat = 0

    override init(frame: CGRect) {
        background = PageBackgroundView()
        canvas = PKCanvasView()
        super.init(frame: frame)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        // A page under the navigation bar must not shift its strokes by the safe area.
        canvas.contentInsetAdjustmentBehavior = .never
        addSubview(background)
        addSubview(canvas)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        canvas.frame = bounds
        guard pageSize.width > 0, bounds.width > 0 else {
            return
        }
        let scale = bounds.width / pageSize.width
        guard scale != appliedScale else {
            return
        }
        appliedScale = scale
        canvas.minimumZoomScale = scale
        canvas.maximumZoomScale = scale
        canvas.zoomScale = scale
        canvas.contentSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
    }
}

/// Draws a binder page with `PageDrawer`, scaled from page points to the view's width.
final class PageBackgroundView: UIView {
    /// The page to draw.
    var page: PagePlan? {
        didSet {
            if page != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// The drawer to draw it with; nothing is drawn without one.
    var drawer: PageDrawer? {
        didSet {
            if drawer !== oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// The page's size in points.
    var pageSize = CGSize.zero {
        didSet {
            if pageSize != oldValue {
                setNeedsDisplay()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ rect: CGRect) {
        guard let page, let drawer, let context = UIGraphicsGetCurrentContext() else {
            return
        }
        guard pageSize.width > 0 else {
            return
        }
        let scale = bounds.width / pageSize.width
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        drawer.draw(page, in: context, pageHeight: pageSize.height)
        context.restoreGState()
    }
}
