import AppCore
import Foundation

/// Keeps the Google client ID and optional secret the user entered in the Keychain as JSON.
struct KeychainClientCredentialsStore: ClientCredentialsStore {
    private let item: KeychainItem

    init(service: String = "name.tkcs.magenda.google-client") {
        item = KeychainItem(service: service, account: "client")
    }

    func load() throws -> GoogleClientCredentials? {
        guard let data = try item.read() else { return nil }
        return try JSONDecoder().decode(GoogleClientCredentials.self, from: data)
    }

    func save(_ credentials: GoogleClientCredentials) throws {
        try item.write(JSONEncoder().encode(credentials))
    }

    func delete() throws {
        try item.delete()
    }
}
