import Foundation

/// The data-protection class of the files that hold the person's handwriting and agendas:
/// unreadable while the device is locked, except for a file already open, so a save that starts
/// as the iPad locks still finishes (ADR 0022).
enum FileProtection {
    /// The option that gives a written file this class.
    static let writingOptions: Data.WritingOptions = .completeFileProtectionUnlessOpen
    /// The attributes that give a file or folder this class.
    static var attributes: [FileAttributeKey: Any] {
        [.protectionKey: FileProtectionType.completeUnlessOpen]
    }
}
