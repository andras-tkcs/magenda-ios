// AppCore's `SummaryRoutine`: names, IDs and the title lookup.

import Foundation
import Testing

@testable import AppCore

@Suite("Summary routine")
struct SummaryRoutineTests {
    @Test("A name is trimmed")
    func trimmed() {
        #expect(SummaryRoutine.validatedName("  Weekly recap \n") == "Weekly recap")
    }

    @Test("A name of 40 characters is accepted, one of 41 is not")
    func length() {
        #expect(SummaryRoutine.validatedName(String(repeating: "a", count: 40)) != nil)
        #expect(SummaryRoutine.validatedName(String(repeating: "a", count: 41)) == nil)
    }

    @Test("An empty name, a blank one and one with a control character are refused")
    func refused() {
        #expect(SummaryRoutine.validatedName("") == nil)
        #expect(SummaryRoutine.validatedName(" \n\t ") == nil)
        #expect(SummaryRoutine.validatedName("a\u{7}b") == nil)
        #expect(SummaryRoutine.validatedName("a\tb") == nil)
    }

    @Test("The invalid-name message is word for word")
    func message() {
        #expect(SummaryRoutine.invalidNameMessage == "Use 1 to 40 characters for the name.")
    }

    @Test("A lowercase UUID is a valid ID")
    func validID() {
        #expect(SummaryRoutine.isValidID("0123abcd-4567-89ab-cdef-0123456789ab"))
    }

    @Test(
        "Anything else is not",
        arguments: [
            "", "0123ABCD-4567-89ab-cdef-0123456789ab", "0123abcd-4567-89ab-cdef-0123456789a",
            "0123abcd-4567-89ab-cdef-0123456789abc", "0123abcd_4567-89ab-cdef-0123456789ab",
            "0123abcd45678-9ab-cdef-0123456789ab-", "0123abcd-4567-89ab-cdef-0123456789ag",
            "0123abcd-4567-89ab-cdef-0123456789a\u{E9}", "--------------------------------------",
        ])
    func invalidID(_ id: String) {
        #expect(!SummaryRoutine.isValidID(id))
    }

    @Test("A made ID is valid and different each time")
    func madeID() {
        let first = SummaryRoutine.makeID()
        #expect(SummaryRoutine.isValidID(first))
        #expect(first != SummaryRoutine.makeID())
    }

    @Test("A routine has no page of its own unless it is given one")
    func pageDefault() {
        #expect(!SummaryRoutine(id: "a", name: "A").hasPage)
        #expect(SummaryRoutine(id: "a", name: "A", hasPage: true).hasPage)
    }

    @Test("A routine stored without hasPage decodes without a page, and hasPage round-trips")
    func pageCoding() throws {
        let old = try JSONDecoder().decode(
            SummaryRoutine.self, from: Data(#"{"id":"a","name":"A"}"#.utf8))
        #expect(old == SummaryRoutine(id: "a", name: "A"))
        let routine = SummaryRoutine(id: "a", name: "A", hasPage: true)
        let data = try JSONEncoder().encode(routine)
        #expect(try JSONDecoder().decode(SummaryRoutine.self, from: data) == routine)
    }

    @Test("hasPage is left out of the JSON when false")
    func pageEncodingOmitted() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let plain = try encoder.encode(SummaryRoutine(id: "a", name: "A"))
        #expect(String(decoding: plain, as: UTF8.self) == #"{"id":"a","name":"A"}"#)
        let paged = try encoder.encode(SummaryRoutine(id: "a", name: "A", hasPage: true))
        #expect(
            String(decoding: paged, as: UTF8.self) == #"{"hasPage":true,"id":"a","name":"A"}"#)
    }

    @Test("A title match is folded, on the page title or the original")
    func foldedMatch() {
        let rules = ["team SYNC": ["a", "b"]]
        #expect(
            SummaryRoutines.routineIDs(pageTitle: "Team Sync", originalTitle: "x", rules: rules)
                == ["a", "b"])
        #expect(
            SummaryRoutines.routineIDs(pageTitle: "x", originalTitle: "Téam sync", rules: rules)
                == ["a", "b"])
    }

    @Test("When several entries match, the title that sorts first wins")
    func firstTitleWins() {
        let rules = ["Sync": ["s"], "Team sync": ["t"]]
        #expect(
            SummaryRoutines.routineIDs(pageTitle: "Sync", originalTitle: "Team sync", rules: rules)
                == ["s"])
    }

    @Test("A repeated ID is returned once, in its first place")
    func deduplicated() {
        #expect(
            SummaryRoutines.routineIDs(
                pageTitle: "Sync", originalTitle: "Sync", rules: ["Sync": ["b", "a", "b", "a"]])
                == ["b", "a"])
    }

    @Test("No matching entry gives no IDs")
    func noMatch() {
        let rules = ["Sync": ["a"]]
        let ids = SummaryRoutines.routineIDs(
            pageTitle: "Lunch", originalTitle: "Lunch", rules: rules)
        #expect(ids.isEmpty)
    }

    @Test("Routines come in the available order and an unknown ID is dropped")
    func routinesByID() {
        let one = SummaryRoutine(id: "1", name: "One")
        let two = SummaryRoutine(id: "2", name: "Two")
        let three = SummaryRoutine(id: "3", name: "Three")
        #expect(
            SummaryRoutines.routines(ids: ["3", "9", "1"], in: [one, two, three]) == [one, three])
        #expect(SummaryRoutines.routines(ids: [], in: [one]).isEmpty)
    }
}
