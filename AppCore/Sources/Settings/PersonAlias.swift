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

    /// The name to put in "Name in tasks": the nickname, else the given name, else the family
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
