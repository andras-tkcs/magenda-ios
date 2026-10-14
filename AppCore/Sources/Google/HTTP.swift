import Foundation

/// The HTTP methods the Google clients use.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

/// A request the app sends, independent of `URLSession` so it can be built and checked on Linux.
public struct HTTPRequest: Equatable, Sendable {
    /// The method.
    public var method: HTTPMethod
    /// The full URL, query included.
    public var url: URL
    /// Header fields by name.
    public var headers: [String: String]
    /// The body, if any.
    public var body: Data?
    /// Seconds before the request is abandoned.
    public var timeout: TimeInterval

    /// Creates a request.
    public init(
        method: HTTPMethod, url: URL, headers: [String: String], body: Data?,
        timeout: TimeInterval = 30
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

/// A response: its status code and body.
public struct HTTPResponse: Equatable, Sendable {
    /// The HTTP status code.
    public var status: Int
    /// The body, empty when there was none.
    public var body: Data

    /// Creates a response.
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Sends requests. The app implements it with `URLSession`; tests use a fake.
public protocol HTTPClient: Sendable {
    /// Sends `request` and returns whatever status came back; throws only when there was no
    /// response at all (a transport failure).
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Computes SHA-256. The app implements it with CryptoKit, which AppCore cannot import.
public protocol SHA256Hashing: Sendable {
    /// The 32-byte SHA-256 digest of `data`.
    func sha256(_ data: Data) -> Data
}
