import Foundation

/// Why a binder could not be read or saved.
public enum BinderStoreError: Error, Equatable {
    /// What is saved exists but cannot be read.
    case unreadable
    /// Something could not be written.
    case unwritable
}

/// Where binder days and their handwriting are kept on the device.
public protocol BinderStore: Sendable {
    /// The saved day, or nil when nothing is saved for `date`.
    func day(_ date: CalendarDay) throws -> BinderDay?
    /// Saves `day`, replacing what was saved for its date.
    func saveDay(_ day: BinderDay) throws
    /// The handwriting saved for `date`, by page.
    func ink(on date: CalendarDay) throws -> [PageKey: Data]
    /// Saves the handwriting of `key` on `date`; empty `data` deletes it.
    func saveInk(_ data: Data, for key: PageKey, on date: CalendarDay) throws
}

/// A store that keeps days and handwriting in memory, for tests and previews.
public final class InMemoryBinderStore: BinderStore, @unchecked Sendable {
    // `days` and `inks` are only read or written while `lock` is held, which is what makes this
    // safe.
    private let lock = NSLock()
    private var days: [CalendarDay: BinderDay] = [:]
    private var inks: [CalendarDay: [PageKey: Data]] = [:]

    /// Creates an empty store.
    public init() {}

    /// The held day.
    public func day(_ date: CalendarDay) throws -> BinderDay? {
        lock.withLock { days[date] }
    }

    /// Replaces the held day.
    public func saveDay(_ day: BinderDay) throws {
        lock.withLock { days[day.date] = day }
    }

    /// The held handwriting of `date`.
    public func ink(on date: CalendarDay) throws -> [PageKey: Data] {
        lock.withLock { inks[date] ?? [:] }
    }

    /// Replaces the held handwriting of `key`; empty `data` removes it.
    public func saveInk(_ data: Data, for key: PageKey, on date: CalendarDay) throws {
        lock.withLock { inks[date, default: [:]][key] = data.isEmpty ? nil : data }
    }
}

/// A store that keeps days and handwriting as files under one directory.
///
/// Each day has a folder named after its date, holding `day.json` and, under `ink`, an
/// `index.json` that maps page keys to generated `page-<n>.pkdata` files. Every name is made by
/// the app, never taken from Google data. Nothing here reads file attributes or timestamps.
public struct FileBinderStore: BinderStore {
    private let directory: URL
    private let writeOptions: Data.WritingOptions

    /// Creates a store under `directory`; folders are created when something is saved. Every write
    /// is atomic and also uses `protection`, so the app can choose a file-protection class.
    public init(directory: URL, protection: Data.WritingOptions = []) {
        self.directory = directory
        writeOptions = protection.union(.atomic)
    }

    /// The saved day, or nil when no `day.json` exists; throws `.unreadable` when it cannot be
    /// decoded.
    public func day(_ date: CalendarDay) throws -> BinderDay? {
        let file = folder(date).appending(path: "day.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try JSONDecoder().decode(BinderDay.self, from: Data(contentsOf: file))
        } catch {
            throw BinderStoreError.unreadable
        }
    }

    /// Writes `day.json`; throws `.unwritable` when it cannot be written.
    public func saveDay(_ day: BinderDay) throws {
        try writing {
            let dayFolder = folder(day.date)
            try FileManager.default.createDirectory(
                at: dayFolder, withIntermediateDirectories: true)
            try encode(day).write(
                to: dayFolder.appending(path: "day.json"), options: writeOptions)
        }
    }

    /// The handwriting of `date`; entries that name no page or no file are left out. Throws
    /// `.unreadable` when the index cannot be decoded.
    public func ink(on date: CalendarDay) throws -> [PageKey: Data] {
        let inkFolder = folder(date).appending(path: "ink")
        var result: [PageKey: Data] = [:]
        for (text, name) in try index(in: inkFolder) {
            guard Self.pageNumber(of: name) != nil, let key = PageKey(storageString: text),
                let data = try? Data(contentsOf: inkFolder.appending(path: name))
            else { continue }
            result[key] = data
        }
        return result
    }

    /// Writes the handwriting of `key` and its index entry; empty `data` removes both. Throws
    /// `.unreadable` when the index cannot be decoded, `.unwritable` when a write fails.
    public func saveInk(_ data: Data, for key: PageKey, on date: CalendarDay) throws {
        try writing {
            let inkFolder = folder(date).appending(path: "ink")
            var entries = try index(in: inkFolder)
            let id = key.storageString
            let existing = entries[id].flatMap { Self.pageNumber(of: $0) == nil ? nil : $0 }
            if data.isEmpty {
                if let existing {
                    try? FileManager.default.removeItem(at: inkFolder.appending(path: existing))
                    entries[id] = nil
                    try encode(entries).write(
                        to: inkFolder.appending(path: "index.json"), options: writeOptions)
                }
                return
            }
            let next = (entries.values.compactMap { Self.pageNumber(of: $0) }.max() ?? 0) + 1
            let name = existing ?? "page-\(next).pkdata"
            try FileManager.default.createDirectory(
                at: inkFolder, withIntermediateDirectories: true)
            try data.write(to: inkFolder.appending(path: name), options: writeOptions)
            entries[id] = name
            try encode(entries).write(
                to: inkFolder.appending(path: "index.json"), options: writeOptions)
        }
    }

    private func folder(_ date: CalendarDay) -> URL {
        directory.appending(path: date.isoString)
    }

    /// Runs a write; whatever fails there other than a `BinderStoreError` is `.unwritable`.
    private func writing(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch let error as BinderStoreError {
            throw error
        } catch {
            throw BinderStoreError.unwritable
        }
    }

    private func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    /// The index of `inkFolder`: empty when there is none, `.unreadable` when it is damaged.
    private func index(in inkFolder: URL) throws -> [String: String] {
        let file = inkFolder.appending(path: "index.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        do {
            return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
        } catch {
            throw BinderStoreError.unreadable
        }
    }

    /// `n` in a file name of the form `page-<n>.pkdata`, or nil for any other name.
    private static func pageNumber(of name: String) -> Int? {
        guard name.hasPrefix("page-"), name.hasSuffix(".pkdata") else { return nil }
        let digits = name.dropFirst(5).dropLast(7)
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(digits) else {
            return nil
        }
        return number
    }
}
