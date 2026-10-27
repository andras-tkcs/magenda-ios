import Foundation

/// The name of the Google Drive folder finished days are uploaded to.
public enum DriveFolderName {
    /// The folder a fresh install uploads to.
    public static let `default` = "Magenda"
    /// The longest name accepted, in characters.
    public static let maxLength = 100
    /// What Settings shows when `validated` returns nil.
    public static let invalidMessage = "Use 1 to 100 characters, without a slash."

    /// `text` trimmed of whitespace and newlines; nil when that is empty, longer than
    /// `maxLength` characters, or contains "/", "\" or a control character.
    public static func validated(_ text: String) -> String? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let refused = name.unicodeScalars.contains {
            $0 == "/" || $0 == "\\" || CharacterSet.controlCharacters.contains($0)
        }
        return name.isEmpty || name.count > maxLength || refused ? nil : name
    }
}
