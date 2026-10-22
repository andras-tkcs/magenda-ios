/// A point on a page, in points, with the origin at the top left.
public struct PlanPoint: Equatable, Decodable, Sendable {
    /// Distance from the left edge.
    public let x: Double
    /// Distance from the top edge.
    public let y: Double

    /// Creates a point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Decodes a point from a two-number JSON array; any other length throws.
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
        if !container.isAtEnd {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "A point has exactly two numbers.")
        }
    }
}

/// A rectangle on a page, in points, with the origin at the top left.
public struct PlanRect: Equatable, Decodable, Sendable {
    /// Left edge.
    public let x0: Double
    /// Top edge.
    public let y0: Double
    /// Right edge.
    public let x1: Double
    /// Bottom edge.
    public let y1: Double

    /// Creates a rectangle from its edges.
    public init(x0: Double, y0: Double, x1: Double, y1: Double) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    /// Decodes a rectangle from a four-number JSON array `[x0, y0, x1, y1]`; any other length
    /// throws.
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x0 = try container.decode(Double.self)
        y0 = try container.decode(Double.self)
        x1 = try container.decode(Double.self)
        y1 = try container.decode(Double.self)
        if !container.isAtEnd {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "A rectangle has exactly four numbers.")
        }
    }

    /// The horizontal extent.
    public var width: Double { x1 - x0 }

    /// The vertical extent.
    public var height: Double { y1 - y0 }

    /// Whether the two rectangles overlap by more than `tolerance` on both axes.
    public func intersects(_ other: PlanRect, tolerance: Double) -> Bool {
        let overlapX = min(x1, other.x1) - max(x0, other.x0)
        let overlapY = min(y1, other.y1) - max(y0, other.y0)
        return overlapX > tolerance && overlapY > tolerance
    }

    /// Whether `other` lies inside this rectangle, allowing it to stick out by `tolerance`.
    public func contains(_ other: PlanRect, tolerance: Double) -> Bool {
        other.x0 >= x0 - tolerance && other.y0 >= y0 - tolerance
            && other.x1 <= x1 + tolerance && other.y1 <= y1 + tolerance
    }
}

/// The page of the blank template a plan page is drawn on.
public enum ChromePage: Int, Sendable {
    /// The overview page.
    case overview = 0
    /// The delegated-tasks page.
    case delegated = 1
    /// A meeting-notes page.
    case meeting = 2
    /// The further-notes page.
    case furtherNotes = 3
}

/// One line of text, positioned.
public struct TextRun: Equatable, Sendable {
    /// The text of the line.
    public let text: String
    /// The font it is set in.
    public let font: FontSpec
    /// Its color.
    public let color: RGBColor
    /// The left end of the line.
    public let x: Double
    /// The baseline's y coordinate.
    public let baseline: Double
    /// The measured width of the line.
    public let width: Double
    /// The measured ascent of the font.
    public let ascent: Double
    /// The measured descent of the font.
    public let descent: Double
    /// The box the line must stay inside.
    public let container: PlanRect

    /// Creates a run.
    public init(
        text: String, font: FontSpec, color: RGBColor, x: Double, baseline: Double, width: Double,
        ascent: Double, descent: Double, container: PlanRect
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.x = x
        self.baseline = baseline
        self.width = width
        self.ascent = ascent
        self.descent = descent
        self.container = container
    }

    /// The box the glyphs occupy.
    public var bounds: PlanRect {
        PlanRect(x0: x, y0: baseline - ascent, x1: x + width, y1: baseline + descent)
    }
}

/// One thing to draw on a page, executed in order on top of the chrome page.
public enum DrawOperation: Equatable, Sendable {
    /// A filled rectangle.
    case fill(PlanRect, RGBColor)
    /// A rectangle outline.
    case stroke(PlanRect, RGBColor, lineWidth: Double)
    /// A straight line.
    case line(from: PlanPoint, to: PlanPoint, RGBColor, lineWidth: Double)
    /// A line of text.
    case text(TextRun)
    /// A tappable area that jumps to a page of the document.
    case link(PlanRect, targetPage: Int)
}

/// One page of a plan.
public struct PagePlan: Equatable, Sendable {
    /// Which page of the binder it is.
    public let key: PageKey
    /// The template page it is drawn on.
    public let chrome: ChromePage
    /// What to draw, in order.
    public var operations: [DrawOperation]

    /// Creates a page plan.
    public init(key: PageKey, chrome: ChromePage, operations: [DrawOperation]) {
        self.key = key
        self.chrome = chrome
        self.operations = operations
    }
}

/// Everything needed to draw the PDF: every glyph run already positioned.
public struct RenderPlan: Equatable, Sendable {
    /// The page width in points.
    public let pageWidth: Double
    /// The page height in points.
    public let pageHeight: Double
    /// The pages, in document order.
    public var pages: [PagePlan]
    /// To-do items that did not fit on the overview page.
    public var omittedTodoItems: [TodoItem]

    /// Creates a plan.
    public init(
        pageWidth: Double, pageHeight: Double, pages: [PagePlan], omittedTodoItems: [TodoItem]
    ) {
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.pages = pages
        self.omittedTodoItems = omittedTodoItems
    }
}
