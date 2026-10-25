import Foundation

/// Which summary skill a meeting asks for.
public enum SummarySkill {
    /// Whether `name` can be a skill name: 1…64 characters, the first an ASCII letter or digit,
    /// the rest ASCII letters, digits, "-", "_", ":" or ".".
    public static func isValidName(_ name: String) -> Bool {
        let scalars = Array(name.unicodeScalars)
        guard (1...64).contains(scalars.count), let first = scalars.first else {
            return false
        }
        func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)
        }
        let punctuation = "-_:.".unicodeScalars
        return isAlphanumeric(first)
            && scalars.dropFirst().allSatisfy { isAlphanumeric($0) || punctuation.contains($0) }
    }

    /// The skill whose entry's `BinderText.fold`ed title equals the fold of `pageTitle` or of
    /// `originalTitle`; when several match, the one whose title sorts first. `nil` when none does
    /// or the matching skill is not a valid name.
    public static func skill(
        pageTitle: String, originalTitle: String, skills: [String: String]
    ) -> String? {
        let wanted: Set<String> = [BinderText.fold(pageTitle), BinderText.fold(originalTitle)]
        guard
            let title = skills.keys.sorted().first(where: { wanted.contains(BinderText.fold($0)) }),
            let name = skills[title], isValidName(name)
        else {
            return nil
        }
        return name
    }
}
