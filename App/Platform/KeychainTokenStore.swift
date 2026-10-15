import AppCore
import Foundation

/// Keeps the Google tokens in the Keychain as JSON.
struct KeychainTokenStore: TokenStore {
    private let item: KeychainItem

    init(service: String = "name.tkcs.magenda.google") {
        item = KeychainItem(service: service, account: "oauth-tokens")
    }

    func load() throws -> OAuthTokens? {
        guard let data = try item.read() else { return nil }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    func save(_ tokens: OAuthTokens) throws {
        try item.write(JSONEncoder().encode(tokens))
    }

    func delete() throws {
        try item.delete()
    }
}
