// AppCore's binder stores: saving a day and its handwriting, and the file layout and its errors.

import Foundation
import Testing

@testable import AppCore

@Suite("Binder store")
struct BinderStoreTests {
    /// The stores whose shared behaviour is tested.
    enum Kind: CaseIterable, Sendable {
        case memory
        case file
    }

    private static func date(_ dayOfMonth: Int = 30) throws -> CalendarDay {
        try #require(CalendarDay(year: 2026, month: 9, day: dayOfMonth))
    }

    private static func binderDay(_ dayOfMonth: Int = 30) throws -> BinderDay {
        BinderDay(
            content: AgendaContent(
                date: try date(dayOfMonth), todoItems: [], schedule: [], meetings: ["A"],
                meetingIDs: ["a"], delegated: []),
            theme: Theme())
    }

    /// Runs `body` with a store of `kind`; a file store lives in a fresh directory that is
    /// removed afterwards.
    private func withStore(
        _ kind: Kind, _ body: (any BinderStore) throws -> Void
    ) throws {
        switch kind {
        case .memory:
            try body(InMemoryBinderStore())
        case .file:
            try withDirectory { try body(FileBinderStore(directory: $0)) }
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

    private let meetingKey = PageKey.meeting("a|b/c")

    @Test("A day is nil until saved, then comes back equal", arguments: Kind.allCases)
    func dayRoundTrip(kind: Kind) throws {
        try withStore(kind) { store in
            let date = try Self.date()
            #expect(try store.day(date) == nil)
            let day = try Self.binderDay()
            try store.saveDay(day)
            #expect(try store.day(date) == day)
        }
    }

    @Test("A new day has no handwriting", arguments: Kind.allCases)
    func newDayHasNoInk(kind: Kind) throws {
        try withStore(kind) { store in
            let date = try Self.date()
            #expect(try store.ink(on: date).isEmpty)
        }
    }

    @Test(
        "Handwriting for two pages comes back, saving again replaces, empty data removes",
        arguments: Kind.allCases)
    func inkRoundTrip(kind: Kind) throws {
        try withStore(kind) { store in
            let date = try Self.date()
            try store.saveInk(Data([1, 2]), for: meetingKey, on: date)
            try store.saveInk(Data([3]), for: .overview, on: date)
            #expect(try store.ink(on: date) == [meetingKey: Data([1, 2]), .overview: Data([3])])
            try store.saveInk(Data([4, 5, 6]), for: meetingKey, on: date)
            let replaced: [PageKey: Data] = [meetingKey: Data([4, 5, 6]), .overview: Data([3])]
            #expect(try store.ink(on: date) == replaced)
            try store.saveInk(Data(), for: meetingKey, on: date)
            #expect(try store.ink(on: date) == [.overview: Data([3])])
            try store.saveInk(Data(), for: .notes, on: date)
            #expect(try store.ink(on: date) == [.overview: Data([3])])
        }
    }

    @Test("Two days do not see each other's handwriting", arguments: Kind.allCases)
    func daysAreSeparate(kind: Kind) throws {
        try withStore(kind) { store in
            let (first, second, third) = (try Self.date(29), try Self.date(30), try Self.date(28))
            try store.saveInk(Data([1]), for: .overview, on: first)
            try store.saveInk(Data([2]), for: .overview, on: second)
            #expect(try store.ink(on: first) == [.overview: Data([1])])
            #expect(try store.ink(on: second) == [.overview: Data([2])])
            #expect(try store.ink(on: third).isEmpty)
        }
    }

    @Test("A day.json that cannot be decoded is unreadable")
    func garbageDay() throws {
        try withDirectory { directory in
            let date = try Self.date()
            try write("not json", to: directory.appending(path: "2026-09-30/day.json"))
            #expect(throws: BinderStoreError.unreadable) {
                try FileBinderStore(directory: directory).day(date)
            }
        }
    }

    @Test("An index.json that cannot be decoded is unreadable, also when saving")
    func garbageIndex() throws {
        try withDirectory { directory in
            let date = try Self.date()
            try write("[", to: directory.appending(path: "2026-09-30/ink/index.json"))
            let store = FileBinderStore(directory: directory)
            #expect(throws: BinderStoreError.unreadable) { try store.ink(on: date) }
            #expect(throws: BinderStoreError.unreadable) {
                try store.saveInk(Data([1]), for: .overview, on: date)
            }
        }
    }

    @Test("Index entries with an unknown key, a bad file name or no file are skipped")
    func skippedEntries() throws {
        try withDirectory { directory in
            let inkFolder = directory.appending(path: "2026-09-30/ink")
            try write(
                """
                {"overview": "page-3.pkdata", "bogus:x": "page-1.pkdata",
                 "notes": "page-9.pkdata", "meeting:a": "../escape", "meeting:b": "page-1.txt",
                 "meeting:c": "page-x.pkdata", "meeting:d": "page-.pkdata"}
                """, to: inkFolder.appending(path: "index.json"))
            try Data([7]).write(to: inkFolder.appending(path: "page-3.pkdata"))
            try Data([8]).write(to: inkFolder.appending(path: "page-1.pkdata"))
            try Data([9]).write(to: inkFolder.appending(path: "page-1.txt"))
            let store = FileBinderStore(directory: directory)
            let date = try Self.date()
            #expect(try store.ink(on: date) == [.overview: Data([7])])
        }
    }

    @Test("A directory that is a regular file makes saving throw unwritable")
    func directoryIsAFile() throws {
        try withDirectory { directory in
            try Data([0]).write(to: directory)
            let store = FileBinderStore(directory: directory)
            let day = try Self.binderDay()
            #expect(throws: BinderStoreError.unwritable) { try store.saveDay(day) }
            #expect(throws: BinderStoreError.unwritable) {
                try store.saveInk(Data([1]), for: .overview, on: day.date)
            }
        }
    }

    @Test("Page file numbers continue after the highest one in the index")
    func pageNumbersContinue() throws {
        try withDirectory { directory in
            let inkFolder = directory.appending(path: "2026-09-30/ink")
            try write(
                #"{"overview": "page-7.pkdata", "notes": "page-2.pkdata"}"#,
                to: inkFolder.appending(path: "index.json"))
            let store = FileBinderStore(directory: directory)
            let date = try Self.date()
            try store.saveInk(Data([1]), for: .delegated(0), on: date)
            let index = try JSONDecoder().decode(
                [String: String].self,
                from: Data(contentsOf: inkFolder.appending(path: "index.json")))
            #expect(
                index == [
                    "overview": "page-7.pkdata", "notes": "page-2.pkdata",
                    "delegated:0": "page-8.pkdata",
                ])
            #expect(try Data(contentsOf: inkFolder.appending(path: "page-8.pkdata")) == Data([1]))
        }
    }

    @Test("Saving again rewrites the file of the key's entry and removing deletes it")
    func entryFileIsReused() throws {
        try withDirectory { directory in
            let date = try Self.date()
            let inkFolder = directory.appending(path: "2026-09-30/ink")
            let store = FileBinderStore(directory: directory)
            try store.saveInk(Data([1]), for: .overview, on: date)
            try store.saveInk(Data([2]), for: .overview, on: date)
            #expect(try Data(contentsOf: inkFolder.appending(path: "page-1.pkdata")) == Data([2]))
            try store.saveInk(Data(), for: .overview, on: date)
            let removed = inkFolder.appending(path: "page-1.pkdata")
            #expect(!FileManager.default.fileExists(atPath: removed.path))
            #expect(try store.ink(on: date).isEmpty)
        }
    }

    @Test("The file store writes only generated names under its directory")
    func writesOnlyUnderDirectory() throws {
        try withDirectory { directory in
            let store = FileBinderStore(directory: directory)
            let day = try Self.binderDay()
            try store.saveDay(day)
            try store.saveInk(Data([1]), for: meetingKey, on: day.date)
            let paths = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            #expect(
                Set(paths) == [
                    "2026-09-30", "2026-09-30/day.json", "2026-09-30/ink",
                    "2026-09-30/ink/index.json", "2026-09-30/ink/page-1.pkdata",
                ])
        }
    }
}
