import Foundation

/// What the end-of-day hand-off needs from Google Drive.
public protocol DriveFiling: Sendable {
    /// The ID of the folder called `name`, created when none exists.
    func folderID(named name: String) async throws -> String
    /// Uploads `data` as a PDF into `folderID` and returns its ID. With `fileID` the file is
    /// replaced in place; when it no longer exists a new file is created.
    func uploadPDF(_ data: Data, name: String, folderID: String, replacing fileID: String?)
        async throws -> String
    /// Creates a Google Doc from `text` in `folderID` and returns its ID.
    func createDoc(name: String, folderID: String, text: String) async throws -> String
    /// The plain text of the Google Doc `docID`.
    func exportText(ofDoc docID: String) async throws -> String
}

/// Files, uploads and exports on Google Drive.
public struct GoogleDriveClient: DriveFiling {
    private static let folderType = "application/vnd.google-apps.folder"
    private static let docType = "application/vnd.google-apps.document"
    private static let boundary = "magenda-part-boundary"
    private static let jsonType = "application/json; charset=UTF-8"

    private let sender: any AuthorizedHTTPSending

    /// Creates a client that sends through `sender`.
    public init(sender: any AuthorizedHTTPSending) {
        self.sender = sender
    }

    /// The first folder called `name`, or a new one when none exists.
    public func folderID(named name: String) async throws -> String {
        let escapedName = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let query =
            "name = '\(escapedName)' and mimeType = '\(Self.folderType)' and trashed = false"
        let listURL = GoogleAPI.withQuery(
            [
                (key: "q", value: query), (key: "spaces", value: "drive"),
                (key: "fields", value: "files(id)"), (key: "pageSize", value: "10"),
            ], on: Self.filesURL)
        let listed = try await sender.send(
            HTTPRequest(method: .get, url: listURL, headers: [:], body: nil))
        if let id = try decode(FilesPage.self, listed).files.first?.id {
            return id
        }
        let body = encode(["mimeType": Self.folderType, "name": name])
        let created = try await sender.send(
            HTTPRequest(
                method: .post,
                url: GoogleAPI.withQuery([(key: "fields", value: "id")], on: Self.filesURL),
                headers: ["Content-Type": Self.jsonType], body: body))
        return try decode(FileID.self, created).id
    }

    /// Uploads `data` as a PDF in one resumable `PUT`; a gone `fileID` falls back to a new file.
    public func uploadPDF(
        _ data: Data, name: String, folderID: String, replacing fileID: String?
    ) async throws -> String {
        let creation = encode(
            Metadata(mimeType: "application/pdf", name: name, parents: [folderID]))
        let location: URL
        if let fileID {
            do {
                location = try await initiateUpload(
                    method: .patch, url: Self.uploadURL.appending(path: fileID),
                    body: Data("{}".utf8), length: data.count)
            } catch GoogleAPIError.notFound {
                location = try await initiateUpload(
                    method: .post, url: Self.uploadURL, body: creation, length: data.count)
            }
        } else {
            location = try await initiateUpload(
                method: .post, url: Self.uploadURL, body: creation, length: data.count)
        }
        let uploaded = try await sender.send(
            HTTPRequest(
                method: .put, url: location, headers: ["Content-Type": "application/pdf"],
                body: data, timeout: 300))
        return try decode(FileID.self, uploaded).id
    }

    /// Creates a Google Doc from `text` with one multipart request.
    public func createDoc(name: String, folderID: String, text: String) async throws -> String {
        let metadata = encode(
            Metadata(mimeType: Self.docType, name: name, parents: [folderID]))
        let delimiter = "--\(Self.boundary)"
        var body = Data("\(delimiter)\r\nContent-Type: \(Self.jsonType)\r\n\r\n".utf8)
        body.append(metadata)
        let textHeader = "\r\n\(delimiter)\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n"
        body.append(Data("\(textHeader)\(text)\r\n\(delimiter)--\r\n".utf8))
        let response = try await sender.send(
            HTTPRequest(
                method: .post,
                url: GoogleAPI.withQuery(
                    [(key: "uploadType", value: "multipart"), (key: "fields", value: "id")],
                    on: Self.uploadURL),
                headers: ["Content-Type": "multipart/related; boundary=\(Self.boundary)"],
                body: body))
        return try decode(FileID.self, response).id
    }

    /// The Doc as plain text, without the byte order mark Drive puts first.
    public func exportText(ofDoc docID: String) async throws -> String {
        let url = GoogleAPI.withQuery(
            [(key: "mimeType", value: "text/plain")],
            on: Self.filesURL.appending(path: docID).appending(path: "export"))
        let response = try await sender.send(
            HTTPRequest(method: .get, url: url, headers: [:], body: nil))
        guard let text = String(data: response.body, encoding: .utf8) else {
            throw GoogleAPIError.unexpectedResponse
        }
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    private static var filesURL: URL {
        GoogleAPI.url(host: "www.googleapis.com", path: "drive/v3/files")
    }

    private static var uploadURL: URL {
        GoogleAPI.url(host: "www.googleapis.com", path: "upload/drive/v3/files")
    }

    /// Starts a resumable upload and returns the URL to `PUT` the bytes to.
    private func initiateUpload(method: HTTPMethod, url: URL, body: Data, length: Int)
        async throws -> URL
    {
        let response = try await sender.send(
            HTTPRequest(
                method: method,
                url: GoogleAPI.withQuery(
                    [(key: "uploadType", value: "resumable"), (key: "fields", value: "id")],
                    on: url),
                headers: [
                    "Content-Type": Self.jsonType,
                    "X-Upload-Content-Type": "application/pdf",
                    "X-Upload-Content-Length": String(length),
                ], body: body))
        guard let header = response.header("Location"),
            let location = URL(string: header),
            location.scheme == "https", location.host == "www.googleapis.com"
        else {
            throw GoogleAPIError.unexpectedResponse
        }
        return location
    }

    private func decode<T: Decodable>(_ type: T.Type, _ response: HTTPResponse) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw GoogleAPIError.unexpectedResponse
        }
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Encoding plain strings and arrays cannot fail; `compactMap` keeps that impossible
        // failure from needing a branch of its own.
        return [try? encoder.encode(value)].compactMap { $0 }.reduce(Data()) { $1 }
    }
}

private struct Metadata: Encodable {
    let mimeType: String
    let name: String
    let parents: [String]
}

private struct FilesPage: Decodable {
    let files: [FileID]
}

private struct FileID: Decodable {
    let id: String
}
