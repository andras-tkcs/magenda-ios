import Foundation

/// Which page of the binder a page is. Stable across layouts of changed content, so handwriting
/// stays with its page.
public enum PageKey: Hashable, Sendable, Codable {
    /// The overview page.
    case overview
    /// A delegated-tasks page, by its 0-based index among the delegated pages.
    case delegated(Int)
    /// A meeting page, by event ID; empty for the blank meeting page of a day without meetings.
    case meeting(String)
    /// The further-notes page.
    case notes
    /// A page the person added, by ``ExtraPage`` ID.
    case extra(String)
    /// The page of a summary routine, by ``SummaryRoutine`` ID.
    case routine(String)

    /// The key as one string: `overview`, `delegated:<n>`, `meeting:<id>`, `notes`,
    /// `extra:<id>` or `routine:<id>`.
    public var storageString: String {
        switch self {
        case .overview: "overview"
        case .delegated(let index): "delegated:\(index)"
        case .meeting(let id): "meeting:\(id)"
        case .notes: "notes"
        case .extra(let id): "extra:\(id)"
        case .routine(let id): "routine:\(id)"
        }
    }

    /// The key `storageString` names, or nil when it names none.
    public init?(storageString: String) {
        let parts = storageString.split(
            separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let suffix = parts.count == 2 ? String(parts[1]) : nil
        switch (String(parts[0]), suffix) {
        case ("overview", nil):
            self = .overview
        case ("notes", nil):
            self = .notes
        case ("delegated", let text?):
            guard let index = Int(text), index >= 0 else { return nil }
            self = .delegated(index)
        case ("meeting", let id?):
            self = .meeting(id)
        case ("extra", let id?) where !id.isEmpty:
            self = .extra(id)
        case ("routine", let id?) where !id.isEmpty:
            self = .routine(id)
        default:
            return nil
        }
    }

    /// Decodes the single string `storageString`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let key = PageKey(storageString: text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unknown page key.")
        }
        self = key
    }

    /// Encodes the single string `storageString`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageString)
    }
}
