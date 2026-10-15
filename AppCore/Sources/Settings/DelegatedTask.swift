import Foundation

/// One task from the delegated list, parsed from its "Owner: Task" title and its notes.
public struct DelegatedTask: Equatable, Sendable {
    /// Who the task was delegated to, empty when the title has no owner.
    public var owner: String
    /// What was delegated.
    public var text: String
    /// How often it is checked in on.
    public var cadence: Cadence
    /// The last two log lines, in their original order.
    public var status: [String]
    /// What was missing from the task, or nil when it is well formed.
    public var warning: String?

    private static let ownerWarning = "No “Owner: Task” title — shown without an owner."
    private static let cadenceWarning =
        "No #daily, #weekly or #monthly on the first line — shown as Daily."

    /// Parses a task title and notes.
    public static func parse(title: String?, notes: String?) -> DelegatedTask {
        var warnings: [String] = []

        let fullTitle = TextFitter.normalized(title ?? "")
        let parts = fullTitle.split(
            separator: ":", maxSplits: 1, omittingEmptySubsequences: false
        ).map { $0.trimmingCharacters(in: .whitespaces) }
        var owner = ""
        var text = fullTitle
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            owner = parts[0]
            text = parts[1]
        } else {
            warnings.append(ownerWarning)
        }

        var lines = (notes ?? "").split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let first = BinderText.fold(lines.first ?? "")
        var cadence = Cadence.daily
        if let marked = Cadence.allCases.first(where: { "#" + $0.rawValue == first }) {
            cadence = marked
            lines.removeFirst()
        } else {
            warnings.append(cadenceWarning)
        }

        return DelegatedTask(
            owner: owner, text: text, cadence: cadence,
            status: Array(lines.suffix(2)),
            warning: warnings.isEmpty ? nil : warnings.joined(separator: " "))
    }
}
