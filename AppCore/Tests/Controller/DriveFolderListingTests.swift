// One level of the Drive folder picker, against a scripted Drive.

import AppCore
import Testing

private struct Unrelated: Error {}

@MainActor
@Suite("Drive folder listing")
struct DriveFolderListingTests {
    private let alpha = DriveFolder(id: "folder-alpha-01", name: "Alpha")

    @Test("My Drive is listed through the root ID")
    func root() async {
        let drive = FakeDriveFolders()
        await drive.setFolders([alpha])
        let listing = DriveFolderListing(parent: nil, browser: drive)
        #expect(listing.state == .loading)
        await listing.load()
        #expect(listing.state == .loaded([alpha]))
        #expect(await drive.calls == [.folders(in: "root")])
    }

    @Test("A folder is listed through its own ID")
    func parent() async {
        let drive = FakeDriveFolders()
        let listing = DriveFolderListing(parent: alpha, browser: drive)
        await listing.load()
        #expect(listing.state == .loaded([]))
        #expect(await drive.calls == [.folders(in: "folder-alpha-01")])
    }

    @Test("A Google error fails with its message; any other error with the unexpected one")
    func failures() async {
        let drive = FakeDriveFolders()
        await drive.setListError(GoogleAPIError.network)
        let listing = DriveFolderListing(parent: nil, browser: drive)
        await listing.load()
        #expect(listing.state == .failed(GoogleAPIError.network.userMessage))
        await drive.setListError(Unrelated())
        await listing.load()
        #expect(listing.state == .failed(GoogleAPIError.unexpectedResponse.userMessage))
    }

    @Test("Loading again after a failure can succeed")
    func retry() async {
        let drive = FakeDriveFolders()
        await drive.setListError(GoogleAPIError.network)
        let listing = DriveFolderListing(parent: nil, browser: drive)
        await listing.load()
        await drive.setListError(nil)
        await drive.setFolders([alpha])
        await listing.load()
        #expect(listing.state == .loaded([alpha]))
    }

    @Test("An invalid name is refused without asking Drive")
    func invalidName() async {
        let drive = FakeDriveFolders()
        let listing = DriveFolderListing(parent: nil, browser: drive)
        #expect(await listing.createFolder(named: "a/b") == nil)
        #expect(listing.createError == DriveFolderName.invalidMessage)
        #expect(await drive.calls.isEmpty)
    }

    @Test("A valid name is trimmed, sent with the parent's ID and returned")
    func created() async {
        let drive = FakeDriveFolders()
        await drive.setCreated(alpha)
        let listing = DriveFolderListing(parent: alpha, browser: drive)
        _ = await listing.createFolder(named: "a/b")
        #expect(listing.createError != nil)
        #expect(await listing.createFolder(named: "  Q4  ") == alpha)
        #expect(listing.createError == nil)
        #expect(await drive.calls == [.createFolder(named: "Q4", in: "folder-alpha-01")])
    }

    @Test("A Drive error sets the create error")
    func createFails() async {
        let drive = FakeDriveFolders()
        await drive.setCreateError(GoogleAPIError.forbidden)
        let listing = DriveFolderListing(parent: nil, browser: drive)
        #expect(await listing.createFolder(named: "Q4") == nil)
        #expect(listing.createError == GoogleAPIError.forbidden.userMessage)
    }
}
