/// A page the person added: a blank copy of `source`'s printed page, placed right after `after`.
public struct ExtraPage: Equatable, Codable, Sendable {
    /// The page's identity, unique within the day.
    public let id: String
    /// The page it follows.
    public var after: PageKey
    /// The page it copies; never an `.extra` key.
    public let source: PageKey

    /// Creates an added page.
    public init(id: String, after: PageKey, source: PageKey) {
        self.id = id
        self.after = after
        self.source = source
    }
}

/// A page that left the content on a later render but carries handwriting, kept with the content
/// it was laid out from.
public struct RetainedPage: Equatable, Codable, Sendable {
    /// The page's key.
    public let key: PageKey
    /// The content the page is laid out from.
    public let content: AgendaContent

    /// Creates a retained page.
    public init(key: PageKey, content: AgendaContent) {
        self.key = key
        self.content = content
    }
}

/// What a day's binder is drawn from: the content snapshot taken at Render, the theme, the pages
/// the person added and the pages kept for their handwriting.
public struct BinderDay: Equatable, Codable, Sendable {
    /// The version of the saved format; a day saved with another version cannot be decoded.
    public static let formatVersion = 1

    /// The format version; always `formatVersion` when created.
    public let version: Int
    /// The content snapshot taken at Render.
    public var content: AgendaContent
    /// The theme the day is drawn with.
    public var theme: Theme
    /// The pages the person added.
    public var extras: [ExtraPage]
    /// The pages kept for their handwriting after they left the content.
    public var retained: [RetainedPage]

    /// The day the binder is for.
    public var date: CalendarDay { content.date }

    private enum CodingKeys: String, CodingKey {
        case version, content, theme, extras, retained
    }

    /// Creates a binder day of the current format.
    public init(
        content: AgendaContent, theme: Theme, extras: [ExtraPage] = [],
        retained: [RetainedPage] = []
    ) {
        self.version = Self.formatVersion
        self.content = content
        self.theme = theme
        self.extras = extras
        self.retained = retained
    }

    /// Decodes a day; throws when it was saved with another format version.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.formatVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container,
                debugDescription: "Unsupported binder version \(version).")
        }
        self.version = version
        self.content = try container.decode(AgendaContent.self, forKey: .content)
        self.theme = try container.decode(Theme.self, forKey: .theme)
        self.extras = try container.decode([ExtraPage].self, forKey: .extras)
        self.retained = try container.decode([RetainedPage].self, forKey: .retained)
    }

    /// Adds a blank copy of `page` right after it, identified by `id`. The copy's source is the
    /// source of `page` when that is itself an added page; extras that followed `page` now follow
    /// the new one.
    public mutating func addPage(after page: PageKey, id: String) {
        var source = page
        if case .extra(let existing) = page,
            let extra = extras.first(where: { $0.id == existing })
        {
            source = extra.source
        }
        for index in extras.indices where extras[index].after == page {
            extras[index].after = .extra(id)
        }
        extras.append(ExtraPage(id: id, after: page, source: source))
    }

    /// Removes the added page `id`; pages that followed it follow the page it followed. Nothing
    /// happens when there is no such page.
    public mutating func removePage(id: String) {
        guard let removed = extras.first(where: { $0.id == id }) else {
            return
        }
        for index in extras.indices where extras[index].after == .extra(id) {
            extras[index].after = removed.after
        }
        extras.removeAll { $0.id == id }
    }
}
