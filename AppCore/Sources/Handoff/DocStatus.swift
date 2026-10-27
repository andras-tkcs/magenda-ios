import Foundation

/// A step the end-of-day routine runs.
public enum RoutineStep: String, Codable, Sendable {
    case notes
    case close
}

/// The first line of the day's Doc, as the routine sets it.
public enum DocStatus: String, Codable, Sendable {
    case waitingForNotes
    case notesReady
    case closed
    case unknown

    /// Decodes the raw status; a value this build does not know reads as `.unknown`.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DocStatus(rawValue: raw) ?? .unknown
    }

    /// The line Magenda writes when it creates the Doc.
    public static let initialDocText = "Status: Waiting for notes\n"

    /// Reads the first non-empty line of `text` (a leading U+FEFF and surrounding whitespace
    /// ignored). It must start with `Status:` (ASCII case-insensitive). The rest, trimmed, is
    /// compared case-insensitively with `Waiting for notes`, `Notes ready for review` and
    /// `Closed`. Anything else is `.unknown`.
    public static func parse(_ text: String) -> DocStatus {
        guard let line = trimmedLines(of: text).first(where: { !$0.isEmpty }),
            line.prefix(7).lowercased() == "status:"
        else { return .unknown }
        switch line.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "waiting for notes": return .waitingForNotes
        case "notes ready for review": return .notesReady
        case "closed": return .closed
        default: return .unknown
        }
    }

    /// The summary markers in `text`: every line, other than the first non-empty one, that after
    /// trimming whitespace is exactly `Summary ready:`, one ASCII space, a routine ID, one ASCII
    /// space and a page of ASCII digits `[1-9][0-9]{0,3}` (the label and the ID compared ASCII
    /// case-insensitively, the ID valid per `SummaryRoutine.isValidID` once lowercased). Each is
    /// returned as `"<lowercased ID> <page>"`, without duplicates, in order. A leading U+FEFF is
    /// ignored; the Doc's first non-empty line is the status line and is never a marker.
    public static func summaryMarkers(in text: String) -> [String] {
        var seen = Set<String>()
        return trimmedLines(of: text).drop { $0.isEmpty }.dropFirst().compactMap(marker(in:))
            .filter { seen.insert($0).inserted }
    }

    // `text`'s lines, each trimmed of whitespace, after a leading U+FEFF.
    private static func trimmedLines(of text: String) -> [String] {
        text.drop { $0 == "\u{FEFF}" }.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    // `"<lowercased ID> <page>"` when `line` is exactly a marker, else nil. Checked byte by byte.
    private static func marker(in line: String) -> String? {
        let label = Array("summary ready:".utf8)
        let space = UInt8(ascii: " ")
        let bytes = Array(line.utf8).map { (0x41...0x5A).contains($0) ? $0 + 0x20 : $0 }
        let idStart = label.count + 1
        let pageStart = idStart + 37
        guard bytes.count > pageStart, bytes.count <= pageStart + 4, bytes.starts(with: label),
            bytes[label.count] == space, bytes[pageStart - 1] == space
        else { return nil }
        let id = String(decoding: bytes[idStart..<(pageStart - 1)], as: UTF8.self)
        let page = bytes[pageStart...]
        guard SummaryRoutine.isValidID(id), page.allSatisfy({ (0x30...0x39).contains($0) }),
            page[pageStart] != 0x30
        else { return nil }
        return id + " " + String(decoding: page, as: UTF8.self)
    }
}
