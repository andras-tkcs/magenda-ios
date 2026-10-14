// AppCore's Google OAuth: client validation, PKCE, the callback and the token endpoint. Every
// malformed input must fail closed, so each rule has a test that expects the rejection.

import AppCore
import Foundation
import Testing

private let clientID = "123-abc.apps.googleusercontent.com"
private let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"
private let tasksScope = "https://www.googleapis.com/auth/tasks.readonly"
private let redirect = "com.googleusercontent.apps.123-abc:/oauth2redirect"
private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

/// The characters `generator` would pick, in order, if every draw indexes `alphabet`.
private func draws(_ count: Int, seed: UInt64) -> String {
    var generator = SeededGenerator(state: seed)
    return String(
        (0..<count).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
}

private func configuration(secret: String? = nil) throws -> GoogleOAuthConfiguration {
    try #require(GoogleOAuthConfiguration(clientID: clientID, clientSecret: secret))
}

/// The fields of a form-encoded body, in order, percent-decoded.
private func formFields(_ request: HTTPRequest) throws -> [String] {
    let body = String(decoding: try #require(request.body), as: UTF8.self)
    return try body.split(separator: "&").map { pair in
        try #require(String(pair).removingPercentEncoding)
    }
}

/// A small seeded generator (SplitMix64) so random draws are repeatable.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

@Suite("Google OAuth configuration")
struct GoogleOAuthConfigurationTests {
    @Test("A well-formed client ID is accepted, trimmed, with no secret")
    func acceptsClientID() throws {
        let config = try #require(
            GoogleOAuthConfiguration(clientID: "  \(clientID)\n", clientSecret: nil))
        #expect(config.clientID == clientID)
        #expect(config.clientSecret == nil)
    }

    @Test(
        "A malformed client ID is rejected",
        arguments: [
            "", "   ", "123-ABC.apps.googleusercontent.com", "123-abc.APPS.googleusercontent.com",
            "abc.apps.googleusercontent.com", "-abc.apps.googleusercontent.com",
            "123-.apps.googleusercontent.com", ".apps.googleusercontent.com",
            "123-abc.apps.googleusercontent.com/oauth",
            "123-abc.apps.googleusercontent.com.evil.com",
            "123-a-b.apps.googleusercontent.com", "123-a b.apps.googleusercontent.com",
            "12x-abc.apps.googleusercontent.com", "123-abc.apps.googleusercontent.co",
            "123-ábc.apps.googleusercontent.com", "123-abc@apps.googleusercontent.com",
        ])
    func rejectsClientID(id: String) {
        #expect(GoogleOAuthConfiguration(clientID: id) == nil)
    }

    @Test("A client secret is trimmed")
    func trimsSecret() throws {
        #expect(try configuration(secret: "  test-secret-abc  ").clientSecret == "test-secret-abc")
        let longest = String(repeating: "s", count: 200)
        #expect(try configuration(secret: longest).clientSecret == longest)
    }

    @Test("An empty or blank client secret means none", arguments: ["", "   ", "\n\t"])
    func blankSecret(secret: String) throws {
        #expect(try configuration(secret: secret).clientSecret == nil)
    }

    @Test(
        "A client secret with whitespace, a control character or over 200 characters is rejected",
        arguments: [
            "a b", "a\tb", "a\u{7}b", "a\u{0}b", "a\u{2028}b", String(repeating: "s", count: 201),
        ])
    func rejectsSecret(secret: String) {
        #expect(GoogleOAuthConfiguration(clientID: clientID, clientSecret: secret) == nil)
    }

    @Test("The redirect scheme is the reversed client ID")
    func redirectURI() throws {
        let config = try configuration()
        #expect(config.redirectScheme == "com.googleusercontent.apps.123-abc")
        #expect(config.redirectURI == "com.googleusercontent.apps.123-abc:/oauth2redirect")
    }

    @Test("The scopes are exactly the two read-only ones")
    func scopes() {
        #expect(GoogleOAuthConfiguration.scopes == [calendarScope, tasksScope])
    }
}

@Suite("Google OAuth authorization request")
struct GoogleOAuthAuthorizationRequestTests {
    /// RFC 7636 appendix B: the S256 challenge is base64url, without padding, of the verifier's
    /// SHA-256 digest.
    @Test("The code challenge matches the RFC 7636 appendix B test vector")
    func rfc7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let digest = Data([
            19, 211, 30, 150, 26, 26, 216, 236, 47, 22, 177, 12, 76, 152, 46, 8, 118, 168, 120,
            173, 109, 241, 68, 86, 110, 225, 137, 74, 203, 112, 249, 195,
        ])
        let hasher = FakeHasher([Data(verifier.utf8): digest])
        #expect(
            GoogleOAuth.codeChallenge(verifier: verifier, hasher: hasher)
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("The challenge maps + and / to - and _ and drops padding")
    func base64URL() {
        let hasher = FakeHasher([Data("v".utf8): Data([0xFB, 0xFF])])
        #expect(GoogleOAuth.codeChallenge(verifier: "v", hasher: hasher) == "-_8")
    }

    @Test(
        "The verifier and state are 64 and 32 characters drawn from the generator",
        arguments: [1, 42, 9_999] as [UInt64])
    func verifierAndState(seed: UInt64) throws {
        let both = draws(96, seed: seed)
        let expectedVerifier = String(both.prefix(64))
        let expectedState = String(both.dropFirst(64))

        var random = SeededGenerator(state: seed)
        let hasher = FakeHasher([Data(expectedVerifier.utf8): Data([1, 2, 3])])
        let request = GoogleOAuth.authorizationRequest(
            configuration: try configuration(), random: &random, hasher: hasher)
        #expect(request.verifier == expectedVerifier)
        #expect(request.state == expectedState)
        #expect(request.verifier.count == 64)
        #expect(request.state.count == 32)
        #expect(request.verifier.allSatisfy(alphabet.contains))
        #expect(request.state.allSatisfy(alphabet.contains))
    }

    @Test("The authorization URL carries exactly the expected query items, in order")
    func authorizationURL() throws {
        let hasher = FakeHasher([Data(draws(64, seed: 7).utf8): Data([0xFB, 0xFF])])

        var random = SeededGenerator(state: 7)
        let request = GoogleOAuth.authorizationRequest(
            configuration: try configuration(), random: &random, hasher: hasher)
        let components = try #require(
            URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "accounts.google.com")
        #expect(components.path == "/o/oauth2/v2/auth")
        #expect(
            components.queryItems == [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirect),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: "\(calendarScope) \(tasksScope)"),
                URLQueryItem(name: "code_challenge", value: "-_8"),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: request.state),
            ])
        #expect(request.url.absoluteString.contains("scope=\(calendarScope)%20\(tasksScope)"))
    }
}

@Suite("Google OAuth callback")
struct GoogleOAuthCallbackTests {
    private let request = AuthorizationRequest(
        url: URL(fileURLWithPath: "/"), state: "state-123", verifier: "verifier")

    private func code(from callback: String) throws -> String {
        let url = try #require(URL(string: callback))
        return try GoogleOAuth.authorizationCode(
            from: url, for: request, configuration: try configuration())
    }

    @Test("A callback with the right scheme, state and a code returns the code")
    func valid() throws {
        #expect(try code(from: "\(redirect)?state=state-123&code=4/0Ab-c") == "4/0Ab-c")
    }

    @Test(
        "A callback from another scheme fails",
        arguments: [
            "com.example.evil:/oauth2redirect?state=state-123&code=abc",
            "https://accounts.google.com/oauth2redirect?state=state-123&code=abc",
            "com.googleusercontent.apps.456-abc:/oauth2redirect?state=state-123&code=abc",
        ])
    func wrongScheme(callback: String) {
        #expect(throws: GoogleAPIError.authorizationFailed) { try code(from: callback) }
    }

    @Test(
        "A callback with a wrong, missing or repeated state, or no single code, fails",
        arguments: [
            "?state=state-124&code=abc", "?code=abc", "?state&code=abc",
            "?state=state-123&state=state-123&code=abc", "?state=state-123",
            "?state=state-123&code=", "?state=state-123&code=a&code=b", "",
            "?state=other&error=access_denied",
        ])
    func fails(query: String) {
        #expect(throws: GoogleAPIError.authorizationFailed) { try code(from: redirect + query) }
    }

    @Test("access_denied means the person cancelled, even with a code")
    func cancelled() {
        #expect(throws: GoogleAPIError.authorizationCancelled) {
            try code(from: "\(redirect)?state=state-123&error=access_denied&code=abc")
        }
    }

    @Test(
        "Any other error fails",
        arguments: [
            "?state=state-123&error=server_error", "?state=state-123&error",
            "?state=state-123&error=access_denied&error=access_denied",
        ])
    func otherError(query: String) {
        #expect(throws: GoogleAPIError.authorizationFailed) { try code(from: redirect + query) }
    }
}

@Suite("Google OAuth token endpoint requests")
struct GoogleOAuthTokenRequestTests {
    @Test("The code exchange posts the exact form fields, without a secret")
    func exchange() throws {
        let request = GoogleOAuth.tokenRequest(
            code: "4/0Ab+c/d=", verifier: "v-._~", configuration: try configuration())
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(request.headers == ["Content-Type": "application/x-www-form-urlencoded"])
        #expect(request.timeout == 30)
        #expect(
            try formFields(request) == [
                "code=4/0Ab+c/d=", "client_id=\(clientID)",
                "redirect_uri=com.googleusercontent.apps.123-abc:/oauth2redirect",
                "code_verifier=v-._~", "grant_type=authorization_code",
            ])
        let body = String(decoding: try #require(request.body), as: UTF8.self)
        #expect(body.hasPrefix("code=4%2F0Ab%2Bc%2Fd%3D&client_id=\(clientID)&"))
        let encodedRedirect = "com.googleusercontent.apps.123-abc%3A%2Foauth2redirect"
        #expect(body.contains("&redirect_uri=\(encodedRedirect)&"))
    }

    @Test("A client secret follows client_id in the code exchange")
    func exchangeWithSecret() throws {
        let request = GoogleOAuth.tokenRequest(
            code: "abc", verifier: "v", configuration: try configuration(secret: "s&e=c/r+t"))
        #expect(
            try Array(formFields(request).prefix(3)) == [
                "code=abc", "client_id=\(clientID)", "client_secret=s&e=c/r+t",
            ])
        let body = String(decoding: try #require(request.body), as: UTF8.self)
        #expect(body.contains("&client_secret=s%26e%3Dc%2Fr%2Bt&"))
    }

    @Test("The refresh posts the exact form fields, with the secret right after client_id")
    func refresh() throws {
        let plain = GoogleOAuth.refreshRequest(
            refreshToken: "1//r+t", configuration: try configuration())
        #expect(plain.method == .post)
        #expect(plain.url.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(plain.headers == ["Content-Type": "application/x-www-form-urlencoded"])
        #expect(
            try formFields(plain) == [
                "client_id=\(clientID)", "refresh_token=1//r+t", "grant_type=refresh_token",
            ])
        let withSecret = GoogleOAuth.refreshRequest(
            refreshToken: "r", configuration: try configuration(secret: "sec"))
        #expect(
            try formFields(withSecret) == [
                "client_id=\(clientID)", "client_secret=sec", "refresh_token=r",
                "grant_type=refresh_token",
            ])
    }

    @Test("Revoking posts the token form-encoded")
    func revoke() throws {
        let request = GoogleOAuth.revokeRequest(token: "1//r+t é")
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://oauth2.googleapis.com/revoke")
        #expect(request.headers == ["Content-Type": "application/x-www-form-urlencoded"])
        #expect(request.body == Data("token=1%2F%2Fr%2Bt%20%C3%A9".utf8))
        #expect(try formFields(request) == ["token=1//r+t é"])
    }
}

@Suite("Google OAuth token responses")
struct GoogleOAuthTokenResponseTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A token response body: the usual fields, each replaced by a JSON literal in `fields` or
    /// removed by a `nil` there.
    private func body(_ fields: [String: String?] = [:]) -> String {
        var json = [
            "access_token": #""ya29.a""#, "expires_in": "3599", "token_type": #""Bearer""#,
            "refresh_token": #""1//r""#, "scope": "\"\(calendarScope) \(tasksScope)\"",
        ]
        for (key, value) in fields {
            json[key] = value
        }
        let members = json.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\($0.value)" }
        return "{" + members.joined(separator: ",") + "}"
    }

    private func tokens(
        status: Int = 200, _ json: String, previous: String? = nil, requireScopes: Bool = true
    ) throws -> OAuthTokens {
        try GoogleOAuth.tokens(
            from: HTTPResponse(status: status, body: Data(json.utf8)),
            previousRefreshToken: previous, requireScopes: requireScopes, now: now)
    }

    @Test("A full response becomes tokens that expire expires_in seconds from now")
    func success() throws {
        let json = body(["scope": "\"\(tasksScope) \(calendarScope) openid\""])
        #expect(
            try tokens(json, previous: "old")
                == OAuthTokens(
                    accessToken: "ya29.a", refreshToken: "1//r",
                    expiresAt: now.addingTimeInterval(3599)))
    }

    @Test("A lowercase bearer type and a fractional lifetime are accepted")
    func lenientFields() throws {
        let result = try tokens(body(["token_type": #""bearer""#, "expires_in": "10.5"]))
        #expect(result.expiresAt == now.addingTimeInterval(10.5))
    }

    @Test("A missing or empty refresh token keeps the previous one", arguments: [nil, "\"\""])
    func keepsPrevious(refreshToken: String?) throws {
        let json = body(["refresh_token": refreshToken])
        #expect(try tokens(json, previous: "1//old").refreshToken == "1//old")
    }

    @Test("With no refresh token anywhere the response is unexpected", arguments: [nil, ""])
    func noRefreshToken(previous: String?) {
        #expect(throws: GoogleAPIError.unexpectedResponse) {
            try tokens(body(["refresh_token": nil]), previous: previous)
        }
    }

    @Test(
        "A malformed 200 is unexpected",
        arguments: [
            ["token_type": #""mac""#], ["access_token": "\"\""], ["access_token": nil],
            ["expires_in": #""3599""#], ["expires_in": nil], ["token_type": nil],
            ["access_token": "42"],
        ] as [[String: String?]])
    func malformed(fields: [String: String?]) {
        #expect(throws: GoogleAPIError.unexpectedResponse) { try tokens(body(fields)) }
    }

    @Test("A body that is not JSON is unexpected", arguments: ["not json", "", "{", "[]"])
    func notJSON(json: String) {
        #expect(throws: GoogleAPIError.unexpectedResponse) { try tokens(json) }
    }

    @Test("A missing scope fails only when scopes are required")
    func missingScope() throws {
        let json = body(["scope": nil])
        #expect(throws: GoogleAPIError.missingScopes) { try tokens(json, requireScopes: true) }
        #expect(try tokens(json, requireScopes: false).accessToken == "ya29.a")
    }

    @Test(
        "A scope without both read-only scopes fails, required or not",
        arguments: [calendarScope, tasksScope, "", calendarScope + tasksScope], [true, false])
    func partialScope(granted: String, requireScopes: Bool) {
        #expect(throws: GoogleAPIError.missingScopes) {
            try tokens(body(["scope": "\"\(granted)\""]), requireScopes: requireScopes)
        }
    }

    @Test("400 invalid_grant means the sign-in is gone")
    func invalidGrant() {
        #expect(throws: GoogleAPIError.signedOut) {
            try tokens(status: 400, #"{"error":"invalid_grant","error_description":"Bad"}"#)
        }
    }

    @Test(
        "Any other failure status fails the sign-in",
        arguments: [
            (400, #"{"error":"invalid_request"}"#), (400, "not json"), (400, ""),
            (401, #"{"error":"invalid_grant"}"#), (500, #"{"error":"invalid_grant"}"#),
            (500, "oops"),
        ])
    func otherStatus(status: Int, json: String) {
        #expect(throws: GoogleAPIError.authorizationFailed) { try tokens(status: status, json) }
    }

    @Test("A success body with a status other than 200 fails the sign-in")
    func non200Success() {
        #expect(throws: GoogleAPIError.authorizationFailed) { try tokens(status: 201, body()) }
    }
}
