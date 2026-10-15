import AppCore
import Foundation

/// Keeps the agenda settings in `UserDefaults` as JSON.
struct UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    // `UserDefaults` is documented as thread-safe.
    private let defaults: UserDefaults
    private let key = "agendaSettings"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> AgendaSettings {
        guard let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(AgendaSettings.self, from: data)
        else { return AgendaSettings() }
        return settings
    }

    func save(_ settings: AgendaSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
