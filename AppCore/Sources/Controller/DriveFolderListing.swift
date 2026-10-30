import Foundation
import Observation

/// One level of the Drive folder picker: the folders inside `parent` (My Drive when nil).
@MainActor @Observable
public final class DriveFolderListing {
    /// What the level shows.
    public enum State: Equatable, Sendable {
        case loading
        case loaded([DriveFolder])
        case failed(String)
    }

    /// The folder this level lists; nil for My Drive.
    public let parent: DriveFolder?
    /// What the level shows now.
    public private(set) var state: State = .loading
    /// Why the last `createFolder` failed; nil after a success or before any.
    public private(set) var createError: String?

    private let browser: any DriveFolderBrowsing

    /// A level listing `parent` through `browser`.
    public init(parent: DriveFolder?, browser: any DriveFolderBrowsing) {
        self.parent = parent
        self.browser = browser
    }

    /// Lists the folders: `.loading`, then `.loaded`, or `.failed` with the
    /// `GoogleAPIError`'s `userMessage` (`GoogleAPIError.unexpectedResponse`'s for any other error).
    public func load() async {
        state = .loading
        do {
            state = .loaded(try await browser.folders(in: parentID))
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// Creates a folder named `text` inside this level and returns it. When
    /// `DriveFolderName.validated(text)` is nil, sets `createError` to
    /// `DriveFolderName.invalidMessage` and returns nil without asking Drive. A Drive error
    /// sets `createError` as `load` phrases it and returns nil.
    public func createFolder(named text: String) async -> DriveFolder? {
        guard let name = DriveFolderName.validated(text) else {
            createError = DriveFolderName.invalidMessage
            return nil
        }
        do {
            let folder = try await browser.createFolder(named: name, in: parentID)
            createError = nil
            return folder
        } catch {
            createError = Self.message(for: error)
            return nil
        }
    }

    private var parentID: String {
        parent?.id ?? DriveFolder.rootID
    }

    private static func message(for error: any Error) -> String {
        (error as? GoogleAPIError ?? .unexpectedResponse).userMessage
    }
}
