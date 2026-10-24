// A `BinderStore` for tests that keeps everything in memory but throws a chosen error from chosen
// methods, plus a counter that makes predictable page IDs.

import AppCore
import Foundation

// `@unchecked Sendable` is safe because `failing` and `saveInkSuccesses` are only read or written while `lock` is held, and
// `base` is itself thread-safe.
final class FailingBinderStore: BinderStore, @unchecked Sendable {
    enum Method: Sendable {
        case day, saveDay, ink, saveInk, deleteDay
    }

    /// Where everything that does not fail is kept; tests seed and inspect it directly.
    let base = InMemoryBinderStore()
    let error: BinderStoreError

    private let lock = NSLock()
    private var failing: Set<Method>
    private var saveInkSuccesses: Int?

    init(_ error: BinderStoreError, failing: Set<Method>) {
        self.error = error
        self.failing = failing
    }

    /// Chooses which methods throw from now on.
    func setFailing(_ methods: Set<Method>) {
        lock.withLock { failing = methods }
    }

    /// Lets `saveInk` succeed `count` more times, then makes it throw from then on.
    func failSaveInk(after count: Int) {
        lock.withLock { saveInkSuccesses = count }
    }

    func day(_ date: CalendarDay) throws -> BinderDay? {
        try check(.day)
        return try base.day(date)
    }

    func saveDay(_ day: BinderDay) throws {
        try check(.saveDay)
        try base.saveDay(day)
    }

    func ink(on date: CalendarDay) throws -> [PageKey: Data] {
        try check(.ink)
        return try base.ink(on: date)
    }

    func saveInk(_ data: Data, for key: PageKey, on date: CalendarDay) throws {
        try check(.saveInk)
        let exhausted = lock.withLock { () -> Bool in
            guard let remaining = saveInkSuccesses else {
                return false
            }
            saveInkSuccesses = remaining - 1
            return remaining <= 0
        }
        if exhausted {
            throw error
        }
        try base.saveInk(data, for: key, on: date)
    }

    func deleteDay(_ date: CalendarDay) throws {
        try check(.deleteDay)
        try base.deleteDay(date)
    }

    private func check(_ method: Method) throws {
        if lock.withLock({ failing.contains(method) }) {
            throw error
        }
    }
}

// `@unchecked Sendable` is safe because `count` is only touched while `lock` is held.
final class CountingIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    /// "id-1", then "id-2", and so on.
    func next() -> String {
        lock.withLock {
            count += 1
            return "id-\(count)"
        }
    }
}
