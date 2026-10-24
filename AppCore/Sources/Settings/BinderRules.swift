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
    /// A summary skill name per meeting title as entered, see ``SummarySkill``.
    public var summarySkills: [String: String]

    /// Creates a set of rules.
    public init(
        personalBlocks: [String], titlePrefixes: [String], outOfOfficeWords: [String],
        shortNames: [String: String], personAliases: [String: String], lookAheadDays: Int,
        summarySkills: [String: String] = [:]
    ) {
        self.personalBlocks = personalBlocks
        self.titlePrefixes = titlePrefixes
        self.outOfOfficeWords = outOfOfficeWords
        self.shortNames = shortNames
        self.personAliases = personAliases
        self.lookAheadDays = lookAheadDays
        self.summarySkills = summarySkills
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
        lookAheadDays: 5,
        summarySkills: [:])

    private enum CodingKeys: String, CodingKey {
        case personalBlocks, titlePrefixes, outOfOfficeWords, shortNames, personAliases
        case lookAheadDays, summarySkills
    }

    /// Decodes rules written by any build; a missing field keeps its default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BinderRules.default
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        self.init(
            personalBlocks: try value(.personalBlocks, defaults.personalBlocks),
            titlePrefixes: try value(.titlePrefixes, defaults.titlePrefixes),
            outOfOfficeWords: try value(.outOfOfficeWords, defaults.outOfOfficeWords),
            shortNames: try value(.shortNames, defaults.shortNames),
            personAliases: try value(.personAliases, defaults.personAliases),
            lookAheadDays: try value(.lookAheadDays, defaults.lookAheadDays),
            summarySkills: try value(.summarySkills, defaults.summarySkills))
    }
}
