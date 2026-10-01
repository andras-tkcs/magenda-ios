import Foundation

/// The greeting the main screen shows for the name typed into it.
///
/// A placeholder for the app's real logic, kept here rather than in the view so that `swift test`
/// covers it on any machine (ADR 0007). Replace it once the app has logic of its own.
public enum Greeting {
    /// Names longer than this are cut, so a pasted paragraph cannot push the layout around.
    public static let maximumNameLength = 40

    /// The greeting for `name`, or a generic one when `name` is blank.
    public static func message(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Hello!"
        }
        return "Hello, \(trimmed.prefix(maximumNameLength))!"
    }
}
