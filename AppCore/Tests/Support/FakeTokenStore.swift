// A `TokenStore` for tests: holds tokens in memory, counts saves and deletes, and can be told to
// fail.

import AppCore
import Foundation

// `@unchecked Sendable` is safe because every access to the mutable state goes through `lock`.
final class FakeTokenStore: TokenStore, @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private var stored: OAuthTokens?
    private var saves = 0
    private var deletes = 0
    private let failsOnLoad: Bool
    private let failsOnSave: Bool
    private let failsOnDelete: Bool

    init(
        _ tokens: OAuthTokens? = nil, failsOnLoad: Bool = false, failsOnSave: Bool = false,
        failsOnDelete: Bool = false
    ) {
        stored = tokens
        self.failsOnLoad = failsOnLoad
        self.failsOnSave = failsOnSave
        self.failsOnDelete = failsOnDelete
    }

    /// The tokens held right now.
    var tokens: OAuthTokens? {
        locked { stored }
    }

    /// How many times `save` was called, including calls that failed.
    var saveCount: Int {
        locked { saves }
    }

    /// How many times `delete` was called, including calls that failed.
    var deleteCount: Int {
        locked { deletes }
    }

    func load() throws -> OAuthTokens? {
        try locked {
            if failsOnLoad {
                throw Failure()
            }
            return stored
        }
    }

    func save(_ tokens: OAuthTokens) throws {
        try locked {
            saves += 1
            if failsOnSave {
                throw Failure()
            }
            stored = tokens
        }
    }

    func delete() throws {
        try locked {
            deletes += 1
            if failsOnDelete {
                throw Failure()
            }
            stored = nil
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
