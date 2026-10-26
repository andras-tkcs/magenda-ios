import AppCore
import Foundation

/// Keeps each summary routine's fire URL and token the user entered in the Keychain as JSON, one
/// item per routine ID.
struct KeychainSummaryRoutineCredentialsStore: SummaryRoutineCredentialsStore {
    private let service: String

    init(service: String = "name.tkcs.magenda.summary-routine") {
        self.service = service
    }

    func load(id: String) throws -> RoutineCredentials? {
        guard let data = try item(id).read() else { return nil }
        return try JSONDecoder().decode(RoutineCredentials.self, from: data)
    }

    func save(_ credentials: RoutineCredentials, id: String) throws {
        try item(id).write(JSONEncoder().encode(credentials))
    }

    func delete(id: String) throws {
        try item(id).delete()
    }

    private func item(_ id: String) -> KeychainItem {
        KeychainItem(service: service, account: id)
    }
}
