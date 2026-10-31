// The fixture Drive folders behind the folder picker's UI tests and previews.

import AppCore
import Testing

@Suite("Fixture Drive folders")
struct DriveFolderFixturesTests {
    @Test("My Drive holds Magenda and Work, in that order")
    func root() async throws {
        let folders = try await FixtureDriveFolders().folders(in: DriveFolder.rootID)
        #expect(folders.map(\.name) == ["Magenda", "Work"])
        #expect(folders.map(\.id) == ["fixture-folder-magenda", "fixture-folder-work"])
    }

    @Test("Work holds Meeting notes")
    func work() async throws {
        let folders = try await FixtureDriveFolders().folders(in: "fixture-folder-work")
        #expect(folders == [DriveFolder(id: "fixture-folder-notes", name: "Meeting notes")])
    }

    @Test("An unknown folder is empty")
    func unknown() async throws {
        #expect(try await FixtureDriveFolders().folders(in: "nowhere").isEmpty)
    }

    @Test("A created folder appears in its parent's list")
    func created() async throws {
        let drive = FixtureDriveFolders()
        let folder = try await drive.createFolder(named: "Q4", in: "fixture-folder-work")
        #expect(folder == DriveFolder(id: "fixture-folder-new-1", name: "Q4"))
        let listed = try await drive.folders(in: "fixture-folder-work")
        #expect(listed.last == folder)
        let next = try await drive.createFolder(named: "Q5", in: DriveFolder.rootID)
        #expect(next.id == "fixture-folder-new-2")
        let inUnknown = try await drive.createFolder(named: "Lost", in: "nowhere")
        #expect(try await drive.folders(in: "nowhere") == [inUnknown])
    }
}
