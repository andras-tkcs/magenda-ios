// A `DriveFiling` for tests: records every call, answers with a scripted result or error per
// method, and can hold `uploadPDF` until the test releases it.

import AppCore
import Foundation

actor FakeDrive: DriveFiling {
    enum Method: Hashable, Sendable {
        case folderID, uploadPDF, createDoc, exportText
    }

    enum Call: Equatable, Sendable {
        case folderID(named: String)
        case uploadPDF(data: Data, name: String, folderID: String, replacing: String?)
        case createDoc(name: String, folderID: String, text: String)
        case exportText(docID: String)
    }

    /// Every call so far, oldest first.
    private(set) var calls: [Call] = []

    private var folder = "folder-1"
    private var file = "file-1"
    private var doc = "doc-1"
    private var exported = DocStatus.initialDocText
    private var errors: [Method: any Error] = [:]
    private let holdsUpload: Bool
    private var isBlocked = false
    private var isReleased = false
    private var gate: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    /// With `holdingUpload`, the first `uploadPDF` waits for `release()`.
    init(holdingUpload: Bool = false) {
        holdsUpload = holdingUpload
    }

    /// Makes `method` throw `error` from now on; nil makes it succeed again.
    func setError(_ error: (any Error)?, for method: Method) {
        errors[method] = error
    }

    /// The text `exportText` answers with from now on.
    func setExportedText(_ text: String) {
        exported = text
    }

    /// Returns once the held upload is waiting for `release()`.
    func waitUntilBlocked() async {
        if isBlocked {
            return
        }
        await withCheckedContinuation { arrival = $0 }
    }

    /// Lets the held upload continue.
    func release() {
        isReleased = true
        gate?.resume()
        gate = nil
    }

    func folderID(named name: String) async throws -> String {
        calls.append(.folderID(named: name))
        try fail(.folderID)
        return folder
    }

    func uploadPDF(_ data: Data, name: String, folderID: String, replacing fileID: String?)
        async throws -> String
    {
        calls.append(
            .uploadPDF(data: data, name: name, folderID: folderID, replacing: fileID))
        if holdsUpload && !isBlocked {
            await block()
        }
        try fail(.uploadPDF)
        return file
    }

    func createDoc(name: String, folderID: String, text: String) async throws -> String {
        calls.append(.createDoc(name: name, folderID: folderID, text: text))
        try fail(.createDoc)
        return doc
    }

    func exportText(ofDoc docID: String) async throws -> String {
        calls.append(.exportText(docID: docID))
        try fail(.exportText)
        return exported
    }

    private func fail(_ method: Method) throws {
        if let error = errors[method] {
            throw error
        }
    }

    private func block() async {
        isBlocked = true
        arrival?.resume()
        arrival = nil
        if isReleased {
            return
        }
        await withCheckedContinuation { gate = $0 }
    }
}
