import Foundation
import Observation

/// The open binder of one day: its pages, its handwriting, and saving both as they change.
@MainActor @Observable
public final class BinderSession {
    /// The day the binder is for.
    public var date: CalendarDay { day.date }
    /// What the pages are drawn from.
    public private(set) var day: BinderDay
    /// The laid-out pages of `day`.
    public private(set) var plan: RenderPlan
    /// The handwriting of each page, as PencilKit data.
    public private(set) var ink: [PageKey: Data]
    /// The last saving problem, or nil when the last save worked.
    public private(set) var message: String?

    /// The pages that carry handwriting.
    public var inkedKeys: Set<PageKey> { Set(ink.filter { !$0.value.isEmpty }.keys) }

    /// One handwriting change: what page `key` held before and after it.
    private struct InkChange {
        let key: PageKey
        let before: Data
        let after: Data
    }

    /// How many handwriting changes undo can go back through; older ones are forgotten.
    static let historyLimit = 100

    private var undoStack: [InkChange] = []
    private var redoStack: [InkChange] = []

    /// Whether there is a handwriting change to undo.
    public var canUndo: Bool { !undoStack.isEmpty }
    /// Whether there is an undone handwriting change to redo.
    public var canRedo: Bool { !redoStack.isEmpty }

    @ObservationIgnored private let store: any BinderStore
    @ObservationIgnored private let layout: BinderLayout
    @ObservationIgnored private let makeID: @Sendable () -> String

    init(
        day: BinderDay, plan: RenderPlan, ink: [PageKey: Data], store: any BinderStore,
        layout: BinderLayout, makeID: @escaping @Sendable () -> String
    ) {
        self.day = day
        self.plan = plan
        self.ink = ink
        self.store = store
        self.layout = layout
        self.makeID = makeID
    }

    /// The position of the page called `key` in `plan`, or nil when it is not shown.
    public func index(of key: PageKey) -> Int? {
        plan.pages.firstIndex { $0.key == key }
    }

    /// Keeps `data` as the handwriting of `key` and saves it; empty `data` removes it.
    public func setInk(_ data: Data, on key: PageKey) {
        guard !isLocked(key), (ink[key] ?? Data()) != data else {
            return
        }
        undoStack.append(InkChange(key: key, before: ink[key] ?? Data(), after: data))
        if undoStack.count > Self.historyLimit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        write(data, on: key)
    }

    /// Reverts the last handwriting change, on whichever page it was, saves the page, and returns
    /// its key; nil when there is nothing to undo.
    public func undo() -> PageKey? {
        guard let change = undoStack.popLast() else {
            return nil
        }
        redoStack.append(change)
        write(change.before, on: change.key)
        return change.key
    }

    /// Applies the last undone handwriting change again, saves the page, and returns its key; nil
    /// when there is nothing to redo.
    public func redo() -> PageKey? {
        guard let change = redoStack.popLast() else {
            return nil
        }
        undoStack.append(change)
        write(change.after, on: change.key)
        return change.key
    }

    private func write(_ data: Data, on key: PageKey) {
        ink[key] = data.isEmpty ? nil : data
        do {
            try store.saveInk(data, for: key, on: date)
            message = nil
        } catch {
            message =
                (error as? BinderStoreError) == .unreadable
                ? "Couldn't save your handwriting: this day's saved binder can't be read."
                : "Couldn't save your handwriting. Free some space on this device."
        }
    }

    /// Puts a blank copy of the page `key` right after it, saves the day, and returns the new
    /// page's key.
    public func addPage(after key: PageKey) -> PageKey {
        let id = makeID()
        day.addPage(after: key, id: id)
        plan = layout.plan(for: day)
        do {
            try store.saveDay(day)
        } catch {
            message = "Couldn't save the new page. Free some space on this device."
        }
        return .extra(id)
    }

    /// Whether `key` is a page the person added, which they can delete.
    public func canDelete(_ key: PageKey) -> Bool {
        guard !isLocked(key), case .extra(let id) = key else {
            return false
        }
        return day.extras.contains { $0.id == id }
    }

    /// Deletes the added page `key` and its handwriting, saves the day, and returns the key of the
    /// page to show instead: the one before it. Returns nil and changes nothing when `key` is not
    /// an added page of this day.
    public func deletePage(_ key: PageKey) -> PageKey? {
        guard canDelete(key), case .extra(let id) = key, let index = self.index(of: key) else {
            return nil
        }
        day.removePage(id: id)
        plan = layout.plan(for: day)
        ink[key] = nil
        undoStack.removeAll { $0.key == key }
        redoStack.removeAll { $0.key == key }
        do {
            try store.saveDay(day)
            try store.saveInk(Data(), for: key, on: date)
            message = nil
        } catch {
            message = "Couldn't delete the page. Free some space on this device."
        }
        return plan.pages[max(0, min(index - 1, plan.pages.count - 1))].key
    }

    /// Whether `key` was sent to Claude and can no longer be written on.
    public func isLocked(_ key: PageKey) -> Bool {
        day.locked.contains(key)
    }

    /// Makes `keys` read-only, drops their undo and redo history, and saves the day.
    public func lock(_ keys: [PageKey]) {
        for key in keys where !day.locked.contains(key) {
            day.locked.append(key)
        }
        undoStack.removeAll { keys.contains($0.key) }
        redoStack.removeAll { keys.contains($0.key) }
        saveLocks()
    }

    /// Makes `keys` writable again and saves the day.
    public func unlock(_ keys: [PageKey]) {
        day.locked.removeAll { keys.contains($0) }
        saveLocks()
    }

    /// Makes every page writable again and saves the day.
    public func unlockAll() {
        day.locked = []
        saveLocks()
    }

    /// Whether a page can be added after `key`: not after a locked page.
    public func canAddPage(after key: PageKey) -> Bool {
        !isLocked(key)
    }

    private func saveLocks() {
        do {
            try store.saveDay(day)
        } catch {
            message = "Couldn't save the binder. Free some space on this device."
        }
    }

    // Used by a render, which updates the open binder instead of replacing it, so screens keep
    // saving into the same session and its handwriting.
    func replace(day: BinderDay, plan: RenderPlan) {
        self.day = day
        self.plan = plan
    }
}
