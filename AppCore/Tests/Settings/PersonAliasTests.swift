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
