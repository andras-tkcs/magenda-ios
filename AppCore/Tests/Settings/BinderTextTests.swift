// AppCore's text comparison for the binder rules.

import AppCore
import Foundation
import Testing

@Suite("Binder text")
struct BinderTextTests {
    @Test("Folding ignores case, accents and spacing")
    func folding() {
        #expect(BinderText.fold("Zoltán") == "zoltan")
        #expect(BinderText.fold("ZOLTAN") == "zoltan")
        #expect(BinderText.fold("  Árvíztűrő\ttükörfúrógép ") == "arvizturo tukorfurogep")
    }

    @Test(
        "A phrase at the start of a title matches as a whole word",
        arguments: [
            ("Lunch", "Lunch", true),
            ("lunch with Sam", "Lunch", true),
            ("Lunch: team", "Lunch", true),
            ("Lunchtime", "Lunch", false),
            ("Team lunch", "Lunch", false),
            ("FW:Budget", "FW:", true),
            ("Anything", "", false),
        ])
    func startsWith(text: String, phrase: String, expected: Bool) {
        #expect(BinderText.startsWithPhrase(text, phrase) == expected)
    }

    @Test(
        "A phrase anywhere in a title matches as a whole word",
        arguments: [
            ("OOO - Budapest", "OOO", true),
            ("Summer vacation", "Vacation", true),
            ("Out of office (Nora)", "Out of Office", true),
            ("Photography", "PTO", false),
            ("Anything", "", false),
            ("Hi", "Longer phrase", false),
        ])
    func contains(text: String, phrase: String, expected: Bool) {
        #expect(BinderText.containsPhrase(text, phrase) == expected)
    }

    @Test(
        "A location marker is not out of office",
        arguments: BinderRules.default.outOfOfficeWords)
    func homeIsNotOutOfOffice(word: String) {
        #expect(!BinderText.containsPhrase("Home", word))
    }
}
