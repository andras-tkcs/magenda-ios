import Foundation

/// A summary routine the person set up: one Claude routine with its own API trigger.
public struct SummaryRoutine: Equatable, Hashable, Codable, Identifiable, Sendable {
    /// A lowercase UUID string, made when the routine is added and never changed.
    public let id: String
    /// What the checkboxes and the meeting page show.
    public var name: String
    /// Whether the binder ends with a page of its own for this routine. The routine is started for
    /// it only on a day when something was written on it.
    public var hasPage: Bool

    /// Creates a routine.
    public init(id: String, name: String, hasPage: Bool = false) {
        self.id = id
        self.name = name
        self.hasPage = hasPage
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, hasPage
    }

    /// Decodes a routine written by any build; a missing `hasPage` is false.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        hasPage = try container.decodeIfPresent(Bool.self, forKey: .hasPage) ?? false
    }

    /// Encodes the routine; `hasPage` is left out when false, so a routine without a page looks as
    /// it always did in the payloads.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        if hasPage { try container.encode(true, forKey: .hasPage) }
    }

    /// The longest name accepted, in characters.
    public static let maxNameLength = 40
    /// What Settings shows when `validatedName` returns nil.
    public static let invalidNameMessage = "Use 1 to 40 characters for the name."

    /// `text` trimmed of whitespace and newlines; nil when that is empty, longer than
    /// `maxNameLength` characters, or contains a control character.
    public static func validatedName(_ text: String) -> String? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let refused = name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        return name.isEmpty || name.count > maxNameLength || refused ? nil : name
    }

    /// Whether `id` is a lowercase UUID string: 8-4-4-4-12 characters from `0-9a-f`, with dashes
    /// between.
    public static func isValidID(_ id: String) -> Bool {
        // Checked byte by byte so no Unicode equivalence can let a look-alike character through.
        let bytes = Array(id.utf8)
        let dashes: Set<Int> = [8, 13, 18, 23]
        guard bytes.count == 36 else { return false }
        return bytes.enumerated().allSatisfy { offset, byte in
            if dashes.contains(offset) { return byte == 0x2D }
            return (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
        }
    }

    /// A new ID: `UUID().uuidString.lowercased()`.
    public static func makeID() -> String {
        UUID().uuidString.lowercased()
    }
}

/// Which summary routines a meeting asks for.
public enum SummaryRoutines {
    /// The routine IDs of the entry of `rules` whose `BinderText.fold`ed title equals the fold of
    /// `pageTitle` or of `originalTitle`; when several entries match, the one whose title sorts
    /// first. IDs are returned as stored, a repeated ID only once. Empty when no entry matches.
    public static func routineIDs(
        pageTitle: String, originalTitle: String, rules: [String: [String]]
    ) -> [String] {
        let wanted: Set<String> = [BinderText.fold(pageTitle), BinderText.fold(originalTitle)]
        guard
            let title = rules.keys.sorted().first(where: { wanted.contains(BinderText.fold($0)) }),
            let ids = rules[title]
        else {
            return []
        }
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }

    /// The routines of `available` whose ID is in `ids`, in `available`'s order. An ID that names
    /// no routine of `available` is left out.
    public static func routines(ids: [String], in available: [SummaryRoutine]) -> [SummaryRoutine] {
        let wanted = Set(ids)
        return available.filter { wanted.contains($0.id) }
    }
}
