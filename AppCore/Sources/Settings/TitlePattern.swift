import Foundation

/// A meeting-title pattern: a regular expression that must match the whole title, ignoring case
/// and accents (ADR 0052).
public enum TitlePattern {
    /// The longest pattern accepted, in characters.
    public static let maxLength = 200
    /// What the rules screen shows when `validated` returns nil.
    public static let invalidMessage =
        "That isn't a valid pattern. Use a regular expression, like delivery sync [0-9]+."

    /// `text` trimmed of whitespace and newlines; nil when that is empty, longer than
    /// `maxLength`, or does not compile as a regular expression on its own.
    public static func validated(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        // The bare pattern must compile too: that means its parentheses balance, so it cannot
        // escape the wrapper `matches` puts around it.
        guard
            (try? NSRegularExpression(pattern: folded(trimmed))) != nil,
            wrapped(trimmed, options: []) != nil
        else {
            return nil
        }
        return trimmed
    }

    /// Whether `pattern` matches all of `BinderText.fold(title)`; false for a pattern that
    /// `validated` refuses.
    public static func matches(_ pattern: String, title: String) -> Bool {
        guard
            let trimmed = validated(pattern),
            let expression = wrapped(trimmed, options: [.caseInsensitive])
        else {
            return false
        }
        let text = BinderText.fold(title)
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // Accents are dropped but case is kept, so an escape like `\D` keeps its meaning.
    private static func folded(_ pattern: String) -> String {
        pattern.folding(options: [.diacriticInsensitive], locale: nil)
    }

    private static func wrapped(
        _ pattern: String, options: NSRegularExpression.Options
    ) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: "^(?:" + folded(pattern) + ")$", options: options)
    }
}
