import Foundation

/// Everything the user can configure about how an agenda is built and drawn.
public struct AgendaSettings: Equatable, Codable, Sendable {
    /// The font family.
    public var fontPack: FontPack
    /// The theme colors.
    public var colors: ThemeColors
    /// The calendars to read; empty means the primary calendar.
    public var calendarIDs: [String]
    /// The title of the Google Tasks list holding personal tasks.
    public var todoListTitle: String
    /// The title of the list holding delegated tasks; empty means no delegated page.
    public var delegatedListTitle: String
    /// The binder rules.
    public var rules: BinderRules

    /// Creates settings; the defaults are what a fresh install uses.
    public init(
        fontPack: FontPack = .outfit, colors: ThemeColors = .default, calendarIDs: [String] = [],
        todoListTitle: String = "Claude", delegatedListTitle: String = "Claude Delegations",
        rules: BinderRules = .default
    ) {
        self.fontPack = fontPack
        self.colors = colors
        self.calendarIDs = calendarIDs
        self.todoListTitle = todoListTitle
        self.delegatedListTitle = delegatedListTitle
        self.rules = rules
    }

    /// The font pack and colors as a theme.
    public var theme: Theme {
        Theme(fontPack: fontPack, colors: colors)
    }

    /// Decodes settings written by any build; an unknown font pack becomes Outfit and a missing
    /// field keeps its default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AgendaSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        let fontPackName = try value(.fontPack, defaults.fontPack.rawValue)
        self.init(
            fontPack: FontPack(rawValue: fontPackName) ?? defaults.fontPack,
            colors: try value(.colors, defaults.colors),
            calendarIDs: try value(.calendarIDs, defaults.calendarIDs),
            todoListTitle: try value(.todoListTitle, defaults.todoListTitle),
            delegatedListTitle: try value(.delegatedListTitle, defaults.delegatedListTitle),
            rules: try value(.rules, defaults.rules))
    }

    private enum CodingKeys: String, CodingKey {
        case fontPack, colors, calendarIDs, todoListTitle, delegatedListTitle, rules
    }
}

/// Where the settings are kept between launches.
public protocol SettingsStore: Sendable {
    /// The saved settings, or the defaults when nothing usable is saved.
    func load() -> AgendaSettings
    /// Saves `settings`.
    func save(_ settings: AgendaSettings)
}

/// A store that keeps the settings in memory, for tests and previews.
public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    // `settings` is only read or written while `lock` is held, which is what makes this safe.
    private let lock = NSLock()
    private var settings: AgendaSettings

    /// Creates a store holding `settings`.
    public init(_ settings: AgendaSettings = AgendaSettings()) {
        self.settings = settings
    }

    /// The held settings.
    public func load() -> AgendaSettings {
        lock.withLock { settings }
    }

    /// Replaces the held settings.
    public func save(_ settings: AgendaSettings) {
        lock.withLock { self.settings = settings }
    }
}
