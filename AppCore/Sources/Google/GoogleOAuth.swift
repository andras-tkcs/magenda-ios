import Foundation

/// The Google OAuth client the person created in their own Google Cloud project and entered in
/// the app. Only a well-formed client ID (and, if given, a plausible secret) gets this far.
public struct GoogleOAuthConfiguration: Equatable, Sendable {
    /// The client ID, such as `123-abc.apps.googleusercontent.com`.
    public let clientID: String
    /// The client secret, for client types that have one; `nil` for an iOS client.
    public let clientSecret: String?

    /// Validates a client ID and an optional secret, both trimmed of surrounding whitespace.
    ///
    /// The client ID must look like
    /// `<digits>-<lowercase letters and digits>.apps.googleusercontent.com`. An empty secret
    /// means none; a non-empty one must be at most 200 characters with no whitespace or control
    /// characters. Anything else returns `nil`.
    public init?(clientID: String, clientSecret: String? = nil) {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidClientID(id) else {
            return nil
        }
        let secret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard secret.isEmpty || Self.isValidClientSecret(secret) else {
            return nil
        }
        self.clientID = id
        self.clientSecret = secret.isEmpty ? nil : secret
    }

    /// The custom URL scheme Google redirects to: the client ID reversed, as Google requires for
    /// an iOS client.
    public var redirectScheme: String {
        "com.googleusercontent.apps." + String(clientID.dropLast(Self.clientIDSuffix.count))
    }

    /// The redirect URI sent to Google.
    public var redirectURI: String {
        redirectScheme + ":/oauth2redirect"
    }

    /// The scopes the app asks for, and needs all of.
    public static let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/tasks.readonly",
        "https://www.googleapis.com/auth/drive",
    ]

    private static let clientIDSuffix = ".apps.googleusercontent.com"

    // Checked byte by byte so no Unicode equivalence can let a look-alike character through.
    private static func isValidClientID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        let suffix = Array(clientIDSuffix.utf8)
        guard bytes.count > suffix.count, bytes.suffix(suffix.count).elementsEqual(suffix),
            let dash = bytes.firstIndex(of: UInt8(ascii: "-"))
        else {
            return false
        }
        let number = bytes[..<dash]
        let name = bytes[(dash + 1)..<(bytes.count - suffix.count)]
        return !number.isEmpty && number.allSatisfy(\.isASCIIDigit) && !name.isEmpty
            && name.allSatisfy { $0.isASCIIDigit || (0x61...0x7A).contains($0) }
    }

    private static func isValidClientSecret(_ secret: String) -> Bool {
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        return secret.count <= 200 && !secret.unicodeScalars.contains { forbidden.contains($0) }
    }
}

extension UInt8 {
    fileprivate var isASCIIDigit: Bool { (0x30...0x39).contains(self) }
}

/// What the app needs to start a sign-in and to check its callback.
public struct AuthorizationRequest: Equatable, Sendable {
    /// The Google consent page to open.
    public let url: URL
    /// The random value Google must echo back in the callback.
    public let state: String
    /// The PKCE code verifier, sent with the code exchange.
    public let verifier: String

    /// Creates a request.
    public init(url: URL, state: String, verifier: String) {
        self.url = url
        self.state = state
        self.verifier = verifier
    }
}

/// A signed-in session's tokens. They are secrets: kept in the Keychain and never logged.
public struct OAuthTokens: Codable, Equatable, Sendable {
    /// The short-lived token sent with every API request.
    public let accessToken: String
    /// The long-lived token that gets a new access token.
    public let refreshToken: String
    /// When the access token stops working.
    public let expiresAt: Date
    /// The scopes the grant covers; `nil` for tokens stored before the app recorded them.
    public let scopes: [String]?

    /// Creates a set of tokens.
    public init(
        accessToken: String, refreshToken: String, expiresAt: Date, scopes: [String]? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
    }
}

/// OAuth 2.0 authorization code with PKCE (RFC 7636, S256) against Google, as pure functions:
/// building the requests and reading the answers. Nothing here sends anything.
public enum GoogleOAuth {
    private static let unreserved = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// A new sign-in: a 64-character verifier and a 32-character state drawn from `random`, and
    /// the consent URL carrying the verifier's S256 challenge.
    public static func authorizationRequest(
        configuration: GoogleOAuthConfiguration, random: inout some RandomNumberGenerator,
        hasher: any SHA256Hashing
    ) -> AuthorizationRequest {
        let verifier = randomString(length: 64, using: &random)
        let state = randomString(length: 32, using: &random)
        let query = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(
                name: "scope", value: GoogleOAuthConfiguration.scopes.joined(separator: " ")),
            URLQueryItem(
                name: "code_challenge", value: codeChallenge(verifier: verifier, hasher: hasher)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return AuthorizationRequest(
            url: httpsURL(host: "accounts.google.com", path: "/o/oauth2/v2/auth", query: query),
            state: state, verifier: verifier)
    }

    /// The S256 code challenge for `verifier`: base64url without padding of its SHA-256 digest.
    public static func codeChallenge(verifier: String, hasher: any SHA256Hashing) -> String {
        hasher.sha256(Data(verifier.utf8)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The authorization code from Google's redirect back to the app.
    ///
    /// Throws `.authorizationFailed` unless the scheme is the configured redirect scheme and the
    /// single `state` equals the request's; then `.authorizationCancelled` for
    /// `error=access_denied`, `.authorizationFailed` for any other error or a missing code.
    public static func authorizationCode(
        from callback: URL, for request: AuthorizationRequest,
        configuration: GoogleOAuthConfiguration
    ) throws -> String {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
            components.scheme == configuration.redirectScheme,
            onlyValue(of: "state", in: components) == request.state
        else {
            throw GoogleAPIError.authorizationFailed
        }
        if components.queryItems?.contains(where: { $0.name == "error" }) == true {
            throw onlyValue(of: "error", in: components) == "access_denied"
                ? GoogleAPIError.authorizationCancelled : GoogleAPIError.authorizationFailed
        }
        guard let code = onlyValue(of: "code", in: components), !code.isEmpty else {
            throw GoogleAPIError.authorizationFailed
        }
        return code
    }

    /// Exchanges an authorization code for tokens.
    public static func tokenRequest(
        code: String, verifier: String, configuration: GoogleOAuthConfiguration
    ) -> HTTPRequest {
        formRequest(
            "/token",
            [("code", code)] + clientFields(configuration) + [
                ("redirect_uri", configuration.redirectURI),
                ("code_verifier", verifier),
                ("grant_type", "authorization_code"),
            ])
    }

    /// Gets a new access token with a refresh token.
    public static func refreshRequest(
        refreshToken: String, configuration: GoogleOAuthConfiguration
    ) -> HTTPRequest {
        formRequest(
            "/token",
            clientFields(configuration) + [
                ("refresh_token", refreshToken),
                ("grant_type", "refresh_token"),
            ])
    }

    /// Revokes a token, which ends the grant it belongs to.
    public static func revokeRequest(token: String) -> HTTPRequest {
        formRequest("/revoke", [("token", token)])
    }

    /// Reads the token endpoint's answer.
    ///
    /// A 200 needs a non-empty `access_token`, a numeric `expires_in` and a `Bearer` token type,
    /// else `.unexpectedResponse`. The refresh token is the response's, else
    /// `previousRefreshToken`, else `.unexpectedResponse`. The granted scopes are the response's
    /// `scope`, else `previousScopes`; when they are unknown or lack any of
    /// `GoogleOAuthConfiguration.scopes` the answer is `.missingScopes`, and so is a missing
    /// `scope` when `requireScopes` is set. A 400 `invalid_grant` is `.signedOut`; any other
    /// status is `.authorizationFailed`.
    public static func tokens(
        from response: HTTPResponse, previousRefreshToken: String?, previousScopes: [String]?,
        requireScopes: Bool, now: Date
    ) throws -> OAuthTokens {
        guard response.status == 200 else {
            let error = try? JSONDecoder().decode(ErrorBody.self, from: response.body)
            throw response.status == 400 && error?.error == "invalid_grant"
                ? GoogleAPIError.signedOut : GoogleAPIError.authorizationFailed
        }
        guard let body = try? JSONDecoder().decode(TokenBody.self, from: response.body),
            !body.accessToken.isEmpty, body.tokenType.lowercased() == "bearer"
        else {
            throw GoogleAPIError.unexpectedResponse
        }
        let responseScopes = body.scope.map { $0.split(separator: " ").map(String.init) }
        guard let scopes = responseScopes ?? (requireScopes ? nil : previousScopes),
            Set(scopes).isSuperset(of: GoogleOAuthConfiguration.scopes)
        else {
            throw GoogleAPIError.missingScopes
        }
        let refreshToken = [body.refreshToken, previousRefreshToken].compactMap { $0 }
            .first { !$0.isEmpty }
        guard let refreshToken else {
            throw GoogleAPIError.unexpectedResponse
        }
        return OAuthTokens(
            accessToken: body.accessToken, refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(body.expiresIn), scopes: scopes)
    }

    private struct TokenBody: Decodable {
        let accessToken: String
        let expiresIn: Double
        let tokenType: String
        let refreshToken: String?
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
            case refreshToken = "refresh_token"
            case scope
        }
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    private static func randomString(
        length: Int, using random: inout some RandomNumberGenerator
    ) -> String {
        String(
            (0..<length).map { _ in
                unreserved[Int.random(in: 0..<unreserved.count, using: &random)]
            })
    }

    // A duplicated parameter counts as missing, so an injected second `state` or `code` cannot win.
    private static func onlyValue(of name: String, in components: URLComponents) -> String? {
        let values = (components.queryItems ?? []).filter { $0.name == name }.map(\.value)
        return values.count == 1 ? values[0] : nil
    }

    private static func clientFields(
        _ configuration: GoogleOAuthConfiguration
    ) -> [(String, String)] {
        [("client_id", configuration.clientID)]
            + (configuration.clientSecret.map { [("client_secret", $0)] } ?? [])
    }

    private static func formRequest(_ path: String, _ fields: [(String, String)]) -> HTTPRequest {
        let body = fields.map { "\(formEncoded($0.0))=\(formEncoded($0.1))" }.joined(separator: "&")
        return HTTPRequest(
            method: .post, url: httpsURL(host: "oauth2.googleapis.com", path: path),
            headers: ["Content-Type": "application/x-www-form-urlencoded"], body: Data(body.utf8))
    }

    // Stricter than `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)`, which leaves
    // `+` and `/` alone; a `+` in a form body would arrive at Google as a space.
    private static func formEncoded(_ value: String) -> String {
        var encoded = ""
        for byte in value.utf8 {
            let scalar = Unicode.Scalar(byte)
            if byte < 0x80 && unreserved.contains(Character(scalar)) {
                encoded.unicodeScalars.append(scalar)
            } else {
                encoded += String(format: "%%%02X", byte)
            }
        }
        return encoded
    }

    // A fixed host and absolute path always form a URL, but `URLComponents.url` is optional.
    // Replacing a placeholder, rather than falling back to one, leaves no branch that never runs.
    private static func httpsURL(
        host: String, path: String, query: [URLQueryItem]? = nil
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query
        var url = URL(fileURLWithPath: "/")
        if let built = components.url {
            url = built
        }
        return url
    }
}
