// AppCore's `SummarySkill`: valid skill names and the title lookup.

import Testing

@testable import AppCore

@Suite("Summary skill")
struct SummarySkillTests {
    @Test(
        "Valid skill names",
        arguments: [
            "a", "1", "meeting-summary", "my_skill", "ns:skill.v2",
            String(repeating: "a", count: 64),
        ])
    func validNames(_ name: String) {
        #expect(SummarySkill.isValidName(name))
    }

    @Test(
        "Invalid skill names",
        arguments: [
            "", "-lead", "_lead", ".lead", ":lead", "with space", "slash/y", "é", "ab\u{E9}",
            "日本", String(repeating: "a", count: 65),
        ])
    func invalidNames(_ name: String) {
        #expect(!SummarySkill.isValidName(name))
    }

    @Test("A page title match gives the skill")
    func pageTitle() {
        #expect(
            SummarySkill.skill(
                pageTitle: "Sync", originalTitle: "Team sync", skills: ["Sync": "s1"]) == "s1")
    }

    @Test("An original title match gives the skill")
    func originalTitle() {
        #expect(
            SummarySkill.skill(
                pageTitle: "Sync", originalTitle: "Team sync", skills: ["Team sync": "s2"])
                == "s2")
    }

    @Test("Matching folds case and diacritics")
    func folding() {
        #expect(
            SummarySkill.skill(
                pageTitle: "RÉSUMÉ review", originalTitle: "x", skills: ["resume Review": "s3"])
                == "s3")
    }

    @Test("When several titles match, the first by sort order wins")
    func firstWins() {
        let skills = ["b sync": "second", "A Sync": "first"]
        #expect(
            SummarySkill.skill(pageTitle: "a sync", originalTitle: "B Sync", skills: skills)
                == "first")
    }

    @Test("No match, or an invalid stored skill, gives nil")
    func noMatch() {
        #expect(SummarySkill.skill(pageTitle: "x", originalTitle: "y", skills: ["z": "s"]) == nil)
        #expect(SummarySkill.skill(pageTitle: "x", originalTitle: "y", skills: [:]) == nil)
        #expect(
            SummarySkill.skill(pageTitle: "x", originalTitle: "y", skills: ["x": "-bad"]) == nil)
    }
}
