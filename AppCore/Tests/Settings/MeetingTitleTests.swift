// AppCore's meeting-page title rules.

import AppCore
import Foundation
import Testing

@Suite("Meeting titles")
struct MeetingTitleTests {
    private let prefixes = BinderRules.default.titlePrefixes

    @Test(
        "Prefixes and separators are stripped",
        arguments: [
            ("REMINDER // Decision about the office move", "Decision about the office move"),
            ("(temp) weekly budget / invoice review", "Budget / invoice review"),
            ("FW: Fwd: Contract deadline", "Contract deadline"),
            ("Weekly", "Weekly"),
            ("Weekly sync", "Sync"),
            (
                "CONDITIONAL Product - Cross Team Roadmap Planning Alignment & Tracking",
                "Product - Cross Team Roadmap Planning Alignment & Tracking"
            ),
            ("  Team   sync ", "Team sync"),
        ])
    func stripping(title: String, expected: String) {
        #expect(MeetingTitle.stripped(title, prefixes: prefixes) == expected)
    }

    @Test("A recurring event is keyed by its series, a one-off by its folded title")
    func keys() {
        #expect(MeetingTitle.key(originalTitle: "Sync", recurringEventID: "abc") == "r:abc")
        let oneOff = MeetingTitle.key(originalTitle: "Árvíz Sync", recurringEventID: nil)
        #expect(oneOff == "t:arviz sync")
        #expect(MeetingTitle.key(originalTitle: "Sync", recurringEventID: "") == "t:sync")
    }

    @Test("A non-empty short name wins and a blank one is ignored")
    func pageTitle() {
        var rules = BinderRules.default
        #expect(
            MeetingTitle.pageTitle(
                originalTitle: "(temp) weekly sync", recurringEventID: "abc", rules: rules)
                == "Sync")
        rules.shortNames["r:abc"] = "  Team \n sync "
        #expect(
            MeetingTitle.pageTitle(
                originalTitle: "(temp) weekly sync", recurringEventID: "abc", rules: rules)
                == "Team sync")
        rules.shortNames["r:abc"] = "   "
        #expect(
            MeetingTitle.pageTitle(
                originalTitle: "(temp) weekly sync", recurringEventID: "abc", rules: rules)
                == "Sync")
        rules.shortNames["t:lonely"] = "Short"
        #expect(
            MeetingTitle.pageTitle(originalTitle: "Lonely", recurringEventID: nil, rules: rules)
                == "Short")
    }
}
