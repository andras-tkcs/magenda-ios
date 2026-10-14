import Foundation

/// The rules that turn a calendar title into a meeting-page title.
public enum MeetingTitle {
    private static let separators: Set<Character> = [" ", "-", "–", "—", ":", "/", "|", "·"]

    /// The key a short name is saved under: every instance of a recurring meeting shares one.
    public static func key(originalTitle: String, recurringEventID: String?) -> String {
        if let recurringEventID, !recurringEventID.isEmpty {
            return "r:" + recurringEventID
        }
        return "t:" + BinderText.fold(originalTitle)
    }

    /// `title` without its leading prefixes; unchanged when nothing would be left.
    public static func stripped(_ title: String, prefixes: [String]) -> String {
        var remaining = TextFitter.normalized(title)
        while let prefix = prefixes.first(where: { BinderText.startsWithPhrase(remaining, $0) }) {
            remaining = String(
                remaining.dropFirst(TextFitter.normalized(prefix).count)
                    .drop(while: { separators.contains($0) }))
        }
        guard let first = remaining.first else {
            return TextFitter.normalized(title)
        }
        return first.isLowercase ? first.uppercased() + remaining.dropFirst() : remaining
    }

    /// The saved short name for the meeting, else the stripped title.
    public static func pageTitle(
        originalTitle: String, recurringEventID: String?, rules: BinderRules
    ) -> String {
        let saved = rules.shortNames[
            key(originalTitle: originalTitle, recurringEventID: recurringEventID)]
        let shortName = TextFitter.normalized(saved ?? "")
        return shortName.isEmpty
            ? stripped(originalTitle, prefixes: rules.titlePrefixes) : shortName
    }
}
