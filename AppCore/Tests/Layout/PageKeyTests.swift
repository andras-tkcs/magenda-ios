// AppCore's `PageKey`: its storage string, parsing and single-string Codable form.

import Foundation
import Testing

@testable import AppCore

@Suite("Page keys")
struct PageKeyTests {
    private static let keys: [PageKey] = [
        .overview, .delegated(0), .delegated(3), .meeting("primary|abc:def"), .meeting(""),
        .notes, .extra("x1"), .routine("r1"),
    ]

    @Test("Every key round-trips through its storage string", arguments: PageKeyTests.keys)
    func storageRoundTrip(_ key: PageKey) {
        #expect(PageKey(storageString: key.storageString) == key)
    }

    @Test("Storage strings have the documented shape")
    func storageStrings() {
        #expect(PageKey.overview.storageString == "overview")
        #expect(PageKey.delegated(2).storageString == "delegated:2")
        #expect(PageKey.meeting("a:b|c").storageString == "meeting:a:b|c")
        #expect(PageKey.meeting("").storageString == "meeting:")
        #expect(PageKey.notes.storageString == "notes")
        #expect(PageKey.extra("e").storageString == "extra:e")
        #expect(PageKey.routine("r").storageString == "routine:r")
    }

    @Test("A meeting ID may contain colons and pipes, or be empty")
    func meetingIDs() {
        #expect(PageKey(storageString: "meeting:a:b|c") == .meeting("a:b|c"))
        #expect(PageKey(storageString: "meeting:") == .meeting(""))
    }

    @Test(
        "Malformed strings have no key",
        arguments: [
            "", "delegated:x", "delegated:-1", "extra:", "routine:", "overview:x", "notes:x",
            "unknown",
        ])
    func malformed(_ text: String) {
        #expect(PageKey(storageString: text) == nil)
    }

    @Test("Keys encode as one JSON string and decode from it", arguments: PageKeyTests.keys)
    func jsonRoundTrip(_ key: PageKey) throws {
        let data = try JSONEncoder().encode(key)
        #expect(String(decoding: data, as: UTF8.self) == "\"\(key.storageString)\"")
        #expect(try JSONDecoder().decode(PageKey.self, from: data) == key)
    }

    @Test("An unknown string does not decode")
    func bogus() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PageKey.self, from: Data("\"bogus\"".utf8))
        }
    }
}
