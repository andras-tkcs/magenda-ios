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

    private static func handoff(_ dayOfMonth: Int = 26) throws -> DayHandoff {
        DayHandoff(
            date: try date(dayOfMonth), checksum: "sha256:abc",
            pages: [HandoffPage(page: 1, key: "overview")], tasks: [], delegated: [])
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
            let date = try Self.date()
            #expect(try store.handoff(date) == nil)
            var handoff = try Self.handoff()
            try store.save(handoff)
            #expect(try store.handoff(date) == handoff)
            handoff.stage = .uploaded
            try store.save(handoff)
            #expect(try store.handoff(date) == handoff)
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
            let date = try Self.date()
            try store.deletePDF(for: date)
            #expect(try store.pdf(for: date) == nil)
            try store.save(try Self.handoff())
            try store.savePDF(Data([1, 2]), for: date)
            #expect(try store.pdf(for: date) == Data([1, 2]))
            try store.savePDF(Data([3]), for: date)
            #expect(try store.pdf(for: date) == Data([3]))
            try store.deletePDF(for: date)
            #expect(try store.pdf(for: date) == nil)
            #expect(try store.handoff(date) == (try Self.handoff()))
            try store.deletePDF(for: date)
        }
    }

    @Test("handoffs() is empty when the directory does not exist")
    func missingDirectory() throws {
        try withDirectory { directory in
            #expect(try FileHandoffStore(directory: directory).handoffs().isEmpty)
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
            #expect(try store.handoffs().map(\.date.day) == [26])
            #expect(throws: HandoffStoreError.unreadable) { try store.handoff(try Self.date(25)) }
            #expect(try store.handoff(try Self.date(24)) == nil)
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
            #expect(throws: HandoffStoreError.unreadable) { try store.handoff(try Self.date()) }
        }
    }

    @Test("A day.pdf that cannot be read is unreadable")
    func unreadablePDF() throws {
        try withDirectory { directory in
            try FileManager.default.createDirectory(
                at: directory.appending(path: "2026-10-26/day.pdf"),
                withIntermediateDirectories: true)
            #expect(throws: HandoffStoreError.unreadable) {
                try FileHandoffStore(directory: directory).pdf(for: try Self.date())
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
                try store.savePDF(Data([1]), for: try Self.date())
            }
        }
    }

    @Test("The file store writes only handoff.json and day.pdf under its directory")
    func writesOnlyUnderDirectory() throws {
        try withDirectory { directory in
            let store = FileHandoffStore(directory: directory)
            try store.save(try Self.handoff())
            try store.savePDF(Data([1]), for: try Self.date())
            let paths = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            #expect(
                Set(paths) == ["2026-10-26", "2026-10-26/handoff.json", "2026-10-26/day.pdf"])
            try store.deletePDF(for: try Self.date())
            let after = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            #expect(Set(after) == ["2026-10-26", "2026-10-26/handoff.json"])
        }
    }
}
