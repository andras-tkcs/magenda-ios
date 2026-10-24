// AppCore's Google Drive client: the exact requests it sends and how it reads the recorded
// responses. Every name and ID in the fixtures is made up.

import AppCore
import Foundation
import Testing

private let uploadLocation = "https://www.googleapis.com/upload/drive/v3/files?upload_id=abc"
private let pdf = Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF])

private func text(_ data: Data?) -> String {
    String(decoding: data ?? Data(), as: UTF8.self)
}

@Suite("Google Drive client")
struct GoogleDriveClientTests {
    @Test("An existing folder is found and nothing is created")
    func folderFound() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "drive-files-list")
        let id = try await GoogleDriveClient(sender: sender).folderID(named: "Magenda")
        #expect(id == "folder-magenda-01")
        #expect(sender.requests.count == 1)
        #expect(sender.requests.first?.method == .get)
    }

    @Test("The folder query escapes a quote and a backslash in the name")
    func folderQuery() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "drive-files-list")
        _ = try await GoogleDriveClient(sender: sender).folderID(named: "It's a\\b")
        let request = try #require(sender.requests.first)
        let query =
            "name = 'It\\'s a\\\\b' and mimeType = 'application/vnd.google-apps.folder'"
            + " and trashed = false"
        let components = try #require(
            URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "q" }?.value == query)
        #expect(request.url.absoluteString.contains("It%5C%27s%20a%5C%5Cb"))
        let url = request.url.absoluteString
        #expect(url.hasPrefix("https://www.googleapis.com/drive/v3/files?q="))
        #expect(url.hasSuffix("&spaces=drive&fields=files%28id%29&pageSize=10"))
    }

    @Test("A missing folder is created with the exact JSON body")
    func folderCreated() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "drive-files-list-empty")
        try sender.enqueue(fixture: "drive-file-id")
        let id = try await GoogleDriveClient(sender: sender).folderID(named: "Magenda")
        #expect(id == "file-id-01")
        let request = try #require(sender.requests.last)
        #expect(sender.requests.count == 2)
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://www.googleapis.com/drive/v3/files?fields=id")
        #expect(request.headers["Content-Type"] == "application/json; charset=UTF-8")
        #expect(
            text(request.body)
                == #"{"mimeType":"application/vnd.google-apps.folder","name":"Magenda"}"#)
    }

    @Test("A new upload posts the metadata, then puts the bytes to the Location")
    func newUpload() async throws {
        let sender = FakeSender()
        sender.enqueue(json: "{}", headers: ["location": uploadLocation])
        try sender.enqueue(fixture: "drive-file-id")
        let id = try await GoogleDriveClient(sender: sender)
            .uploadPDF(pdf, name: "Magenda 2026-10-24.pdf", folderID: "folder-1", replacing: nil)
        #expect(id == "file-id-01")
        let initiation = sender.requests[0]
        #expect(initiation.method == .post)
        #expect(
            initiation.url.absoluteString
                == "https://www.googleapis.com/upload/drive/v3/files"
                + "?uploadType=resumable&fields=id")
        #expect(initiation.headers["Content-Type"] == "application/json; charset=UTF-8")
        #expect(initiation.headers["X-Upload-Content-Type"] == "application/pdf")
        #expect(initiation.headers["X-Upload-Content-Length"] == "6")
        #expect(
            text(initiation.body)
                == #"{"mimeType":"application/pdf","name":"Magenda 2026-10-24.pdf","#
                + #""parents":["folder-1"]}"#
        )
        let upload = sender.requests[1]
        #expect(upload.method == .put)
        #expect(upload.url.absoluteString == uploadLocation)
        #expect(upload.body == pdf)
        #expect(upload.headers["Content-Type"] == "application/pdf")
        #expect(upload.timeout == 300)
    }

    @Test("A replacement patches the file by its ID with an empty body")
    func replacement() async throws {
        let sender = FakeSender()
        sender.enqueue(json: "{}", headers: ["Location": uploadLocation])
        try sender.enqueue(fixture: "drive-file-id")
        _ = try await GoogleDriveClient(sender: sender)
            .uploadPDF(pdf, name: "n.pdf", folderID: "f", replacing: "old#id")
        let initiation = sender.requests[0]
        #expect(initiation.method == .patch)
        #expect(
            initiation.url.absoluteString
                == "https://www.googleapis.com/upload/drive/v3/files/old%23id"
                + "?uploadType=resumable&fields=id")
        #expect(text(initiation.body) == "{}")
        #expect(initiation.headers["X-Upload-Content-Length"] == "6")
        #expect(sender.requests[1].method == .put)
    }

    @Test("A replacement whose file is gone creates a new one")
    func replacementNotFound() async throws {
        let sender = FakeSender()
        sender.enqueue(.failure(GoogleAPIError.notFound))
        sender.enqueue(json: "{}", headers: ["Location": uploadLocation])
        try sender.enqueue(fixture: "drive-file-id")
        let id = try await GoogleDriveClient(sender: sender)
            .uploadPDF(pdf, name: "n.pdf", folderID: "f", replacing: "gone")
        #expect(id == "file-id-01")
        #expect(sender.requests.map(\.method) == [.patch, .post, .put])
        #expect(text(sender.requests[1].body).contains(#""parents":["f"]"#))
    }

    @Test("A Location on another host, another scheme or none is unexpected")
    func badLocation() async throws {
        let locations: [[String: String]] = [
            ["Location": "https://evil.example.com/upload"],
            ["Location": "http://www.googleapis.com/upload"],
            [:],
        ]
        for headers in locations {
            let sender = FakeSender()
            sender.enqueue(json: "{}", headers: headers)
            await #expect(throws: GoogleAPIError.unexpectedResponse) {
                try await GoogleDriveClient(sender: sender)
                    .uploadPDF(pdf, name: "n.pdf", folderID: "f", replacing: nil)
            }
            #expect(sender.requests.count == 1)
        }
    }

    @Test("A Doc is created with the exact multipart body")
    func createDoc() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "drive-file-id")
        let id = try await GoogleDriveClient(sender: sender)
            .createDoc(
                name: "Magenda 2026-10-24 notes", folderID: "folder-1", text: "Line one\nLine two")
        #expect(id == "file-id-01")
        let request = try #require(sender.requests.first)
        #expect(request.method == .post)
        #expect(
            request.url.absoluteString
                == "https://www.googleapis.com/upload/drive/v3/files"
                + "?uploadType=multipart&fields=id")
        #expect(
            request.headers["Content-Type"] == "multipart/related; boundary=magenda-part-boundary")
        let expected =
            "--magenda-part-boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
            + #"{"mimeType":"application/vnd.google-apps.document","#
            + #""name":"Magenda 2026-10-24 notes","parents":["folder-1"]}"#
            + "\r\n--magenda-part-boundary\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n"
            + "Line one\nLine two\r\n--magenda-part-boundary--\r\n"
        #expect(request.body == Data(expected.utf8))
    }

    @Test("The export asks for plain text and strips a leading byte order mark")
    func export() async throws {
        let sender = FakeSender()
        sender.enqueue(
            .success(HTTPResponse(status: 200, body: Data("\u{FEFF}Hello".utf8))))
        let result = try await GoogleDriveClient(sender: sender).exportText(ofDoc: "doc/1")
        #expect(result == "Hello")
        let request = try #require(sender.requests.first)
        #expect(request.method == .get)
        #expect(
            request.url.absoluteString
                == "https://www.googleapis.com/drive/v3/files/doc/1/export"
                + "?mimeType=text%2Fplain")
    }

    @Test("An export without a byte order mark is returned as it is")
    func exportPlain() async throws {
        let sender = FakeSender()
        sender.enqueue(.success(HTTPResponse(status: 200, body: Data("Hello".utf8))))
        #expect(try await GoogleDriveClient(sender: sender).exportText(ofDoc: "d") == "Hello")
    }

    @Test("An export that is not UTF-8 is unexpected")
    func exportNotUTF8() async throws {
        let sender = FakeSender()
        sender.enqueue(.success(HTTPResponse(status: 200, body: Data([0xFF, 0xFE, 0x00]))))
        await #expect(throws: GoogleAPIError.unexpectedResponse) {
            try await GoogleDriveClient(sender: sender).exportText(ofDoc: "d")
        }
    }

    @Test("A body that does not decode is unexpected")
    func malformed() async throws {
        let sender = FakeSender()
        sender.enqueue(json: "not json")
        await #expect(throws: GoogleAPIError.unexpectedResponse) {
            try await GoogleDriveClient(sender: sender).folderID(named: "Magenda")
        }
        let uploadSender = FakeSender()
        uploadSender.enqueue(json: "{}", headers: ["Location": uploadLocation])
        uploadSender.enqueue(json: "{\"name\":1}")
        await #expect(throws: GoogleAPIError.unexpectedResponse) {
            try await GoogleDriveClient(sender: uploadSender)
                .uploadPDF(pdf, name: "n", folderID: "f", replacing: nil)
        }
    }
}
