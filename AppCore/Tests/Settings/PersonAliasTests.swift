// AppCore's `PersonAlias`, `PickedContact` and `FixtureContactPicker`: the People rules entry and
// the contact the picker hands back.

import Testing

@testable import AppCore

@Suite("Person aliases")
struct PersonAliasTests {
    @Test("A name and email are folded and lowercased")
    func foldsAndLowercases() {
        let alias = PersonAlias(name: "  Zoë ", email: " Zoe.K@Example.COM ")
        #expect(alias?.key == BinderText.fold("Zoë"))
        #expect(alias?.email == "zoe.k@example.com")
    }

    @Test(
        "A blank name or a blank email gives no alias",
        arguments: [("", "a@example.com"), ("  \n", "a@example.com"), ("Zoe", ""), ("Zoe", " \t ")])
    func blankGivesNil(name: String, email: String) {
        #expect(PersonAlias(name: name, email: email) == nil)
    }

    @Test("Several comma-separated names become one alias each for the trimmed, lowercased email")
    func aliasesSplitsNames() {
        let aliases = PersonAlias.aliases(names: "Bob, Robert ,bobby", email: " R@X.com ")
        #expect(aliases.map(\.key) == ["bob", "robert", "bobby"])
        #expect(aliases.allSatisfy { $0.email == "r@x.com" })
    }

    @Test("Empty pieces are dropped and a name repeated once folded is kept once")
    func aliasesDropsEmptyAndDuplicates() {
        #expect(PersonAlias.aliases(names: ", Bob,,", email: "r@x.com").map(\.key) == ["bob"])
        #expect(PersonAlias.aliases(names: "Bob, bob, BÓB", email: "r@x.com").map(\.key) == ["bob"])
    }

    @Test("A blank email or no names gives no aliases")
    func aliasesBlankGivesNone() {
        #expect(PersonAlias.aliases(names: "Bob", email: "  ").isEmpty)
        #expect(PersonAlias.aliases(names: ", ,", email: "r@x.com").isEmpty)
    }

    @Test("Groups collect the names of one email, sorted, and the emails are sorted")
    func groupsByEmail() {
        let groups = PersonAlias.groups(["bob": "r@x.com", "robert": "r@x.com", "nora": "n@x.com"])
        #expect(
            groups == [
                PersonGroup(email: "n@x.com", names: ["nora"]),
                PersonGroup(email: "r@x.com", names: ["bob", "robert"]),
            ])
        #expect(PersonAlias.groups([:]).isEmpty)
    }

    @Test(
        "The suggested name prefers the nickname, then the given name, then the family name",
        arguments: [
            ("Robert", "Bob", "Smith", "Bob"),
            ("Robert", "", "Smith", "Robert"),
            ("", "", "Smith", "Smith"),
            (" Robert ", "  ", "Smith", "Robert"),
            ("", "", "", ""),
        ])
    func suggestedName(given: String, nickname: String, family: String, expected: String) {
        let contact = PickedContact(
            givenName: given, nickname: nickname, familyName: family, email: "a@example.com")
        #expect(contact.suggestedName == expected)
    }

    @Test("The fixture picker picks the fixture contact")
    @MainActor
    func fixturePicker() async {
        #expect(await FixtureContactPicker().pickContact() == PickedContact.fixture)
    }
}
