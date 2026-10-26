import Foundation

/// The end-of-day routine's API trigger, as entered in Settings.
public struct RoutineCredentials: Codable, Equatable, Sendable {
    /// `trig_` followed by 1…64 ASCII letters or digits.
    public let triggerID: String
    /// `sk-ant-oat01-` followed by 1…500 characters of `[A-Za-z0-9_-]`.
    public let token: String

    private static let host = "api.anthropic.com"
    private static let pathPrefix = "/v1/claude_code/routines/"
    private static let pathSuffix = "/fire"
    private static let triggerPrefix = Array("trig_".utf8)
    private static let tokenPrefix = Array("sk-ant-oat01-".utf8)

    /// Creates credentials from the fire URL and token as pasted, each trimmed of whitespace.
    /// Returns `nil` unless the URL is `https://api.anthropic.com/v1/claude_code/routines/<trigger
    /// ID>/fire` with nothing else, and the token has the routine token's shape.
    public init?(fireURL: String, token: String) {
        let trimmedURL = fireURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedURL),
            components.scheme == "https", components.host == Self.host, components.port == nil,
            components.query == nil, components.fragment == nil, components.user == nil,
            components.password == nil,
            components.path.hasPrefix(Self.pathPrefix), components.path.hasSuffix(Self.pathSuffix),
            components.path.count > Self.pathPrefix.count + Self.pathSuffix.count
        else {
            return nil
        }
        let triggerID = String(
            components.path.dropFirst(Self.pathPrefix.count).dropLast(Self.pathSuffix.count))
        guard Self.isValidTriggerID(triggerID), Self.isValidToken(trimmedToken) else {
            return nil
        }
        self.triggerID = triggerID
        self.token = trimmedToken
    }

    /// `https://api.anthropic.com/v1/claude_code/routines/<triggerID>/fire`.
    public var fireURL: URL {
        GoogleAPI.url(host: Self.host, path: Self.pathPrefix + triggerID + Self.pathSuffix)
    }

    // Checked byte by byte so no Unicode equivalence can let a look-alike character through.
    private static func isValidTriggerID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        let suffix = bytes.dropFirst(triggerPrefix.count)
        return bytes.starts(with: triggerPrefix) && (1...64).contains(suffix.count)
            && suffix.allSatisfy(\.isASCIILetterOrDigit)
    }

    private static func isValidToken(_ token: String) -> Bool {
        let bytes = Array(token.utf8)
        let suffix = bytes.dropFirst(tokenPrefix.count)
        return bytes.starts(with: tokenPrefix) && (1...500).contains(suffix.count)
            && suffix.allSatisfy { $0.isASCIILetterOrDigit || $0 == 0x2D || $0 == 0x5F }
    }
}

extension UInt8 {
    fileprivate var isASCIILetterOrDigit: Bool {
        (0x30...0x39).contains(self) || (0x41...0x5A).contains(self) || (0x61...0x7A).contains(self)
    }
}

/// Where the entered routine is kept. The app implements it with the Keychain.
public protocol RoutineCredentialsStore: Sendable {
    /// The stored credentials, or `nil` when none have been entered.
    func load() throws -> RoutineCredentials?
    /// Replaces the stored credentials.
    func save(_ credentials: RoutineCredentials) throws
    /// Removes the stored credentials.
    func delete() throws
}

/// A `RoutineCredentialsStore` held in memory, for previews and tests.
public final class InMemoryRoutineCredentialsStore: RoutineCredentialsStore, @unchecked Sendable {
    // `@unchecked Sendable` is safe because every access to `credentials` goes through `lock`.
    private let lock = NSLock()
    private var credentials: RoutineCredentials?

    /// Creates a store holding `credentials`.
    public init(_ credentials: RoutineCredentials? = nil) {
        self.credentials = credentials
    }

    /// The stored credentials.
    public func load() -> RoutineCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return credentials
    }

    /// Replaces the stored credentials.
    public func save(_ credentials: RoutineCredentials) {
        lock.lock()
        defer { lock.unlock() }
        self.credentials = credentials
    }

    /// Removes the stored credentials.
    public func delete() {
        lock.lock()
        defer { lock.unlock() }
        credentials = nil
    }
}

/// Starts the end-of-day routine.
public protocol RoutineFiring: Sendable {
    /// Whether a routine has been entered.
    func isConfigured() -> Bool
    /// Starts the routine with `text` and returns the URL of the session it started.
    func fire(text: String) async throws -> URL
}

/// Why the routine did not start.
public enum RoutineTriggerError: Error, Equatable, Sendable {
    case notConfigured
    case summaryNotConfigured
    case rejectedToken
    case notFound
    case notStarted
    case forbidden
    case rateLimited(retryAfter: TimeInterval?)
    case unavailable
    case network
    case unexpectedResponse

    /// A sentence to show the person. It never contains the token.
    public var userMessage: String {
        switch self {
        case .notConfigured:
            "Add the end-of-day routine in Settings to send this day for processing."
        case .summaryNotConfigured:
            "A summary routine's trigger is missing. Save it again under the same name in Settings → Summary routines."
        case .rejectedToken:
            "Claude rejected the routine token. Generate a new token at claude.ai/code/routines and enter it in Settings."
        case .notFound:
            "That routine no longer exists. Check the fire URL in Settings."
        case .notStarted:
            "Claude didn't start the routine. Check that it isn't paused at claude.ai/code/routines."
        case .forbidden:
            "Your Claude account can't start routines. Check your plan and your organization's settings."
        case .rateLimited:
            "Claude is limiting routine runs right now. Try again later."
        case .unavailable:
            "Claude is unavailable right now. Try again in a few minutes."
        case .network:
            "Couldn't reach Claude. Check your connection and try again."
        case .unexpectedResponse:
            "Claude sent an unexpected response. Try again later."
        }
    }
}

/// Fires the routine through its API trigger.
public struct RoutineTriggerClient: RoutineFiring {
    private let http: any HTTPClient
    private let credentials: any RoutineCredentialsStore

    /// Creates a client that sends through `http` with the routine in `credentials`.
    public init(http: any HTTPClient, credentials: any RoutineCredentialsStore) {
        self.http = http
        self.credentials = credentials
    }

    /// Whether the routine's URL and token are stored and readable.
    public func isConfigured() -> Bool {
        stored() != nil
    }

    /// Sends `text` to the routine and returns the URL of the session it started.
    public func fire(text: String) async throws -> URL {
        guard let routine = stored() else {
            throw RoutineTriggerError.notConfigured
        }
        return try await Self.send(text: text, to: routine, http: http)
    }

    /// Sends `text` to `routine` through `http` and returns the URL of the session it started.
    static func send(
        text: String, to routine: RoutineCredentials, http: any HTTPClient
    ) async throws -> URL {
        let request = HTTPRequest(
            method: .post, url: routine.fireURL,
            headers: [
                "Authorization": "Bearer " + routine.token,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            ],
            body: try JSONEncoder().encode(Payload(text: text)), timeout: 30)
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            throw RoutineTriggerError.network
        }
        switch response.status {
        case 200: return try sessionURL(in: response.body)
        case 400: throw RoutineTriggerError.notStarted
        case 401: throw RoutineTriggerError.rejectedToken
        case 403: throw RoutineTriggerError.forbidden
        case 404: throw RoutineTriggerError.notFound
        case 429:
            let seconds = response.header("Retry-After")
                .flatMap { Int($0) }
                .flatMap { $0 >= 0 ? $0 : nil }
            throw RoutineTriggerError.rateLimited(retryAfter: seconds.map(TimeInterval.init))
        case 500...599: throw RoutineTriggerError.unavailable
        default: throw RoutineTriggerError.unexpectedResponse
        }
    }

    // A store that cannot be read counts as no routine.
    private func stored() -> RoutineCredentials? {
        try? credentials.load()
    }

    private static func sessionURL(in body: Data) throws -> URL {
        guard let fired = try? JSONDecoder().decode(Fired.self, from: body),
            fired.type == "routine_fire",
            let url = URL(string: fired.sessionURL),
            url.scheme == "https", url.host == "claude.ai"
        else {
            throw RoutineTriggerError.unexpectedResponse
        }
        return url
    }

    private struct Payload: Encodable {
        let text: String
    }

    private struct Fired: Decodable {
        let type: String
        let sessionURL: String

        enum CodingKeys: String, CodingKey {
            case type
            case sessionURL = "claude_code_session_url"
        }
    }
}
