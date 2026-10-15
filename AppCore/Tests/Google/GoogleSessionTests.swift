// AppCore's Google session: stored tokens, refreshing them once for concurrent callers, the
// 401 retry, sign-in, sign-out and switching clients. Every client ID here is made up.

import AppCore
import Foundation
import Testing

private let clientID = "123-abc.apps.googleusercontent.com"
private let otherClientID = "456-xyz.apps.googleusercontent.com"
private let redirectScheme = "com.googleusercontent.apps.123-abc"
private let bothScopes =
    "https://www.googleapis.com/auth/calendar.readonly "
    + "https://www.googleapis.com/auth/tasks.readonly"
private let clock = Date(timeIntervalSince1970: 1_800_000_000)
private let apiURL = URL(fileURLWithPath: "/").appending(path: "calendar")
private let tokenURL = "https://oauth2.googleapis.com/token"
private let revokeURL = "https://oauth2.googleapis.com/revoke"

private let freshTokens = OAuthTokens(
    accessToken: "old-access", refreshToken: "refresh-1", expiresAt: clock.addingTimeInterval(3600))
private let refreshJSON =
    #"{"access_token":"new-access","expires_in":3600,"token_type":"Bearer"}"#
private let okJSON = #"{"ok":true}"#

private struct Unrelated: Error {}

/// Answers every input with the same 32-byte digest, since sign-in draws a random verifier.
private struct ConstantHasher: SHA256Hashing {
    func sha256(_ data: Data) -> Data {
        Data(repeating: 7, count: 32)
    }
}

/// Records every input and answers with its first 32 bytes, so each verifier has its own
/// challenge.
// `@unchecked Sendable` is safe because every access to `recorded` goes through `lock`.
private final class RecordingHasher: SHA256Hashing, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Data] = []

    /// Every input hashed so far, oldest first.
    var inputs: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func sha256(_ data: Data) -> Data {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(data)
        return Data(data.prefix(32))
    }
}

private func configuration(
    _ id: String = clientID, secret: String? = nil
) throws -> GoogleOAuthConfiguration {
    try #require(GoogleOAuthConfiguration(clientID: id, clientSecret: secret))
}

private func session(
    http: any HTTPClient, store: FakeTokenStore, configured: Bool = true,
    hasher: any SHA256Hashing = FakeHasher()
) throws -> GoogleSession {
    let config = try configured ? configuration() : nil
    return GoogleSession(
        configuration: config, http: http, tokens: store, hasher: hasher, now: { clock })
}

private func apiRequest() -> HTTPRequest {
    HTTPRequest(method: .get, url: apiURL, headers: ["Accept": "application/json"], body: nil)
}

private func expiring(in seconds: TimeInterval) -> OAuthTokens {
    OAuthTokens(
        accessToken: "old-access", refreshToken: "refresh-1",
        expiresAt: clock.addingTimeInterval(seconds))
}

private func bearers(_ http: FakeHTTPClient) -> [String?] {
    http.requests.filter { $0.url == apiURL }.map { $0.headers["Authorization"] }
}

private func tokenRequests(_ http: FakeHTTPClient) -> [HTTPRequest] {
    http.requests.filter { $0.url.absoluteString == tokenURL }
}

private func formBody(_ request: HTTPRequest) -> String {
    String(decoding: request.body ?? Data(), as: UTF8.self)
}

/// The value of `name` in a URL's query or a form body.
private func parameter(_ name: String, in query: String?) -> String? {
    URLComponents(string: "?" + (query ?? ""))?.queryItems?.first { $0.name == name }?.value
}

/// The callback Google would send for `url`'s state, with `code`.
private func callback(for url: URL, code: String = "auth-code") throws -> URL {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let state = try #require(items.first { $0.name == "state" }?.value)
    let link = "\(redirectScheme):/oauth2redirect?state=\(state)&code=\(code)"
    return try #require(URL(string: link))
}

@Suite("Google session authorized requests")
struct GoogleSessionSendTests {
    @Test("Sending with no stored tokens throws signedOut without a request")
    func notSignedIn() async throws {
        let http = FakeHTTPClient()
        let google = try session(http: http, store: FakeTokenStore())
        await #expect(throws: GoogleAPIError.signedOut) { try await google.send(apiRequest()) }
        #expect(http.requests.isEmpty)
    }

    @Test("Sending when the tokens cannot be loaded throws signedOut")
    func loadFails() async throws {
        let http = FakeHTTPClient()
        let google = try session(http: http, store: FakeTokenStore(failsOnLoad: true))
        await #expect(throws: GoogleAPIError.signedOut) { try await google.send(apiRequest()) }
        #expect(http.requests.isEmpty)
    }

    @Test("A request gets the bearer header and keeps its own headers")
    func bearerHeader() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: okJSON)
        let google = try session(http: http, store: FakeTokenStore(freshTokens))
        let response = try await google.send(apiRequest())
        #expect(response == HTTPResponse(status: 200, body: Data(okJSON.utf8)))
        let sent = try #require(http.requests.first)
        #expect(
            sent.headers == ["Accept": "application/json", "Authorization": "Bearer old-access"])
        #expect(http.requests.count == 1)
    }

    @Test("A token expiring within 60 seconds is refreshed first and the new one stored")
    func refreshesNearExpiry() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: refreshJSON)
        http.enqueue(status: 200, json: okJSON)
        let store = FakeTokenStore(expiring(in: 60))
        let google = try session(http: http, store: store)
        _ = try await google.send(apiRequest())
        #expect(http.requests.map(\.url.absoluteString) == [tokenURL, apiURL.absoluteString])
        #expect(formBody(http.requests[0]).contains("refresh_token=refresh-1"))
        #expect(bearers(http) == ["Bearer new-access"])
        #expect(
            store.tokens
                == OAuthTokens(
                    accessToken: "new-access", refreshToken: "refresh-1",
                    expiresAt: clock.addingTimeInterval(3600)))
    }

    @Test("A token valid for more than 60 seconds is used as it is")
    func noRefreshBeforeWindow() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: okJSON)
        let google = try session(http: http, store: FakeTokenStore(expiring(in: 61)))
        _ = try await google.send(apiRequest())
        #expect(tokenRequests(http).isEmpty)
        #expect(bearers(http) == ["Bearer old-access"])
    }

    @Test("Two concurrent sends with an expiring token share exactly one refresh request")
    func concurrentRefreshIsSingleFlight() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: refreshJSON)
        http.enqueue(status: 200, json: okJSON)
        http.enqueue(status: 200, json: okJSON)
        let gated = GatedHTTPClient(http, gating: tokenURL)
        let store = FakeTokenStore(expiring(in: 10))
        let google = try session(http: gated, store: store)
        let first = Task { try await google.send(apiRequest()) }
        await gated.waitUntilBlocked()
        let second = Task { try await google.send(apiRequest()) }
        // The second send has read the expiring token while the refresh is held. It cannot leave
        // the session before it waits for that refresh, which needs the session to finish.
        await store.waitForLoads(2)
        await gated.release()
        _ = try await (first.value, second.value)
        #expect(tokenRequests(http).count == 1)
        #expect(http.requests.first?.url.absoluteString == tokenURL)
        #expect(bearers(http) == ["Bearer new-access", "Bearer new-access"])
        #expect(store.saveCount == 1)
    }

    @Test("A 401 refreshes the token and retries once with the new one")
    func retryAfter401() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 401, json: "{}")
        http.enqueue(status: 200, json: refreshJSON)
        http.enqueue(status: 200, json: okJSON)
        let store = FakeTokenStore(freshTokens)
        let google = try session(http: http, store: store)
        let response = try await google.send(apiRequest())
        #expect(response.status == 200)
        #expect(tokenRequests(http).count == 1)
        #expect(bearers(http) == ["Bearer old-access", "Bearer new-access"])
        #expect(store.deleteCount == 0)
    }

    @Test("A second 401 deletes the tokens and throws signedOut")
    func twice401() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 401, json: "{}")
        http.enqueue(status: 200, json: refreshJSON)
        http.enqueue(status: 401, json: "{}")
        let store = FakeTokenStore(freshTokens)
        let google = try session(http: http, store: store)
        await #expect(throws: GoogleAPIError.signedOut) { try await google.send(apiRequest()) }
        #expect(http.requests.count == 3)
        #expect(store.tokens == nil)
        #expect(store.deleteCount == 1)
    }

    @Test("A refresh answered with invalid_grant deletes the tokens and throws signedOut")
    func refreshInvalidGrant() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 400, json: #"{"error":"invalid_grant"}"#)
        let store = FakeTokenStore(expiring(in: 0))
        let google = try session(http: http, store: store)
        await #expect(throws: GoogleAPIError.signedOut) { try await google.send(apiRequest()) }
        #expect(http.requests.count == 1)
        #expect(store.tokens == nil)
    }

    @Test("A refresh that fails another way keeps the tokens and passes the error on")
    func refreshServerError() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 500, json: "{}")
        let store = FakeTokenStore(expiring(in: 0))
        let google = try session(http: http, store: store)
        await #expect(throws: GoogleAPIError.authorizationFailed) {
            try await google.send(apiRequest())
        }
        #expect(store.tokens == expiring(in: 0))
        #expect(store.deleteCount == 0)
    }

    @Test("A refresh that cannot reach Google throws network")
    func refreshTransportError() async throws {
        let http = FakeHTTPClient([.failure(URLError(.notConnectedToInternet))])
        let store = FakeTokenStore(expiring(in: 0))
        let google = try session(http: http, store: store)
        await #expect(throws: GoogleAPIError.network) { try await google.send(apiRequest()) }
        #expect(store.tokens == expiring(in: 0))
    }

    @Test("A refreshed token that cannot be stored is still used")
    func refreshSaveFails() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: refreshJSON)
        http.enqueue(status: 200, json: okJSON)
        let store = FakeTokenStore(expiring(in: 0), failsOnSave: true)
        let google = try session(http: http, store: store)
        _ = try await google.send(apiRequest())
        #expect(bearers(http) == ["Bearer new-access"])
        #expect(store.saveCount == 1)
    }

    @Test("A sign-out while a refresh is in flight is not undone when the refresh finishes")
    func signOutDuringRefresh() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: "{}")
        http.enqueue(status: 200, json: refreshJSON)
        http.enqueue(status: 200, json: okJSON)
        let gated = GatedHTTPClient(http, gating: tokenURL)
        let store = FakeTokenStore(expiring(in: 10))
        let google = try session(http: gated, store: store)
        let sending = Task { try await google.send(apiRequest()) }
        await gated.waitUntilBlocked()
        await google.signOut()
        await gated.release()
        _ = try await sending.value
        #expect(http.requests.first?.url.absoluteString == revokeURL)
        #expect(store.tokens == nil)
        #expect(store.saveCount == 0)
        #expect(await google.isSignedIn() == false)
    }

    @Test("Switching clients while a refresh is in flight keeps the old client's tokens out")
    func configureDuringRefresh() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: refreshJSON)
        http.enqueue(status: 200, json: okJSON)
        let gated = GatedHTTPClient(http, gating: tokenURL)
        let store = FakeTokenStore(expiring(in: 10))
        let google = try session(http: gated, store: store)
        let sending = Task { try await google.send(apiRequest()) }
        await gated.waitUntilBlocked()
        await google.configure(try configuration(otherClientID))
        await gated.release()
        _ = try await sending.value
        #expect(store.tokens == nil)
        #expect(store.saveCount == 0)
    }

    @Test(
        "A non-2xx answer maps to its error",
        arguments: [
            (403, GoogleAPIError.forbidden), (429, .rateLimited), (500, .unexpectedResponse),
            (302, .unexpectedResponse),
        ])
    func statusMapping(status: Int, error: GoogleAPIError) async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: status, json: "{}")
        let google = try session(http: http, store: FakeTokenStore(freshTokens))
        await #expect(throws: error) { try await google.send(apiRequest()) }
        #expect(http.requests.count == 1)
    }

    @Test("Any 2xx answer is returned", arguments: [200, 204, 299])
    func successStatuses(status: Int) async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: status, json: "")
        let google = try session(http: http, store: FakeTokenStore(freshTokens))
        #expect(try await google.send(apiRequest()).status == status)
    }

    @Test("A transport failure throws network")
    func transportError() async throws {
        let http = FakeHTTPClient([.failure(URLError(.timedOut))])
        let store = FakeTokenStore(freshTokens)
        let google = try session(http: http, store: store)
        await #expect(throws: GoogleAPIError.network) { try await google.send(apiRequest()) }
        #expect(store.tokens == freshTokens)
    }
}

@Suite("Google session sign-in")
struct GoogleSessionSignInTests {
    private let signInJSON = """
        {"access_token":"access-1","expires_in":3599,"token_type":"Bearer",
         "refresh_token":"refresh-1","scope":"\(bothScopes)"}
        """

    @Test("Sign-in opens the consent URL, exchanges the code and stores the tokens")
    func signsIn() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: signInJSON)
        let store = FakeTokenStore()
        let hasher = RecordingHasher()
        let google = try session(http: http, store: store, hasher: hasher)
        #expect(await google.isSignedIn() == false)
        try await google.signIn { url, scheme in
            #expect(scheme == redirectScheme)
            #expect(url.host() == "accounts.google.com")
            #expect(url.path() == "/o/oauth2/v2/auth")
            let hashed = try #require(hasher.inputs.first)
            let expected = GoogleOAuth.codeChallenge(
                verifier: String(decoding: hashed, as: UTF8.self), hasher: RecordingHasher())
            #expect(parameter("code_challenge", in: url.query()) == expected)
            return try callback(for: url, code: "code/with+chars")
        }
        let exchange = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(exchange.url.absoluteString == tokenURL)
        let body = formBody(exchange)
        #expect(body.hasPrefix("code=code%2Fwith%2Bchars&client_id="))
        #expect(body.contains("grant_type=authorization_code"))
        // The verifier sent with the code is the one whose hash became the challenge.
        let verifier = try #require(parameter("code_verifier", in: body))
        #expect(hasher.inputs == [Data(verifier.utf8)])
        #expect(
            store.tokens
                == OAuthTokens(
                    accessToken: "access-1", refreshToken: "refresh-1",
                    expiresAt: clock.addingTimeInterval(3599)))
        #expect(await google.isSignedIn())
    }

    @Test(
        "A GoogleAPIError from the sign-in sheet passes through",
        arguments: [GoogleAPIError.authorizationCancelled, .network])
    func closureGoogleError(error: GoogleAPIError) async throws {
        let http = FakeHTTPClient()
        let store = FakeTokenStore()
        let google = try session(http: http, store: store, hasher: ConstantHasher())
        await #expect(throws: error) { try await google.signIn { _, _ in throw error } }
        #expect(http.requests.isEmpty)
        #expect(store.saveCount == 0)
    }

    @Test("Any other error from the sign-in sheet becomes authorizationFailed")
    func closureOtherError() async throws {
        let http = FakeHTTPClient()
        let google = try session(http: http, store: FakeTokenStore(), hasher: ConstantHasher())
        await #expect(throws: GoogleAPIError.authorizationFailed) {
            try await google.signIn { _, _ in throw Unrelated() }
        }
        #expect(http.requests.isEmpty)
    }

    @Test("A callback with the wrong state fails without exchanging a code")
    func wrongState() async throws {
        let http = FakeHTTPClient()
        let google = try session(http: http, store: FakeTokenStore(), hasher: ConstantHasher())
        await #expect(throws: GoogleAPIError.authorizationFailed) {
            try await google.signIn { _, _ in
                try #require(URL(string: "\(redirectScheme):/oauth2redirect?state=forged&code=x"))
            }
        }
        #expect(http.requests.isEmpty)
    }

    @Test("A code exchange that cannot reach Google throws network")
    func exchangeTransportError() async throws {
        let http = FakeHTTPClient([.failure(URLError(.notConnectedToInternet))])
        let store = FakeTokenStore()
        let google = try session(http: http, store: store, hasher: ConstantHasher())
        await #expect(throws: GoogleAPIError.network) {
            try await google.signIn { url, _ in try callback(for: url) }
        }
        #expect(store.saveCount == 0)
    }

    @Test("A grant without both scopes throws missingScopes and stores nothing")
    func missingScopes() async throws {
        let http = FakeHTTPClient()
        http.enqueue(
            status: 200,
            json: #"{"access_token":"a","expires_in":1,"token_type":"Bearer","refresh_token":"r"}"#)
        let store = FakeTokenStore()
        let google = try session(http: http, store: store, hasher: ConstantHasher())
        await #expect(throws: GoogleAPIError.missingScopes) {
            try await google.signIn { url, _ in try callback(for: url) }
        }
        #expect(store.saveCount == 0)
    }

    @Test("Tokens that cannot be stored make sign-in fail with authorizationFailed")
    func saveFails() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: signInJSON)
        let store = FakeTokenStore(failsOnSave: true)
        let google = try session(http: http, store: store, hasher: ConstantHasher())
        await #expect(throws: GoogleAPIError.authorizationFailed) {
            try await google.signIn { url, _ in try callback(for: url) }
        }
        #expect(store.saveCount == 1)
    }
}

@Suite("Google session sign-out")
struct GoogleSessionSignOutTests {
    @Test("Sign-out revokes the refresh token and deletes the tokens")
    func signsOut() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: "{}")
        let store = FakeTokenStore(freshTokens)
        let google = try session(http: http, store: store)
        await google.signOut()
        let revoke = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(revoke.url.absoluteString == revokeURL)
        #expect(formBody(revoke) == "token=refresh-1")
        #expect(store.tokens == nil)
        #expect(await google.isSignedIn() == false)
    }

    @Test("Sign-out deletes the tokens even when the revoke cannot reach Google")
    func revokeFails() async throws {
        let http = FakeHTTPClient([.failure(URLError(.notConnectedToInternet))])
        let store = FakeTokenStore(freshTokens)
        let google = try session(http: http, store: store)
        await google.signOut()
        #expect(http.requests.count == 1)
        #expect(store.tokens == nil)
    }

    @Test("Sign-out ignores a revoke error status and a failing delete")
    func deleteFails() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 400, json: #"{"error":"invalid_token"}"#)
        let store = FakeTokenStore(freshTokens, failsOnDelete: true)
        let google = try session(http: http, store: store)
        await google.signOut()
        #expect(http.requests.count == 1)
        #expect(store.deleteCount == 1)
    }

    @Test("Sign-out with no stored tokens sends nothing")
    func nothingStored() async throws {
        let http = FakeHTTPClient()
        let store = FakeTokenStore()
        let google = try session(http: http, store: store)
        await google.signOut()
        #expect(http.requests.isEmpty)
        #expect(store.deleteCount == 1)
    }
}

@Suite("Google session configuration")
struct GoogleSessionConfigurationTests {
    @Test("With no client, nothing is configured or signed in and nothing is sent")
    func notConfigured() async throws {
        let http = FakeHTTPClient()
        let store = FakeTokenStore(freshTokens)
        let google = try session(http: http, store: store, configured: false)
        #expect(await google.isConfigured() == false)
        #expect(await google.isSignedIn() == false)
        await #expect(throws: GoogleAPIError.notConfigured) { try await google.send(apiRequest()) }
        await #expect(throws: GoogleAPIError.notConfigured) {
            try await google.signIn { url, _ in
                Issue.record("The sign-in sheet must not open without a client")
                return url
            }
        }
        #expect(http.requests.isEmpty)
    }

    @Test("A configured client with stored tokens is signed in")
    func configuredAndSignedIn() async throws {
        let google = try session(http: FakeHTTPClient(), store: FakeTokenStore(freshTokens))
        #expect(await google.isConfigured())
        #expect(await google.isSignedIn())
    }

    @Test("isSignedIn is false when the tokens cannot be loaded")
    func loadThrows() async throws {
        let google = try session(
            http: FakeHTTPClient(), store: FakeTokenStore(freshTokens, failsOnLoad: true))
        #expect(await google.isSignedIn() == false)
    }

    @Test("Configuring a different client ID deletes the tokens without revoking them")
    func differentClient() async throws {
        let http = FakeHTTPClient()
        let store = FakeTokenStore(freshTokens)
        let google = try session(http: http, store: store)
        await google.configure(try configuration(otherClientID))
        #expect(store.tokens == nil)
        #expect(http.requests.isEmpty)
        #expect(await google.isConfigured())
        #expect(await google.isSignedIn() == false)
    }

    @Test("Removing the client deletes the tokens")
    func removedClient() async throws {
        let store = FakeTokenStore(freshTokens)
        let google = try session(http: FakeHTTPClient(), store: store)
        await google.configure(nil)
        #expect(store.tokens == nil)
        #expect(await google.isConfigured() == false)
    }

    @Test("Entering a first client clears any tokens left without one")
    func firstClient() async throws {
        let store = FakeTokenStore(freshTokens)
        let google = try session(http: FakeHTTPClient(), store: store, configured: false)
        await google.configure(try configuration())
        #expect(store.deleteCount == 1)
        #expect(await google.isConfigured())
    }

    @Test("The same client ID with a new secret keeps the tokens")
    func sameClientNewSecret() async throws {
        let store = FakeTokenStore(freshTokens)
        let google = try session(http: FakeHTTPClient(), store: store)
        await google.configure(try configuration(secret: "new-secret"))
        #expect(store.tokens == freshTokens)
        #expect(store.deleteCount == 0)
        #expect(await google.isSignedIn())
    }

    @Test("A failing delete while switching clients is ignored")
    func switchDeleteFails() async throws {
        let store = FakeTokenStore(freshTokens, failsOnDelete: true)
        let google = try session(http: FakeHTTPClient(), store: store)
        await google.configure(try configuration(otherClientID))
        #expect(store.deleteCount == 1)
        #expect(await google.isConfigured())
    }
}

@Suite("Google client credentials")
struct GoogleClientCredentialsTests {
    @Test("Valid credentials give their configuration")
    func validConfiguration() throws {
        let credentials = GoogleClientCredentials(clientID: " \(clientID) ", clientSecret: "s3cret")
        let expected = try configuration(secret: "s3cret")
        #expect(credentials.configuration == expected)
    }

    @Test(
        "Invalid credentials give no configuration",
        arguments: [
            GoogleClientCredentials(clientID: "not-a-client", clientSecret: nil),
            GoogleClientCredentials(clientID: clientID, clientSecret: "has space"),
        ])
    func invalidConfiguration(credentials: GoogleClientCredentials) {
        #expect(credentials.configuration == nil)
    }

    @Test("The in-memory store saves, loads and deletes")
    func inMemoryStore() throws {
        let initial = GoogleClientCredentials(clientID: clientID, clientSecret: nil)
        let store = InMemoryClientCredentialsStore(initial)
        #expect(store.load() == initial)
        let replacement = GoogleClientCredentials(clientID: otherClientID, clientSecret: "s")
        store.save(replacement)
        #expect(store.load() == replacement)
        store.delete()
        #expect(store.load() == nil)
        #expect(InMemoryClientCredentialsStore().load() == nil)
    }

    @Test("Credentials round-trip through JSON")
    func codable() throws {
        let credentials = GoogleClientCredentials(clientID: clientID, clientSecret: "s")
        let data = try JSONEncoder().encode(credentials)
        #expect(try JSONDecoder().decode(GoogleClientCredentials.self, from: data) == credentials)
    }
}
