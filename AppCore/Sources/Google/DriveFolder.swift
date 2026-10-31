import Foundation

/// A folder in the person's Google Drive.
public struct DriveFolder: Equatable, Hashable, Identifiable, Sendable {
    /// The ID Drive's API uses for the root of My Drive.
    public static let rootID = "root"
    /// Drive's folder ID.
    public let id: String
    /// The folder's name as Drive has it.
    public let name: String

    /// Creates a folder.
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Lists and creates folders in Google Drive, for the folder picker.
public protocol DriveFolderBrowsing: Sendable {
    /// The folders directly inside `parentID` (a folder ID or `DriveFolder.rootID`), not
    /// trashed, in Drive's natural name order.
    func folders(in parentID: String) async throws -> [DriveFolder]
    /// Creates a folder called `name` inside `parentID` and returns it.
    func createFolder(named name: String, in parentID: String) async throws -> DriveFolder
}
