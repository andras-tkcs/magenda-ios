// AppCore's hand-off stores: saving hand-offs and PDFs, listing them, and the file layout.

import Foundation
import Testing

@testable import AppCore

@Suite("Hand-off store")
struct HandoffStoreTests {
    /// The stores whose shared behaviour is tested.
    enum Kind: CaseIterable, Sendable {
        case memory
        case file
    }

    private static func date(_ dayOfMonth: Int = 26) throws -> CalendarDay {
        try #require(CalendarDay(year: 2026, month: 10, day: dayOfMonth))
    }

    private static func dayID(_ dayOfMonth: Int = 26) throws -> HandoffID {
        HandoffID(date: try date(dayOfMonth), part: nil)
    }

    private static func partID(_ number: Int, _ dayOfMonth: Int = 26) throws -> HandoffID {
        HandoffID(date: try date(dayOfMonth), part: number)
    }

    private static func handoff(_ dayOfMonth: Int = 26) throws -> DayHandoff {
        DayHandoff(
            date: try date(dayOfMonth), checksum: "sha256:abc",
            pages: [HandoffPage(page: 1, key: "overview")], tasks: [], delegated: [])
    }

    private static func part(_ number: Int, _ dayOfMonth: Int = 26) throws -> DayHandoff {
        DayHandoff(
            date: try date(dayOfMonth), checksum: "sha256:def",
            pages: [HandoffPage(page: 1, key: "meeting:cal|a")], tasks: [], delegated: [],
            part: HandoffPart(number: number, meetingKey: "meeting:cal|a", title: "A"))
    }

    private func withStore(_ kind: Kind, _ body: (any HandoffStore) throws -> Void) throws {
        switch kind {
        case .memory:
            try body(InMemoryHandoffStore())
        case .file:
            try withDirectory { try body(FileHandoffStore(directory: $0)) }
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    @Test(
        "A hand-off is nil until saved, then comes back equal, and saving replaces it",
        arguments: Kind.allCases)
    func handoffRoundTrip(kind: Kind) throws {
        try withStore(kind) { store in
            let id = try Self.dayID()
            #expect(try store.handoff(id) == nil)
            var handoff = try Self.handoff()
            try store.save(handoff)
            #expect(try store.handoff(id) == handoff)
            handoff.stage = .uploaded
            try store.save(handoff)
            #expect(try store.handoff(id) == handoff)
        }
    }

    @Test("handoffs() lists the saved hand-offs, newest date first", arguments: Kind.allCases)
    func newestFirst(kind: Kind) throws {
        try withStore(kind) { store in
            #expect(try store.handoffs().isEmpty)
            for day in [24, 27, 26] { try store.save(try Self.handoff(day)) }
            #expect(try store.handoffs().map(\.date.day) == [27, 26, 24])
        }
    }

    @Test(
        "A PDF is nil until saved; deleting it keeps the hand-off and is fine without one",
        arguments: Kind.allCases)
    func pdfRoundTrip(kind: Kind) throws {
        try withStore(kind) { store in
            let id = try Self.dayID()
            try store.deletePDF(for: id)
            #expect(try store.pdf(for: id) == nil)
            try store.save(try Self.handoff())
            try store.savePDF(Data([1, 2]), for: id)
            #expect(try store.pdf(for: id) == Data([1, 2]))
            try store.savePDF(Data([3]), for: id)
            #expect(try store.pdf(for: id) == Data([3]))
            try store.deletePDF(for: id)
            #expect(try store.pdf(for: id) == nil)
            #expect(try store.handoff(id) == (try Self.handoff()))
            try store.deletePDF(for: id)
        }
    }

    @Test(
        "Deleting a hand-off removes it and its PDF, leaves other days, and is fine without one",
        arguments: Kind.allCases)
    func deleteHandoff(kind: Kind) throws {
        try withStore(kind) { store in
            let date = try Self.date()
            try store.deleteHandoff(for: date)
            try store.save(try Self.handoff(26))
            try store.save(try Self.handoff(27))
            try store.savePDF(Data([1]), for: try Self.dayID())
            try store.deleteHandoff(for: date)
            #expect(try store.handoff(try Self.dayID()) == nil)
            #expect(try store.pdf(for: try Self.dayID()) == nil)
            #expect(try store.handoffs().map(\.date.day) == [27])
        }
    }

    @Test(
        "A day and its parts are saved, read and listed with the day first, then parts by number",
        arguments: Kind.allCases)
    func partsRoundTrip(kind: Kind) throws {
        try withStore(kind) { store in
            try store.save(try Self.part(2))
            try store.save(try Self.handoff(26))
            try store.save(try Self.part(1))
            try store.save(try Self.handoff(27))
            try store.save(try Self.part(1, 24))
            let listed = try store.handoffs()
            #expect(
                listed.map(\.id) == [
                    try Self.dayID(27), try Self.dayID(26), try Self.partID(1), try Self.partID(2),
                    try Self.partID(1, 24),
                ])
            #expect(try store.handoff(try Self.partID(2)) == (try Self.part(2)))
            #expect(try store.handoff(try Self.dayID()) == (try Self.handoff()))
            #expect(try store.handoff(try Self.partID(3)) == nil)
            var again = try Self.part(1)
            again.stage = .uploaded
            try store.save(again)
            #expect(try store.handoff(try Self.partID(1)) == again)
            #expect(try store.handoffs().count == 5)
        }
    }

    @Test("A part's PDF is kept apart from the day's PDF and other parts", arguments: Kind.allCases)
    func partPDFs(kind: Kind) throws {
        try withStore(kind) { store in
            let day = try Self.dayID()
            let one = try Self.partID(1)
            let two = try Self.partID(2)
            try store.savePDF(Data([0]), for: day)
            try store.savePDF(Data([1]), for: one)
            try store.savePDF(Data([2]), for: two)
            #expect(try store.pdf(for: one) == Data([1]))
            #expect(try store.pdf(for: two) == Data([2]))
            try store.deletePDF(for: one)
            #expect(try store.pdf(for: one) == nil)
            #expect(try store.pdf(for: day) == Data([0]))
            #expect(try store.pdf(for: two) == Data([2]))
            try store.deletePDF(for: one)
        }
    }

    @Test(
        "Deleting a date's hand-off removes its parts and every PDF, and leaves other dates",
        arguments: Kind.allCases)
    func deleteHandoffRemovesParts(kind: Kind) throws {
        try withStore(kind) { store in
            for number in [1, 2] {
                try store.save(try Self.part(number))
                try store.savePDF(Data([1]), for: try Self.partID(number))
            }
            try store.save(try Self.handoff(26))
            try store.savePDF(Data([1]), for: try Self.dayID())
            try store.save(try Self.part(1, 27))
            try store.savePDF(Data([1]), for: try Self.partID(1, 27))
            try store.deleteHandoff(for: try Self.date())
            #expect(try store.handoffs().map(\.id) == [try Self.partID(1, 27)])
            for id in [try Self.dayID(), try Self.partID(1), try Self.partID(2)] {
                #expect(try store.handoff(id) == nil)
                #expect(try store.pdf(for: id) == nil)
            }
            #expect(try store.pdf(for: try Self.partID(1, 27)) == Data([1]))
        }
    }

    @Test("handoffs() is empty when the directory does not exist")
    func missingDirectory() throws {
        try withDirectory { directory in
            let store = FileHandoffStore(directory: directory)
            let listed = try store.handoffs()
            #expect(listed.isEmpty)
        }
    }

    @Test("handoffs() skips non-date folders, folders without a hand-off and damaged files")
    func skipsUnusableFolders() throws {
        try withDirectory { directory in
            let store = FileHandoffStore(directory: directory)
            try store.save(try Self.handoff(26))
            try write("{}", to: directory.appending(path: "notes/handoff.json"))
            try write("{}", to: directory.appending(path: "2026-10-27-extra/handoff.json"))
            try write("not json", to: directory.appending(path: "2026-10-25/handoff.json"))
            try FileManager.default.createDirectory(
                at: directory.appending(path: "2026-10-24"), withIntermediateDirectories: true)
            try write("x", to: directory.appending(path: "stray.txt"))
            try write("x", to: directory.appending(path: "2026-10-23"))
            #expect(try store.handoffs().map(\.date.day) == [26])
            #expect(throws: HandoffStoreError.unreadable) { try store.handoff(try Self.dayID(25)) }
            #expect(try store.handoff(try Self.dayID(24)) == nil)
        }
    }

    @Test("A handoff.json saved with another version is unreadable")
    func otherVersion() throws {
        try withDirectory { directory in
            let store = FileHandoffStore(directory: directory)
            try store.save(try Self.handoff())
            let file = directory.appending(path: "2026-10-26/handoff.json")
            let text = try String(contentsOf: file, encoding: .utf8)
                .replacingOccurrences(of: #""version":1"#, with: #""version":2"#)
            try write(text, to: file)
            #expect(throws: HandoffStoreError.unreadable) { try store.handoff(try Self.dayID()) }
        }
    }

    @Test("handoffs() skips part files with other names and records with another ID")
    func skipsMisnamedParts() throws {
        try withDirectory { directory in
            let store = FileHandoffStore(directory: directory)
            try store.save(try Self.handoff())
            try store.save(try Self.part(1))
            let folder = directory.appending(path: "2026-10-26")
            let record = try String(
                contentsOf: folder.appending(path: "part-1.json"), encoding: .utf8)
            for name in [
                "part-x.json", "part-0.json", "part-10000.json", "part-01.json", "part-+2.json",
                "part-.json", "part-2.json",
            ] {
                try write(record, to: folder.appending(path: name))
            }
            // A day record that holds a part, and a part file that holds the day.
            try write(record, to: directory.appending(path: "2026-10-25/handoff.json"))
            let day = try String(
                contentsOf: folder.appending(path: "handoff.json"), encoding: .utf8)
            try write(day, to: directory.appending(path: "2026-10-24/part-1.json"))
            #expect(
                try store.handoffs().map(\.id) == [try Self.dayID(), try Self.partID(1)])
            #expect(throws: HandoffStoreError.unreadable) { try store.handoff(try Self.dayID(25)) }
            #expect(throws: HandoffStoreError.unreadable) {
                try store.handoff(try Self.partID(2))
            }
            #expect(throws: HandoffStoreError.unreadable) {
                try store.handoff(try Self.partID(1, 24))
            }
        }
    }

    @Test("A day.pdf that cannot be read is unreadable")
    func unreadablePDF() throws {
        try withDirectory { directory in
            try FileManager.default.createDirectory(
                at: directory.appending(path: "2026-10-26/day.pdf"),
                withIntermediateDirectories: true)
            #expect(throws: HandoffStoreError.unreadable) {
                try FileHandoffStore(directory: directory).pdf(for: try Self.dayID())
            }
        }
    }

    @Test("A directory that is a regular file makes listing unreadable and saving unwritable")
    func directoryIsAFile() throws {
        try withDirectory { directory in
            try Data([0]).write(to: directory)
            let store = FileHandoffStore(directory: directory)
            #expect(throws: HandoffStoreError.unreadable) { try store.handoffs() }
            #expect(throws: HandoffStoreError.unwritable) { try store.save(try Self.handoff()) }
            #expect(throws: HandoffStoreError.unwritable) {
                try store.savePDF(Data([1]), for: try Self.dayID())
            }
        }
    }

    @Test("The file store writes only the day's and the parts' files under its directory")
    func writesOnlyUnderDirectory() throws {
        try withDirectory { directory in
            let store = FileHandoffStore(directory: directory)
            try store.save(try Self.handoff())
            try store.savePDF(Data([1]), for: try Self.dayID())
            try store.save(try Self.part(2))
            try store.savePDF(Data([2]), for: try Self.partID(2))
            let paths = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            #expect(
                Set(paths) == [
                    "2026-10-26", "2026-10-26/handoff.json", "2026-10-26/day.pdf",
                    "2026-10-26/part-2.json", "2026-10-26/part-2.pdf",
                ])
            try store.deletePDF(for: try Self.dayID())
            try store.deletePDF(for: try Self.partID(2))
            let after = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            #expect(
                Set(after) == ["2026-10-26", "2026-10-26/handoff.json", "2026-10-26/part-2.json"])
        }
    }
}
