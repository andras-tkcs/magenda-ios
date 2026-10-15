import Foundation

/// A place on a template page where text goes.
public struct TemplateSlot: Equatable, Decodable, Sendable {
    /// The slot's identifier, such as `todo.label`.
    public let id: String
    /// The box the text goes in.
    public let rect: PlanRect
    /// Which theme color the text takes.
    public let role: TextRole
    /// The font weight.
    public let weight: FontWeight
    /// The nominal size in half points.
    public let sizeHalfPoints: Int
    /// `left` or `center`.
    public let align: String
    /// The fixed text of a static label, or nil for a dynamic slot.
    public let text: String?

    /// Creates a slot.
    public init(
        id: String, rect: PlanRect, role: TextRole, weight: FontWeight, sizeHalfPoints: Int,
        align: String, text: String?
    ) {
        self.id = id
        self.rect = rect
        self.role = role
        self.weight = weight
        self.sizeHalfPoints = sizeHalfPoints
        self.align = align
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case id, rect, role, weight, align, text
        case sizeHalfPoints = "size_half_points"
    }

    /// The nominal size in points.
    public var points: Double { Double(sizeHalfPoints) / 2 }
}

/// Why a template manifest could not be loaded.
public enum TemplateError: Error, Equatable {
    /// The manifest file is not there or cannot be read.
    case missing
    /// The manifest is there but is not valid.
    case malformed
}

/// Where every piece of text goes on the template pages.
public struct TemplateManifest: Equatable, Sendable {
    /// The page width in points.
    public let pageWidth: Double
    /// The page height in points.
    public let pageHeight: Double
    /// Slots repeated on every page.
    public let headerSlots: [TemplateSlot]
    /// Slots by page: `overview`, `delegated_shell`, `meeting_unit` and `further_notes`.
    public let pageSlots: [String: [TemplateSlot]]
    /// The top-left corner of the delegated-tasks table.
    public let delegatedTableTopLeft: PlanPoint
    /// The padding a delegated row has beyond its text, in points.
    public let delegatedRowOverhead: Double

    private struct Delegated: Decodable {
        let tableTopLeft: PlanPoint
        let rowOverheadTwips: Double

        private enum CodingKeys: String, CodingKey {
            case tableTopLeft = "table_top_left"
            case rowOverheadTwips = "row_overhead_twips"
        }
    }

    private struct Raw: Decodable {
        let pageWidth: Double
        let pageHeight: Double
        let headerSlots: [TemplateSlot]
        let pageSlots: [String: [TemplateSlot]]
        let delegated: Delegated

        private enum CodingKeys: String, CodingKey {
            case pageWidth = "page_width"
            case pageHeight = "page_height"
            case headerSlots = "header_slots"
            case pageSlots = "page_slots"
            case delegated
        }
    }

    /// Decodes the manifest's JSON; a missing key or a bad value throws `.malformed`.
    public init(data: Data) throws(TemplateError) {
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw .malformed
        }
        pageWidth = raw.pageWidth
        pageHeight = raw.pageHeight
        headerSlots = raw.headerSlots
        pageSlots = raw.pageSlots
        delegatedTableTopLeft = raw.delegated.tableTopLeft
        delegatedRowOverhead = raw.delegated.rowOverheadTwips / 20
    }

    /// Reads the manifest from `url`; a nil or unreadable URL throws `.missing`.
    public init(contentsOf url: URL?) throws(TemplateError) {
        guard let data = url.flatMap({ try? Data(contentsOf: $0) }) else {
            throw .missing
        }
        try self.init(data: data)
    }

    /// The manifest bundled with AppCore.
    public static func bundled() throws(TemplateError) -> TemplateManifest {
        try TemplateManifest(
            contentsOf: Bundle.module.url(forResource: "slots", withExtension: "json"))
    }

    /// The slot with `id`, searching the header slots and then every page's slots.
    public func slot(_ id: String) -> TemplateSlot? {
        (headerSlots + pageSlots.values.flatMap { $0 }).first { $0.id == id }
    }
}
