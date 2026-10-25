import Foundation

/// Why a hand-off could not be read or saved.
public enum HandoffStoreError: Error, Equatable {
    /// What is saved exists but cannot be read.
    case unreadable
    /// Something could not be written.
    case unwritable
}

/// Where finished days, the meetings sent before them, and their PDFs are kept on the device.
public protocol HandoffStore: Sendable {
    /// Every readable hand-off, in `HandoffID.listOrder`.
    func handoffs() throws -> [DayHandoff]
    /// The hand-off `id` names, or nil when there is none.
    func handoff(_ id: HandoffID) throws -> DayHandoff?
    /// Saves `handoff`, replacing what was saved for its `id`.
    func save(_ handoff: DayHandoff) throws
    /// The PDF saved for `id`, or nil when there is none.
    func pdf(for id: HandoffID) throws -> Data?
    /// Saves the PDF of `id`.
    func savePDF(_ data: Data, for id: HandoffID) throws
    /// Removes the PDF of `id`; having none is not an error.
    func deletePDF(for id: HandoffID) throws
    /// Removes the day's hand-off, every part of `date` and every PDF; having none is not an error.
    func deleteHandoff(for date: CalendarDay) throws
}

/// A store that keeps hand-offs in memory, for tests and previews.
public final class InMemoryHandoffStore: HandoffStore, @unchecked Sendable {
    // `held` and `pdfs` are only read or written while `lock` is held, which is what makes this
    // safe.
    private let lock = NSLock()
    private var held: [HandoffID: DayHandoff] = [:]
    private var pdfs: [HandoffID: Data] = [:]

    /// Creates an empty store.
    public init() {}

    /// The held hand-offs, in `HandoffID.listOrder`.
    public func handoffs() throws -> [DayHandoff] {
        lock.withLock { held.values.sorted { HandoffID.listOrder($0.id, $1.id) } }
    }

    /// The held hand-off `id` names.
    public func handoff(_ id: HandoffID) throws -> DayHandoff? {
        lock.withLock { held[id] }
    }

    /// Replaces the held hand-off.
    public func save(_ handoff: DayHandoff) throws {
        lock.withLock { held[handoff.id] = handoff }
    }

    /// The held PDF of `id`.
    public func pdf(for id: HandoffID) throws -> Data? {
        lock.withLock { pdfs[id] }
    }

    /// Replaces the held PDF.
    public func savePDF(_ data: Data, for id: HandoffID) throws {
        lock.withLock { pdfs[id] = data }
    }

    /// Drops the held PDF.
    public func deletePDF(for id: HandoffID) throws {
        lock.withLock { pdfs[id] = nil }
    }

    /// Drops every held hand-off and PDF of `date`.
    public func deleteHandoff(for date: CalendarDay) throws {
        lock.withLock {
            held = held.filter { $0.key.date != date }
            pdfs = pdfs.filter { $0.key.date != date }
        }
    }
}

/// A store that keeps hand-offs as files under one directory.
///
/// Each day has a folder named after its date, holding `handoff.json` and `day.pdf` for the day
/// and `part-<n>.json` and `part-<n>.pdf` for each meeting sent early. Every name is made by the
/// app, never taken from Google data.
public struct FileHandoffStore: HandoffStore {
    private let directory: URL
    private let writeOptions: Data.WritingOptions

    /// Creates a store under `directory`; folders are created when something is saved. Every write
    /// is atomic and also uses `protection`, so the app can choose a file-protection class.
    public init(directory: URL, protection: Data.WritingOptions = []) {
        self.directory = directory
        writeOptions = protection.union(.atomic)
    }

    /// Every hand-off with a readable record file, in `HandoffID.listOrder`; `[]` when the
    /// directory does not exist. Folders that are not named after a date, damaged files, part
    /// files with another name than `part-<n>.json` for `n` in 1 to 9999, and files whose record
    /// has another ID than their name are skipped. Throws `.unreadable` when the directory cannot
    /// be listed.
    public func handoffs() throws -> [DayHandoff] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw HandoffStoreError.unreadable
        }
        let dates = names.compactMap { name in
            CalendarDay(isoString: name).flatMap { $0.isoString == name ? $0 : nil }
        }
        let found = dates.flatMap { date in
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder(date).path))
            return (files ?? []).compactMap { Self.id(ofRecordNamed: $0, on: date) }
        }
        return found.compactMap { try? handoff($0) }.sorted {
            HandoffID.listOrder($0.id, $1.id)
        }
    }

    /// The saved hand-off, or nil when its record file does not exist; throws `.unreadable` when
    /// it cannot be decoded or holds another ID than the one asked for.
    public func handoff(_ id: HandoffID) throws -> DayHandoff? {
        let file = folder(id.date).appending(path: Self.recordName(id))
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let handoff: DayHandoff
        do {
            handoff = try JSONDecoder().decode(DayHandoff.self, from: Data(contentsOf: file))
        } catch {
            throw HandoffStoreError.unreadable
        }
        guard handoff.id == id else { throw HandoffStoreError.unreadable }
        return handoff
    }

    /// Writes the record file; throws `.unwritable` when it cannot be written.
    public func save(_ handoff: DayHandoff) throws {
        try writing {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            try write(
                try encoder.encode(handoff), named: Self.recordName(handoff.id), on: handoff.date)
        }
    }

    /// The saved PDF, or nil when there is none; throws `.unreadable` when it cannot be read.
    public func pdf(for id: HandoffID) throws -> Data? {
        let file = folder(id.date).appending(path: Self.pdfName(id))
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try Data(contentsOf: file)
        } catch {
            throw HandoffStoreError.unreadable
        }
    }

    /// Writes the PDF; throws `.unwritable` when it cannot be written.
    public func savePDF(_ data: Data, for id: HandoffID) throws {
        try writing { try write(data, named: Self.pdfName(id), on: id.date) }
    }

    /// Removes the PDF and keeps the record file; throws `.unwritable` when it cannot be removed.
    public func deletePDF(for id: HandoffID) throws {
        try writing {
            let file = folder(id.date).appending(path: Self.pdfName(id))
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Removes the date's folder, with every record file and PDF; throws `.unwritable` when it
    /// cannot be removed.
    public func deleteHandoff(for date: CalendarDay) throws {
        try writing {
            let dayFolder = folder(date)
            if FileManager.default.fileExists(atPath: dayFolder.path) {
                try FileManager.default.removeItem(at: dayFolder)
            }
        }
    }

    private static func recordName(_ id: HandoffID) -> String {
        id.part.map { "part-\($0).json" } ?? "handoff.json"
    }

    private static func pdfName(_ id: HandoffID) -> String {
        id.part.map { "part-\($0).pdf" } ?? "day.pdf"
    }

    /// The ID a record file of `date` is named for, or nil when `name` is not one.
    private static func id(ofRecordNamed name: String, on date: CalendarDay) -> HandoffID? {
        let day = HandoffID(date: date, part: nil)
        if name == recordName(day) { return day }
        guard let number = Int(name.dropFirst("part-".count).dropLast(".json".count)),
            (1...9999).contains(number)
        else { return nil }
        let id = HandoffID(date: date, part: number)
        return name == recordName(id) ? id : nil
    }

    private func folder(_ date: CalendarDay) -> URL {
        directory.appending(path: date.isoString)
    }

    private func write(_ data: Data, named name: String, on date: CalendarDay) throws {
        let dayFolder = folder(date)
        try FileManager.default.createDirectory(at: dayFolder, withIntermediateDirectories: true)
        try data.write(to: dayFolder.appending(path: name), options: writeOptions)
    }

    /// Runs a write; whatever fails there is `.unwritable`.
    private func writing(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch {
            throw HandoffStoreError.unwritable
        }
    }
}
