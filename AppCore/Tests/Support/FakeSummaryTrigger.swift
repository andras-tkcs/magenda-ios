// A `SummaryRoutineFiring` for tests: records the text and routine ID of every fire and answers
// with a session URL, or throws for the routine IDs it was told to fail.

import AppCore
import Foundation

// `@unchecked Sendable` is safe because every access to the mutable state goes through `lock`.
final class FakeSummaryTrigger: SummaryRoutineFiring, @unchecked Sendable {
    struct Fire: Equatable {
        let text: String
        let routineID: String
    }

    struct Failure: Error, Equatable {}

    let sessionURL = URL(string: "https://claude.ai/code/session_fake") ?? URL(fileURLWithPath: "/")

    private let lock = NSLock()
    private var recorded: [Fire] = []
    private var failing: Set<String> = []

    /// Every fire so far, oldest first, including the ones that threw.
    var fires: [Fire] {
        lock.withLock { recorded }
    }

    /// Makes `fire` throw `Failure` for exactly the routine IDs in `ids` from now on.
    func setFailing(_ ids: Set<String>) {
        lock.withLock { failing = ids }
    }

    func fire(text: String, routineID: String) async throws -> URL {
        try record(text, routineID)
        return sessionURL
    }

    // `NSLock.lock()` is unavailable from async code, so `fire` only locks through here.
    private func record(_ text: String, _ routineID: String) throws {
        let fails = lock.withLock { () -> Bool in
            recorded.append(Fire(text: text, routineID: routineID))
            return failing.contains(routineID)
        }
        if fails {
            throw Failure()
        }
    }
}
