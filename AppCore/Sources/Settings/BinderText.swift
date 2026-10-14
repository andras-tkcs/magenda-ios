import Foundation

/// The only place the binder rules compare text: case, accents and spacing never matter.
public enum BinderText {
    /// `text` with whitespace normalized, accents removed and lowercased.
    public static func fold(_ text: String) -> String {
        TextFitter.normalized(text)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
    }

    /// Whether `text` begins with `phrase` as a whole word or phrase: "Lunch" matches "Lunch with
    /// Sam" and "Lunch: team" but not "Lunchtime".
    public static func startsWithPhrase(_ text: String, _ phrase: String) -> Bool {
        let folded = fold(text)
        let prefix = fold(phrase)
        guard let last = prefix.last, folded.hasPrefix(prefix) else {
            return false
        }
        guard let next = folded.dropFirst(prefix.count).first else {
            return true
        }
        return !isWordCharacter(last) || !isWordCharacter(next)
    }

    /// Whether `phrase` occurs in `text` with no letter or digit directly before or after it.
    public static func containsPhrase(_ text: String, _ phrase: String) -> Bool {
        let haystack = Array(fold(text))
        let needle = Array(fold(phrase))
        guard !needle.isEmpty, haystack.count >= needle.count else {
            return false
        }
        return (0...(haystack.count - needle.count)).contains { start in
            let end = start + needle.count
            return haystack[start..<end].elementsEqual(needle)
                && (start == 0 || !isWordCharacter(haystack[start - 1]))
                && (end == haystack.count || !isWordCharacter(haystack[end]))
        }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
