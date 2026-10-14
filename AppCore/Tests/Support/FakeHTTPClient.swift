// A scripted `HTTPClient` for tests: records every request and answers with queued results, in
// order.

import AppCore
import Foundation
import Testing

// `@unchecked Sendable` is safe because every access to the mutable state goes through `lock`.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
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

    func enqueue(status: Int, json: String) {
        enqueue(.success(HTTPResponse(status: status, body: Data(json.utf8))))
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let result = next(after: request) else {
            Issue.record("FakeHTTPClient has nothing queued for \(request.url)")
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
