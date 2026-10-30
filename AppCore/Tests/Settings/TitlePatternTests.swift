// AppCore's `TitlePattern`: validating and matching meeting-title patterns.

import Foundation
import Testing

@testable import AppCore

@Suite("Title pattern")
struct TitlePatternTests {
    @Test("A pattern is trimmed")
    func trimmed() {
        #expect(TitlePattern.validated("  delivery sync [0-9]+ \n") == "delivery sync [0-9]+")
    }

    @Test("An empty or blank pattern is refused")
    func blank() {
        #expect(TitlePattern.validated("") == nil)
        #expect(TitlePattern.validated("   ") == nil)
    }

    @Test("A pattern of 200 characters is accepted, one of 201 is not")
    func length() {
        #expect(TitlePattern.validated(String(repeating: "a", count: 200)) != nil)
        #expect(TitlePattern.validated(String(repeating: "a", count: 201)) == nil)
    }

    @Test("A pattern that does not compile is refused, also one that escapes the wrapper")
    func invalid() {
        #expect(TitlePattern.validated("delivery sync [0-9") == nil)
        #expect(TitlePattern.validated("a)|(b") == nil)
        #expect(TitlePattern.validated("delivery sync [0-9]+") == "delivery sync [0-9]+")
    }

    @Test("A pattern must match the whole title, ignoring case and spacing")
    func wholeTitle() {
        let pattern = "delivery sync [0-9]+"
        #expect(TitlePattern.matches(pattern, title: "Delivery Sync 2026"))
        #expect(TitlePattern.matches(pattern, title: "delivery  sync 7"))
        #expect(!TitlePattern.matches(pattern, title: "Delivery Sync"))
        #expect(!TitlePattern.matches(pattern, title: "Delivery Sync 2026 prep"))
    }

    @Test("Accents are ignored on both sides")
    func accents() {
        #expect(TitlePattern.matches("réunion .*", title: "Reunion lundi"))
        #expect(TitlePattern.matches("réunion .*", title: "RÉUNION lundi"))
    }

    @Test("The pattern is not lowercased, so an escape keeps its meaning")
    func escapes() {
        #expect(TitlePattern.matches(#"\D+"#, title: "abc"))
        #expect(!TitlePattern.matches(#"\D+"#, title: "ab1"))
    }

    @Test("An invalid pattern matches nothing")
    func invalidMatchesNothing() {
        #expect(!TitlePattern.matches("delivery sync [0-9", title: "delivery sync [0-9"))
        #expect(!TitlePattern.matches("", title: ""))
    }
}
