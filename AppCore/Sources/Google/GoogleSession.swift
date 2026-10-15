import Foundation

/// Where a signed-in session's tokens are kept. The app implements it with the Keychain.
public protocol TokenStore: Sendable {
    /// The stored tokens, or `nil` when nobody is signed in.
    func load() throws -> OAuthTokens?
    /// Replaces the stored tokens.
    func save(_ tokens: OAuthTokens) throws
    /// Removes the stored tokens.
    func delete() throws
}

/// Sends a request to a Google API with the signed-in person's access token.
public protocol AuthorizedHTTPSending: Sendable {
    /// Sends `request` authorized, returning a 2xx response or throwing a `GoogleAPIError`.
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// The Google OAuth client the person entered, as stored, before it is validated.
public struct GoogleClientCredentials: Codable, Equatable, Sendable {
    /// The client ID as entered.
    public let clientID: String
    /// The client secret as entered, if any.
    public let clientSecret: String?

    /// Creates credentials.
    public init(clientID: String, clientSecret: String?) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    /// The validated configuration, or `nil` when the client ID or secret is malformed.
    public var configuration: GoogleOAuthConfiguration? {
        GoogleOAuthConfiguration(clientID: clientID, clientSecret: clientSecret)
    }
}

/// Where the entered Google OAuth client is kept. The app implements it with the Keychain.
public protocol ClientCredentialsStore: Sendable {
    /// The stored credentials, or `nil` when none have been entered.
    func load() throws -> GoogleClientCredentials?
    /// Replaces the stored credentials.
    func save(_ credentials: GoogleClientCredentials) throws
    /// Removes the stored credentials.
    func delete() throws
}

/// A `ClientCredentialsStore` held in memory, for previews and tests.
public final class InMemoryClientCredentialsStore: ClientCredentialsStore, @unchecked Sendable {
    // `@unchecked Sendable` is safe because every access to `credentials` goes through `lock`.
    private let lock = NSLock()
    private var credentials: GoogleClientCredentials?

    /// Creates a store holding `credentials`.
    public init(_ credentials: GoogleClientCredentials? = nil) {
        self.credentials = credentials
    }

    /// The stored credentials.
    public func load() -> GoogleClientCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return credentials
    }

    /// Replaces the stored credentials.
    public func save(_ credentials: GoogleClientCredentials) {
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

/// The person's Google sign-in, as the app's screens see it.
public protocol GoogleAccount: Sendable {
    /// Sets the OAuth client to use; `nil` means none has been entered yet.
    func configure(_ configuration: GoogleOAuthConfiguration?) async
    /// Whether an OAuth client has been set.
    func isConfigured() async -> Bool
    /// Whether tokens are stored for the configured client.
    func isSignedIn() async -> Bool
    /// Signs in. `authenticate` opens the authorization URL and returns the callback URL Google
    /// redirected to with the given callback scheme.
    func signIn(authenticate: @escaping @Sendable (URL, String) async throws -> URL) async throws
    /// Revokes the grant, as far as Google can be reached, and forgets the tokens.
    func signOut() async
}

/// The Google sign-in: keeps the tokens, refreshes them, and authorizes API requests.
///
/// Every error it throws is a `GoogleAPIError`.
public actor GoogleSession: GoogleAccount, AuthorizedHTTPSending {
    private var configuration: GoogleOAuthConfiguration?
    private let http: any HTTPClient
    private let tokenStore: any TokenStore
    private let hasher: any SHA256Hashing
    private let now: @Sendable () -> Date
    private var refreshTask: Task<OAuthTokens, Error>?
    // Bumped whenever the stored tokens are replaced or removed, so a refresh that was already
    // running cannot store its tokens over the change.
    private var tokenGeneration = 0

    /// Creates a session for `configuration`, with `nil` until the person enters a client.
    public init(
        configuration: GoogleOAuthConfiguration?, http: any HTTPClient, tokens: any TokenStore,
        hasher: any SHA256Hashing, now: @escaping @Sendable () -> Date
    ) {
        self.configuration = configuration
        self.http = http
        self.tokenStore = tokens
        self.hasher = hasher
        self.now = now
    }

    /// Sets the OAuth client. Stored tokens belong to the client that issued them, so a
    /// different client ID (or none) deletes them, without revoking; a new secret keeps them.
    public func configure(_ configuration: GoogleOAuthConfiguration?) {
        if configuration?.clientID != self.configuration?.clientID {
            tokenGeneration += 1
            try? tokenStore.delete()
        }
        self.configuration = configuration
    }

    /// Whether an OAuth client has been set.
    public func isConfigured() -> Bool {
        configuration != nil
    }

    /// Whether a client is set and tokens can be loaded.
    public func isSignedIn() -> Bool {
        configuration != nil && (try? tokenStore.load()) != nil
    }

    /// Signs in with authorization code and PKCE, and stores the tokens.
    ///
    /// A `GoogleAPIError` from `authenticate` is rethrown and any other error from it is
    /// `.authorizationFailed`, as is a failure to store the tokens.
    public func signIn(
        authenticate: @escaping @Sendable (URL, String) async throws -> URL
    ) async throws {
        let configuration = try requireConfiguration()
        var random = SystemRandomNumberGenerator()
        let request = GoogleOAuth.authorizationRequest(
            configuration: configuration, random: &random, hasher: hasher)
        let callback: URL
        do {
            callback = try await authenticate(request.url, configuration.redirectScheme)
        } catch let error as GoogleAPIError {
            throw error
        } catch {
            throw GoogleAPIError.authorizationFailed
        }
        let code = try GoogleOAuth.authorizationCode(
            from: callback, for: request, configuration: configuration)
        let response = try await Self.transmit(
            GoogleOAuth.tokenRequest(
                code: code, verifier: request.verifier, configuration: configuration),
            over: http)
        let tokens = try GoogleOAuth.tokens(
            from: response, previousRefreshToken: nil, requireScopes: true, now: now())
        tokenGeneration += 1
        do {
            try tokenStore.save(tokens)
        } catch {
            throw GoogleAPIError.authorizationFailed
        }
    }

    /// Sends `request` with the access token, refreshing it first when it expires within a
    /// minute, and once more after a 401. A second 401 signs the person out.
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let configuration = try requireConfiguration()
        guard var tokens = try? tokenStore.load() else {
            throw GoogleAPIError.signedOut
        }
        if tokens.expiresAt.addingTimeInterval(-60) <= now() {
            tokens = try await refreshed(tokens, configuration: configuration)
        }
        var response = try await Self.transmit(authorized(request, tokens), over: http)
        if response.status == 401 {
            tokens = try await refreshed(tokens, configuration: configuration)
            response = try await Self.transmit(authorized(request, tokens), over: http)
            if response.status == 401 {
                try? tokenStore.delete()
                throw GoogleAPIError.signedOut
            }
        }
        switch response.status {
        case 200..<300:
            return response
        case 403:
            throw GoogleAPIError.forbidden
        case 429:
            throw GoogleAPIError.rateLimited
        default:
            throw GoogleAPIError.unexpectedResponse
        }
    }

    /// Revokes the refresh token, ignoring any failure, then deletes the stored tokens.
    public func signOut() async {
        tokenGeneration += 1
        if let tokens = try? tokenStore.load() {
            _ = try? await http.send(GoogleOAuth.revokeRequest(token: tokens.refreshToken))
        }
        try? tokenStore.delete()
    }

    private func requireConfiguration() throws -> GoogleOAuthConfiguration {
        guard let configuration else {
            throw GoogleAPIError.notConfigured
        }
        return configuration
    }

    // Callers that need a refresh while one is in flight wait for it instead of starting another,
    // so a burst of requests spends the refresh token once. The caller that started it stores the
    // result, unless a sign-in, sign-out or client change replaced the tokens in the meantime.
    // The request already in flight still uses the refreshed token.
    private func refreshed(
        _ tokens: OAuthTokens, configuration: GoogleOAuthConfiguration
    ) async throws -> OAuthTokens {
        if let refreshTask {
            return try await refreshTask.value
        }
        let generation = tokenGeneration
        let task = Task { [http, tokenStore, now] in
            try await Self.refresh(
                tokens, configuration: configuration, http: http, store: tokenStore, now: now)
        }
        refreshTask = task
        defer { refreshTask = nil }
        let refreshed = try await task.value
        if generation == tokenGeneration {
            // A token that cannot be stored still works for now; the next send refreshes again.
            try? tokenStore.save(refreshed)
        }
        return refreshed
    }

    private static func refresh(
        _ tokens: OAuthTokens, configuration: GoogleOAuthConfiguration, http: any HTTPClient,
        store: any TokenStore, now: @Sendable () -> Date
    ) async throws -> OAuthTokens {
        let response = try await transmit(
            GoogleOAuth.refreshRequest(
                refreshToken: tokens.refreshToken, configuration: configuration),
            over: http)
        do {
            return try GoogleOAuth.tokens(
                from: response, previousRefreshToken: tokens.refreshToken, requireScopes: false,
                now: now())
        } catch {
            if error as? GoogleAPIError == .signedOut {
                try? store.delete()
            }
            throw error
        }
    }

    private func authorized(_ request: HTTPRequest, _ tokens: OAuthTokens) -> HTTPRequest {
        var request = request
        request.headers["Authorization"] = "Bearer " + tokens.accessToken
        return request
    }

    private static func transmit(
        _ request: HTTPRequest, over http: any HTTPClient
    ) async throws -> HTTPResponse {
        do {
            return try await http.send(request)
        } catch {
            throw GoogleAPIError.network
        }
    }
}
