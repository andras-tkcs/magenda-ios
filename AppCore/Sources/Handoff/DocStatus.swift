import Foundation

/// A step the end-of-day routine runs.
public enum RoutineStep: String, Codable, Sendable {
    case notes
    case approveNotes = "approve-notes"
    case approveSummary = "approve-summary"
}

/// The first line of the day's Doc, as the routine sets it.
public enum DocStatus: String, Codable, Sendable {
    case waitingForNotes
    case notesReady
    case summaryReady
    case closed
    case unknown

    /// The line Magenda writes when it creates the Doc.
    public static let initialDocText = "Status: Waiting for notes\n"

    /// Reads the first non-empty line of `text` (a leading U+FEFF and surrounding whitespace
    /// ignored). It must start with `Status:` (ASCII case-insensitive). The rest, trimmed, is
    /// compared case-insensitively with `Waiting for notes`, `Notes ready for review`,
    /// `Summary ready for review` and `Closed`. Anything else is `.unknown`.
    public static func parse(_ text: String) -> DocStatus {
        let unmarked = text.drop { $0 == "\u{FEFF}" }
        let lines = unmarked.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let line = lines.first(where: { !$0.isEmpty }),
            line.prefix(7).lowercased() == "status:"
        else { return .unknown }
        switch line.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "waiting for notes": return .waitingForNotes
        case "notes ready for review": return .notesReady
        case "summary ready for review": return .summaryReady
        case "closed": return .closed
        default: return .unknown
        }
    }
}
