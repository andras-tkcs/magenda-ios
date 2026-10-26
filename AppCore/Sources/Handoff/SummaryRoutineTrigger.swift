import Foundation

/// Where each summary routine's URL and token are kept, by routine ID. The app uses the Keychain.
public protocol SummaryRoutineCredentialsStore: Sendable {
    /// The stored credentials of routine `id`, or `nil` when none have been entered.
    func load(id: String) throws -> RoutineCredentials?
    /// Replaces the stored credentials of routine `id`.
    func save(_ credentials: RoutineCredentials, id: String) throws
    /// Removes the stored credentials of routine `id`.
    func delete(id: String) throws
}

/// A `SummaryRoutineCredentialsStore` held in memory, for previews and tests.
public final class InMemorySummaryRoutineCredentialsStore: SummaryRoutineCredentialsStore,
    @unchecked Sendable
{
    // `@unchecked Sendable` is safe because every access to `credentials` goes through `lock`.
    private let lock = NSLock()
    private var credentials: [String: RoutineCredentials]

    /// Creates a store holding `credentials` by routine ID.
    public init(_ credentials: [String: RoutineCredentials] = [:]) {
        self.credentials = credentials
    }

    /// The stored credentials of routine `id`.
    public func load(id: String) -> RoutineCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return credentials[id]
    }

    /// Replaces the stored credentials of routine `id`.
    public func save(_ credentials: RoutineCredentials, id: String) {
        lock.lock()
        defer { lock.unlock() }
        self.credentials[id] = credentials
    }

    /// Removes the stored credentials of routine `id`.
    public func delete(id: String) {
        lock.lock()
        defer { lock.unlock() }
        credentials[id] = nil
    }
}

/// Starts a summary routine.
public protocol SummaryRoutineFiring: Sendable {
    /// Starts routine `routineID` with `text` and returns the URL of the session it started.
    func fire(text: String, routineID: String) async throws -> URL
}

/// Fires a summary routine through its own API trigger.
public struct SummaryRoutineTriggerClient: SummaryRoutineFiring {
    private let http: any HTTPClient
    private let credentials: any SummaryRoutineCredentialsStore

    /// Creates a client that sends through `http` with the routines in `credentials`.
    public init(http: any HTTPClient, credentials: any SummaryRoutineCredentialsStore) {
        self.http = http
        self.credentials = credentials
    }

    /// Sends `text` to routine `routineID` and returns the URL of the session it started. A routine
    /// whose credentials are missing or cannot be read throws `summaryNotConfigured`.
    public func fire(text: String, routineID: String) async throws -> URL {
        guard let routine = try? credentials.load(id: routineID) else {
            throw RoutineTriggerError.summaryNotConfigured
        }
        return try await RoutineTriggerClient.send(text: text, to: routine, http: http)
    }
}
