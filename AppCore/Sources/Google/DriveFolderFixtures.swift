import Foundation

/// Drive folders for UI tests and previews: My Drive holds `Magenda` and `Work`, and `Work`
/// holds `Meeting notes`. Created folders are kept in memory.
public actor FixtureDriveFolders: DriveFolderBrowsing {
    private var children: [String: [DriveFolder]] = [
        DriveFolder.rootID: [
            DriveFolder(id: "fixture-folder-magenda", name: "Magenda"),
            DriveFolder(id: "fixture-folder-work", name: "Work"),
        ],
        "fixture-folder-work": [DriveFolder(id: "fixture-folder-notes", name: "Meeting notes")],
    ]
    private var created = 0

    /// Creates the fixture folders.
    public init() {}

    /// The folders in `parentID`; none for a folder the fixture doesn't know.
    public func folders(in parentID: String) async throws -> [DriveFolder] {
        children[parentID] ?? []
    }

    /// Appends `fixture-folder-new-<n>` to `parentID` and returns it.
    public func createFolder(named name: String, in parentID: String) async throws -> DriveFolder {
        created += 1
        let folder = DriveFolder(id: "fixture-folder-new-\(created)", name: name)
        children[parentID, default: []].append(folder)
        return folder
    }
}
