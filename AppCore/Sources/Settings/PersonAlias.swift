import Foundation

/// One entry of the People rules: a name used in tasks and the attendee email it stands for.
public struct PersonAlias: Equatable, Sendable {
    /// `BinderText.fold` of the trimmed name; the key in `BinderRules.personAliases`.
    public let key: String
    /// The trimmed, lowercased email.
    public let email: String

    /// An alias from what the person typed; nil when the name or the email is blank once trimmed.
    public init?(name: String, email: String) {
        let key = BinderText.fold(name.trimmingCharacters(in: .whitespacesAndNewlines))
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, !email.isEmpty else { return nil }
        self.key = key
        self.email = email
    }
}

extension PersonAlias {
    /// One alias per comma-separated name of `names`, all for `email`, in the order typed; a name
    /// repeated once folded is kept once. Empty when the email is blank or no name is left once
    /// trimmed.
    public static func aliases(names: String, email: String) -> [PersonAlias] {
        var seen = Set<String>()
        return names.split(separator: ",", omittingEmptySubsequences: false).compactMap {
            guard let alias = PersonAlias(name: String($0), email: email),
                seen.insert(alias.key).inserted
            else { return nil }
            return alias
        }
    }

    /// The aliases of `personAliases` grouped by email: one group per email, sorted by email,
    /// each with its folded names sorted.
    public static func groups(_ personAliases: [String: String]) -> [PersonGroup] {
        Dictionary(grouping: personAliases, by: \.value)
            .map { PersonGroup(email: $0.key, names: $0.value.map(\.key).sorted()) }
            .sorted { $0.email < $1.email }
    }
}

/// One person of the People rules: an email and every name that stands for it.
public struct PersonGroup: Equatable, Sendable {
    /// The lowercased email.
    public let email: String
    /// The folded names, sorted.
    public let names: [String]

    /// Creates a group.
    public init(email: String, names: [String]) {
        self.email = email
        self.names = names
    }
}

/// One email address picked from the person's contacts, with the contact's names.
public struct PickedContact: Equatable, Sendable {
    /// The contact's given name; empty when it has none.
    public let givenName: String
    /// The contact's nickname; empty when it has none.
    public let nickname: String
    /// The contact's family name; empty when it has none.
    public let familyName: String
    /// The picked email address.
    public let email: String

    /// A contact from its names and the email that was picked.
    public init(givenName: String, nickname: String, familyName: String, email: String) {
        self.givenName = givenName
        self.nickname = nickname
        self.familyName = familyName
        self.email = email
    }

    /// The name to put in "Names in tasks": the nickname, else the given name, else the family
    /// name, trimmed; empty when the contact has none.
    public var suggestedName: String {
        [nickname, givenName, familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    /// The contact the UI-test fixtures and previews pick.
    public static let fixture = PickedContact(
        givenName: "Nora", nickname: "", familyName: "Kim", email: "nora.kim@example.com")
}

/// Asks the person to pick one email address from their contacts.
public protocol ContactPicking: Sendable {
    /// The picked contact, or nil when the person cancels or no picker can be shown.
    @MainActor func pickContact() async -> PickedContact?
}

/// A picker for UI tests and previews that always picks `PickedContact.fixture`.
public struct FixtureContactPicker: ContactPicking {
    /// A picker that picks the fixture contact.
    public init() {}

    /// Always `PickedContact.fixture`.
    public func pickContact() async -> PickedContact? { .fixture }
}
