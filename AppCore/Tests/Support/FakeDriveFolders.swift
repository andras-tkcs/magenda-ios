// A `DriveFolderBrowsing` for tests: records every call and answers with a scripted list,
// created folder or error per method.

import AppCore
import Foundation

actor FakeDriveFolders: DriveFolderBrowsing {
    enum Call: Equatable {
        case folders(in: String)
        case createFolder(named: String, in: String)
    }

    /// Every call so far, oldest first.
    private(set) var calls: [Call] = []

    private var listed: [DriveFolder] = []
    private var created = DriveFolder(id: "folder-created-01", name: "Created")
    private var listError: (any Error)?
    private var createError: (any Error)?

    /// The folders `folders(in:)` answers with from now on.
    func setFolders(_ folders: [DriveFolder]) {
        listed = folders
    }

    /// The folder `createFolder` answers with from now on.
    func setCreated(_ folder: DriveFolder) {
        created = folder
    }

    /// Makes `folders(in:)` throw `error` from now on; nil makes it succeed again.
    func setListError(_ error: (any Error)?) {
        listError = error
    }

    /// Makes `createFolder` throw `error` from now on; nil makes it succeed again.
    func setCreateError(_ error: (any Error)?) {
        createError = error
    }

    func folders(in parentID: String) async throws -> [DriveFolder] {
        calls.append(.folders(in: parentID))
        if let listError {
            throw listError
        }
        return listed
    }

    func createFolder(named name: String, in parentID: String) async throws -> DriveFolder {
        calls.append(.createFolder(named: name, in: parentID))
        if let createError {
            throw createError
        }
        return created
    }
}
