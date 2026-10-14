import Foundation

/// The fixed, editable rules that replace the judgement calls of the manual binder workflow.
public struct BinderRules: Equatable, Codable, Sendable {
    /// Titles that mark a personal block or a break; matching events are left out.
    public var personalBlocks: [String]
    /// Prefixes dropped from a meeting-page title.
    public var titlePrefixes: [String]
    /// Words that mark an all-day out-of-office event.
    public var outOfOfficeWords: [String]
    /// A short meeting-page title per `MeetingTitle.key`.
    public var shortNames: [String: String]
    /// `BinderText.fold` of a name used in tasks, mapped to a lowercased attendee email.
    public var personAliases: [String: String]
    /// How many days ahead tasks are looked at; the builder clamps it to 0…14.
    public var lookAheadDays: Int

    /// Creates a set of rules.
    public init(
        personalBlocks: [String], titlePrefixes: [String], outOfOfficeWords: [String],
        shortNames: [String: String], personAliases: [String: String], lookAheadDays: Int
    ) {
        self.personalBlocks = personalBlocks
        self.titlePrefixes = titlePrefixes
        self.outOfOfficeWords = outOfOfficeWords
        self.shortNames = shortNames
        self.personAliases = personAliases
        self.lookAheadDays = lookAheadDays
    }

    /// The rules the app starts with.
    public static let `default` = BinderRules(
        personalBlocks: ["Lunch", "Start the day"],
        titlePrefixes: [
            "REMINDER //", "REMINDER:", "(temp)", "FW:", "Fwd:", "CONDITIONAL", "weekly",
        ],
        outOfOfficeWords: ["OOO", "Out of Office", "Vacation", "PTO"],
        shortNames: [:],
        personAliases: [:],
        lookAheadDays: 5)

    private enum CodingKeys: String, CodingKey {
        case personalBlocks, titlePrefixes, outOfOfficeWords, shortNames, personAliases
        case lookAheadDays
    }

    /// Decodes rules written by any build; a missing field keeps its default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BinderRules.default
        self.init(
            personalBlocks: try container.decodeIfPresent([String].self, forKey: .personalBlocks)
                ?? defaults.personalBlocks,
            titlePrefixes: try container.decodeIfPresent([String].self, forKey: .titlePrefixes)
                ?? defaults.titlePrefixes,
            outOfOfficeWords: try container.decodeIfPresent(
                [String].self, forKey: .outOfOfficeWords) ?? defaults.outOfOfficeWords,
            shortNames: try container.decodeIfPresent([String: String].self, forKey: .shortNames)
                ?? defaults.shortNames,
            personAliases: try container.decodeIfPresent(
                [String: String].self, forKey: .personAliases) ?? defaults.personAliases,
            lookAheadDays: try container.decodeIfPresent(Int.self, forKey: .lookAheadDays)
                ?? defaults.lookAheadDays)
    }
}
