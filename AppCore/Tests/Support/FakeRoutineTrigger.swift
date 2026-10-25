// A `RoutineFiring` for tests: records the text of every fire and answers with a session URL or
// a scripted error.

import AppCore
import Foundation

// `@unchecked Sendable` is safe because every access to the mutable state goes through `lock`.
final class FakeRoutineTrigger: RoutineFiring, @unchecked Sendable {
    let sessionURL = URL(string: "https://claude.ai/code/session_fake") ?? URL(fileURLWithPath: "/")

    private let lock = NSLock()
    private var recordedTexts: [String] = []
    private var error: (any Error)?

    /// The text of every fire so far, oldest first.
    var texts: [String] {
        lock.withLock { recordedTexts }
    }

    /// Makes `fire` throw `error` from now on; nil makes it succeed again.
    func setError(_ error: (any Error)?) {
        lock.withLock { self.error = error }
    }

    func isConfigured() -> Bool {
        true
    }

    func fire(text: String) async throws -> URL {
        try record(text)
        return sessionURL
    }

    // `NSLock.lock()` is unavailable from async code, so `fire` only locks through here.
    private func record(_ text: String) throws {
        let error = lock.withLock { () -> (any Error)? in
            recordedTexts.append(text)
            return self.error
        }
        if let error {
            throw error
        }
    }
}
