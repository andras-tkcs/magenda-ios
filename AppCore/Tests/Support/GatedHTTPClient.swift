// An `HTTPClient` for tests that wraps another one and holds the first request to one URL until
// the test releases it, so a test can act while that request is still in flight.

import AppCore
import Foundation

actor GatedHTTPClient: HTTPClient {
    private let base: any HTTPClient
    private let gatedURL: String
    private var gatedCalls = 0
    private var isBlocked = false
    private var isReleased = false
    private var gate: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    /// Holds the first request whose URL is `gatedURL`; every other request goes straight on.
    init(_ base: any HTTPClient, gating gatedURL: String) {
        self.base = base
        self.gatedURL = gatedURL
    }

    /// Returns once the gated request is waiting for `release()`.
    func waitUntilBlocked() async {
        if isBlocked {
            return
        }
        await withCheckedContinuation { arrival = $0 }
    }

    /// Lets the gated request continue.
    func release() {
        isReleased = true
        gate?.resume()
        gate = nil
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.absoluteString == gatedURL {
            gatedCalls += 1
            if gatedCalls == 1 {
                await block()
            }
        }
        return try await base.send(request)
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
