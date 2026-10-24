// A scripted `AuthorizedHTTPSending` for tests: records every request and answers with queued
// results, in order.

import AppCore
import Foundation
import Testing

// `@unchecked Sendable` is safe because every access to the mutable state goes through `lock`.
final class FakeSender: AuthorizedHTTPSending, @unchecked Sendable {
    struct NoQueuedResult: Error {}

    private let lock = NSLock()
    private var queued: [Result<HTTPResponse, any Error>]
    private var recorded: [HTTPRequest] = []

    init(_ results: [Result<HTTPResponse, any Error>] = []) {
        queued = results
    }

    /// Every request sent so far, oldest first.
    var requests: [HTTPRequest] {
        locked { recorded }
    }

    func enqueue(_ result: Result<HTTPResponse, any Error>) {
        locked { queued.append(result) }
    }

    func enqueue(status: Int = 200, json: String, headers: [String: String] = [:]) {
        enqueue(.success(HTTPResponse(status: status, body: Data(json.utf8), headers: headers)))
    }

    func enqueue(status: Int = 200, fixture name: String) throws {
        enqueue(.success(HTTPResponse(status: status, body: try fixtureData(name))))
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let result = next(after: request) else {
            Issue.record("FakeSender has nothing queued for \(request.url)")
            throw NoQueuedResult()
        }
        return try result.get()
    }

    private func next(after request: HTTPRequest) -> Result<HTTPResponse, any Error>? {
        locked {
            recorded.append(request)
            return queued.isEmpty ? nil : queued.removeFirst()
        }
    }

    // `NSLock.lock()` is unavailable from async code, so the async `send` only locks through here.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// The bytes of the recorded response `Tests/Google/Fixtures/<name>.json`.
func fixtureData(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}
