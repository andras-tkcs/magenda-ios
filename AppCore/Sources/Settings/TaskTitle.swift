import Foundation

/// The rules that recognise a to-do task that is about a discussion.
public enum TaskTitle {
    private static let discussionPattern = #"^(.+?)\s*[-–—:]\s*(?:to be discussed|tbd)\s*$"#

    /// Whether the title ends with "to be discussed" or holds "TBD" as a word.
    public static func isDiscussion(_ title: String) -> Bool {
        BinderText.fold(title).hasSuffix("to be discussed")
            || BinderText.containsPhrase(title, "tbd")
    }

    /// The person in "Name – to be discussed" or "Name: TBD", or nil when there is none.
    public static func discussionName(_ title: String) -> String? {
        let normalized = TextFitter.normalized(title)
        // The pattern is anchored, so a match is replaced by its first group and a non-match is
        // returned unchanged.
        let name = normalized.replacingOccurrences(
            of: discussionPattern, with: "$1", options: [.regularExpression, .caseInsensitive])
        return name == normalized ? nil : name.trimmingCharacters(in: .whitespaces)
    }
}
