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

    /// The Drive folder ID in `text`, which is a folder link such as
    /// `https://drive.google.com/drive/folders/<id>` or the bare ID; nil when it is neither.
    public static func folderID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if let url = URL(string: trimmed), url.host?.hasSuffix("drive.google.com") == true {
            let parts = url.pathComponents
            guard let index = parts.lastIndex(of: "folders"), parts.indices.contains(index + 1)
            else { return nil }
            candidate = parts[index + 1]
        } else {
            candidate = trimmed
        }
        let isID =
            candidate.count >= 10
            && candidate.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_"
            }
        return isID ? candidate : nil
    }
}
