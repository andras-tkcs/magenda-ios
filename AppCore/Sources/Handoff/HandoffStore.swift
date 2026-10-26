import Foundation

/// Why a hand-off could not be read or saved.
public enum HandoffStoreError: Error, Equatable {
    /// What is saved exists but cannot be read.
    case unreadable
    /// Something could not be written.
    case unwritable
}

/// Where finished days and their PDFs are kept on the device.
public protocol HandoffStore: Sendable {
    /// Every readable hand-off, newest date first.
    func handoffs() throws -> [DayHandoff]
    /// The hand-off of `date`, or nil when there is none.
    func handoff(_ date: CalendarDay) throws -> DayHandoff?
    /// Saves `handoff`, replacing what was saved for its date.
    func save(_ handoff: DayHandoff) throws
    /// The PDF saved for `date`, or nil when there is none.
    func pdf(for date: CalendarDay) throws -> Data?
    /// Saves the PDF of `date`.
    func savePDF(_ data: Data, for date: CalendarDay) throws
    /// Removes the PDF of `date`; having none is not an error.
    func deletePDF(for date: CalendarDay) throws
    /// Removes the hand-off and the PDF of `date`; having none is not an error.
    func deleteHandoff(for date: CalendarDay) throws
}

/// A store that keeps hand-offs in memory, for tests and previews.
public final class InMemoryHandoffStore: HandoffStore, @unchecked Sendable {
    // `held` and `pdfs` are only read or written while `lock` is held, which is what makes this
    // safe.
    private let lock = NSLock()
    private var held: [CalendarDay: DayHandoff] = [:]
    private var pdfs: [CalendarDay: Data] = [:]

    /// Creates an empty store.
    public init() {}

    /// The held hand-offs, newest first.
    public func handoffs() throws -> [DayHandoff] {
        lock.withLock { held.values.sorted { $0.date > $1.date } }
    }

    /// The held hand-off of `date`.
    public func handoff(_ date: CalendarDay) throws -> DayHandoff? {
        lock.withLock { held[date] }
    }

    /// Replaces the held hand-off.
    public func save(_ handoff: DayHandoff) throws {
        lock.withLock { held[handoff.date] = handoff }
    }

    /// The held PDF of `date`.
    public func pdf(for date: CalendarDay) throws -> Data? {
        lock.withLock { pdfs[date] }
    }

    /// Replaces the held PDF.
    public func savePDF(_ data: Data, for date: CalendarDay) throws {
        lock.withLock { pdfs[date] = data }
    }

    /// Drops the held PDF.
    public func deletePDF(for date: CalendarDay) throws {
        lock.withLock { pdfs[date] = nil }
    }

    /// Drops the held hand-off and PDF.
    public func deleteHandoff(for date: CalendarDay) throws {
        lock.withLock {
            held[date] = nil
            pdfs[date] = nil
        }
    }
}

/// A store that keeps hand-offs as files under one directory.
///
/// Each day has a folder named after its date, holding `handoff.json` and `day.pdf`. Every name
/// is made by the app, never taken from Google data.
public struct FileHandoffStore: HandoffStore {
    private let directory: URL
    private let writeOptions: Data.WritingOptions

    /// Creates a store under `directory`; folders are created when something is saved. Every write
    /// is atomic and also uses `protection`, so the app can choose a file-protection class.
    public init(directory: URL, protection: Data.WritingOptions = []) {
        self.directory = directory
        writeOptions = protection.union(.atomic)
    }

    /// Every hand-off with a readable `handoff.json`, newest date first; `[]` when the directory
    /// does not exist. Folders that are not named after a date and damaged files are skipped.
    /// Throws `.unreadable` when the directory cannot be listed.
    public func handoffs() throws -> [DayHandoff] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw HandoffStoreError.unreadable
        }
        let found = names.compactMap { name in
            CalendarDay(isoString: name).flatMap { $0.isoString == name ? $0 : nil }
        }
        return found.compactMap { try? handoff($0) }.sorted { $0.date > $1.date }
    }

    /// The saved hand-off, or nil when no `handoff.json` exists; throws `.unreadable` when it
    /// cannot be decoded.
    public func handoff(_ date: CalendarDay) throws -> DayHandoff? {
        let file = folder(date).appending(path: "handoff.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try JSONDecoder().decode(DayHandoff.self, from: Data(contentsOf: file))
        } catch {
            throw HandoffStoreError.unreadable
        }
    }

    /// Writes `handoff.json`; throws `.unwritable` when it cannot be written.
    public func save(_ handoff: DayHandoff) throws {
        try writing {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            try write(try encoder.encode(handoff), named: "handoff.json", on: handoff.date)
        }
    }

    /// The saved PDF, or nil when there is none; throws `.unreadable` when it cannot be read.
    public func pdf(for date: CalendarDay) throws -> Data? {
        let file = folder(date).appending(path: "day.pdf")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try Data(contentsOf: file)
        } catch {
            throw HandoffStoreError.unreadable
        }
    }

    /// Writes `day.pdf`; throws `.unwritable` when it cannot be written.
    public func savePDF(_ data: Data, for date: CalendarDay) throws {
        try writing { try write(data, named: "day.pdf", on: date) }
    }

    /// Removes `day.pdf` and keeps `handoff.json`; throws `.unwritable` when it cannot be removed.
    public func deletePDF(for date: CalendarDay) throws {
        try writing {
            let file = folder(date).appending(path: "day.pdf")
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Removes the day's folder, with `handoff.json` and `day.pdf`; throws `.unwritable` when it
    /// cannot be removed.
    public func deleteHandoff(for date: CalendarDay) throws {
        try writing {
            let dayFolder = folder(date)
            if FileManager.default.fileExists(atPath: dayFolder.path) {
                try FileManager.default.removeItem(at: dayFolder)
            }
        }
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
