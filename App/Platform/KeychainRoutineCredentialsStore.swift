import AppCore
import Foundation

/// Keeps the end-of-day routine's fire URL and token the user entered in the Keychain as JSON.
struct KeychainRoutineCredentialsStore: RoutineCredentialsStore {
    private let item: KeychainItem

    init(service: String = "name.tkcs.magenda.routine") {
        item = KeychainItem(service: service, account: "trigger")
    }

    func load() throws -> RoutineCredentials? {
        guard let data = try item.read() else { return nil }
        return try JSONDecoder().decode(RoutineCredentials.self, from: data)
    }

    func save(_ credentials: RoutineCredentials) throws {
        try item.write(JSONEncoder().encode(credentials))
    }

    func delete() throws {
        try item.delete()
    }
}
