// AppCore's `BinderSession`: saving handwriting as it changes, adding pages, undoing and redoing
// handwriting, deleting added pages, and reporting what could not be saved.

import Foundation
import Testing

@testable import AppCore

@MainActor
@Suite("Binder session")
struct BinderSessionTests {
    private let layout: BinderLayout
    private let day: BinderDay
    private let date: CalendarDay
    private let meeting = PageKey.meeting("a")

    init() throws {
        layout = BinderLayout(
            manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer())
        date = try #require(CalendarDay(year: 2026, month: 9, day: 30))
        day = BinderDay(
            content: AgendaContent(
                date: date, todoItems: [],
                schedule: [ScheduleEntry(slot: 2, text: "A", meetingIndex: 0)],
                meetings: ["A"], meetingIDs: ["a"], delegated: []),
            theme: Theme())
    }

    private func makeSession(
        _ store: any BinderStore, ink: [PageKey: Data] = [:]
    ) -> BinderSession {
        BinderSession(
            day: day, plan: layout.plan(for: day), ink: ink, store: store, layout: layout,
            makeID: CountingIDs().next)
    }

    @Test("handwriting is kept and saved")
    func setInkSaves() throws {
        let store = InMemoryBinderStore()
        let session = makeSession(store)
        session.setInk(Data([1, 2]), on: meeting)
        let saved = try store.ink(on: date)
        #expect(session.ink == [meeting: Data([1, 2])])
        #expect(saved == [meeting: Data([1, 2])])
        #expect(session.message == nil)
        #expect(session.date == date)
    }

    @Test("handwriting on a locked page changes nothing and saves nothing")
    func setInkIgnoresLocked() throws {
        let store = InMemoryBinderStore()
        let session = makeSession(store)
        session.lock([meeting])
        session.setInk(Data([1]), on: meeting)
        #expect(session.ink.isEmpty)
        #expect(try store.ink(on: date).isEmpty)
        #expect(!session.canUndo)
    }

    @Test("locking drops the undo and redo entries of the locked pages only")
    func lockDropsHistory() {
        let session = makeSession(InMemoryBinderStore())
        session.setInk(Data([1]), on: meeting)
        session.setInk(Data([2]), on: .notes)
        session.setInk(Data([3]), on: meeting)
        session.setInk(Data([4]), on: .notes)
        #expect(session.undo() == .notes)
        session.lock([meeting])
        #expect(session.isLocked(meeting))
        #expect(!session.isLocked(.notes))
        #expect(session.redo() == .notes)
        #expect(session.undo() == .notes)
        #expect(session.undo() == .notes)
        #expect(session.undo() == nil)
        #expect(session.ink[meeting] == Data([3]))
    }

    @Test("a locked added page cannot be deleted, and no page can follow a locked page")
    func lockedPageRules() throws {
        let session = makeSession(InMemoryBinderStore())
        let added = session.addPage(after: meeting)
        #expect(session.canDelete(added))
        #expect(session.canAddPage(after: added))
        session.lock([added])
        #expect(!session.canDelete(added))
        #expect(!session.canAddPage(after: added))
        #expect(session.canAddPage(after: meeting))
        #expect(session.deletePage(added) == nil)
    }

    @Test("locking twice keeps one entry; unlock and unlockAll make pages writable and save")
    func unlockSaves() throws {
        let store = InMemoryBinderStore()
        let session = makeSession(store)
        session.lock([meeting, .notes])
        session.lock([meeting])
        #expect(session.day.locked == [meeting, .notes])
        #expect(try store.day(date)?.locked == [meeting, .notes])
        session.unlock([meeting])
        #expect(try store.day(date)?.locked == [.notes])
        session.unlockAll()
        #expect(session.day.locked.isEmpty)
        #expect(try store.day(date)?.locked == [])
        #expect(session.message == nil)
    }

    @Test("a failed save while locking or unlocking leaves a message")
    func lockSaveFailures() {
        let store = FailingBinderStore(.unwritable, failing: [.saveDay])
        let expected = "Couldn't save the binder. Free some space on this device."
        let locking = makeSession(store)
        locking.lock([meeting])
        #expect(locking.message == expected)
        let unlocking = makeSession(store)
        unlocking.unlock([meeting])
        #expect(unlocking.message == expected)
        let all = makeSession(store)
        all.unlockAll()
        #expect(all.message == expected)
    }

    @Test("unchanged handwriting is not saved again")
    func setInkIgnoresUnchanged() throws {
        let store = InMemoryBinderStore()
        let session = makeSession(store)
        session.setInk(Data([1]), on: meeting)
        try store.saveInk(Data(), for: meeting, on: date)
        session.setInk(Data([1]), on: meeting)
        session.setInk(Data(), on: .notes)
        let saved = try store.ink(on: date)
        #expect(saved.isEmpty)
    }

    @Test("empty data removes the handwriting")
    func setInkRemoves() throws {
        let store = InMemoryBinderStore()
        let session = makeSession(store)
        session.setInk(Data([1]), on: meeting)
        #expect(session.inkedKeys == [meeting])
        session.setInk(Data(), on: meeting)
        let saved = try store.ink(on: date)
        #expect(session.ink.isEmpty)
        #expect(session.inkedKeys.isEmpty)
        #expect(saved.isEmpty)
    }

    @Test("a failed save says why, and the next good save clears it")
    func setInkMessages() {
        let store = FailingBinderStore(.unwritable, failing: [.saveInk])
        let session = makeSession(store)
        session.setInk(Data([1]), on: meeting)
        #expect(
            session.message == "Couldn't save your handwriting. Free some space on this device.")
        #expect(session.ink[meeting] == Data([1]))
        store.setFailing([])
        session.setInk(Data([2]), on: meeting)
        #expect(session.message == nil)
        let unreadable = FailingBinderStore(.unreadable, failing: [.saveInk])
        let other = makeSession(unreadable)
        other.setInk(Data([1]), on: meeting)
        #expect(
            other.message
                == "Couldn't save your handwriting: this day's saved binder can't be read.")
    }

    @Test("an added page follows its page and is saved with the day")
    func addPage() throws {
        let store = InMemoryBinderStore()
        let session = makeSession(store)
        let key = session.addPage(after: meeting)
        #expect(key == .extra("id-1"))
        let at = try #require(session.index(of: meeting))
        #expect(session.index(of: key) == at + 1)
        let saved = try store.day(date)
        #expect(saved == session.day)
        #expect(session.day.extras == [ExtraPage(id: "id-1", after: meeting, source: meeting)])
        #expect(session.message == nil)
    }

    @Test("a failed save of an added page leaves a message")
    func addPageFails() {
        let session = makeSession(FailingBinderStore(.unwritable, failing: [.saveDay]))
        let key = session.addPage(after: .overview)
        #expect(session.index(of: key) == 1)
        #expect(session.message == "Couldn't save the new page. Free some space on this device.")
    }

    @Test("a deleted page goes with its handwriting, and the page before it is shown")
    func deletePage() throws {
        let store = InMemoryBinderStore()
        let session = makeSession(store)
        let key = session.addPage(after: meeting)
        session.setInk(Data([1]), on: key)
        #expect(session.deletePage(key) == meeting)
        #expect(session.index(of: key) == nil)
        #expect(session.ink[key] == nil)
        #expect(try store.day(date)?.extras == [])
        #expect(try store.ink(on: date)[key] == nil)
        #expect(session.message == nil)
    }

    @Test("only added pages can be deleted")
    func onlyAddedPagesCanBeDeleted() {
        let session = makeSession(InMemoryBinderStore())
        let before = session.plan
        #expect(!session.canDelete(.overview))
        #expect(!session.canDelete(meeting))
        #expect(!session.canDelete(.extra("zz")))
        #expect(session.deletePage(.overview) == nil)
        #expect(session.plan == before)
    }

    @Test("a failed save of a deletion leaves a message")
    func deletePageFails() {
        let session = makeSession(FailingBinderStore(.unwritable, failing: [.saveDay]))
        let key = session.addPage(after: meeting)
        #expect(session.deletePage(key) == meeting)
        #expect(session.message == "Couldn't delete the page. Free some space on this device.")
    }

    @Test("index finds a shown page and nothing else")
    func indexOf() {
        let session = makeSession(InMemoryBinderStore())
        #expect(session.index(of: .overview) == 0)
        #expect(session.index(of: .notes) == session.plan.pages.count - 1)
        #expect(session.index(of: .extra("zz")) == nil)
    }

    @Test("only pages with handwriting count as inked")
    func inkedKeys() {
        let session = makeSession(
            InMemoryBinderStore(), ink: [.overview: Data([1]), .notes: Data(), meeting: Data([3])])
        #expect(session.inkedKeys == [.overview, meeting])
    }
}

@MainActor
@Suite("Binder session history")
struct BinderSessionHistoryTests {
    private let layout: BinderLayout
    private let day: BinderDay
    private let date: CalendarDay
    private let meeting = PageKey.meeting("a")

    init() throws {
        layout = BinderLayout(
            manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer())
        date = try #require(CalendarDay(year: 2026, month: 9, day: 30))
        day = BinderDay(
            content: AgendaContent(
                date: date, todoItems: [],
                schedule: [ScheduleEntry(slot: 2, text: "A", meetingIndex: 0)],
                meetings: ["A"], meetingIDs: ["a"], delegated: []),
            theme: Theme())
    }

    private func makeSession(
        _ store: any BinderStore, ink: [PageKey: Data] = [:]
    ) -> BinderSession {
        BinderSession(
            day: day, plan: layout.plan(for: day), ink: ink, store: store, layout: layout,
            makeID: CountingIDs().next)
    }

    @Test("undo reverts the last change on any page and saves it")
    func undoAnyPage() throws {
        let store = InMemoryBinderStore()
        let session = makeSession(store)
        session.setInk(Data([1]), on: meeting)
        session.setInk(Data([2]), on: .notes)
        #expect(session.undo() == .notes)
        #expect(session.ink == [meeting: Data([1])])
        #expect(try store.ink(on: date)[.notes] == nil)
        #expect(session.undo() == meeting)
        #expect(session.ink.isEmpty)
        #expect(try store.ink(on: date).isEmpty)
        #expect(session.undo() == nil)
        #expect(!session.canUndo)
    }

    @Test("undo restores the handwriting a change replaced")
    func undoRestoresReplaced() throws {
        let store = InMemoryBinderStore()
        let session = makeSession(store)
        session.setInk(Data([1]), on: meeting)
        session.setInk(Data([2]), on: meeting)
        _ = session.undo()
        #expect(session.ink[meeting] == Data([1]))
        #expect(try store.ink(on: date)[meeting] == Data([1]))
    }

    @Test("redo reapplies what undo reverted, and a new change clears it")
    func redoAndNewChange() throws {
        let store = InMemoryBinderStore()
        let session = makeSession(store)
        session.setInk(Data([1]), on: meeting)
        _ = session.undo()
        #expect(session.canRedo)
        #expect(session.redo() == meeting)
        #expect(session.ink[meeting] == Data([1]))
        #expect(try store.ink(on: date)[meeting] == Data([1]))
        #expect(session.undo() == meeting)
        session.setInk(Data([3]), on: .notes)
        #expect(!session.canRedo)
        #expect(session.redo() == nil)
    }

    @Test("the history keeps the last historyLimit changes")
    func historyLimit() {
        let session = makeSession(InMemoryBinderStore())
        for i in 1...BinderSession.historyLimit + 1 {
            session.setInk(Data([UInt8(i)]), on: meeting)
        }
        var undone = 0
        while session.undo() != nil {
            undone += 1
        }
        #expect(undone == BinderSession.historyLimit)
        #expect(session.ink[meeting] == Data([1]))
    }

    @Test("an undo whose save fails keeps the reverted handwriting and says why")
    func undoSaveFails() {
        let session = makeSession(FailingBinderStore(.unwritable, failing: [.saveInk]))
        session.setInk(Data([1]), on: meeting)
        _ = session.undo()
        #expect(session.ink.isEmpty)
        #expect(
            session.message == "Couldn't save your handwriting. Free some space on this device.")
    }

    @Test("adding a page leaves the history alone")
    func addPageKeepsHistory() {
        let session = makeSession(InMemoryBinderStore())
        session.setInk(Data([1]), on: meeting)
        _ = session.addPage(after: .overview)
        #expect(session.undo() == meeting)
    }

    @Test("deleting a page forgets its undo history")
    func deletePageForgetsHistory() throws {
        let store = InMemoryBinderStore()
        let session = makeSession(store)
        let key = session.addPage(after: meeting)
        session.setInk(Data([1]), on: meeting)
        session.setInk(Data([2]), on: key)
        #expect(session.undo() == key)
        _ = session.deletePage(key)
        #expect(!session.canRedo)
        #expect(session.canUndo)
        #expect(session.undo() == meeting)
        #expect(session.undo() == nil)
        #expect(session.ink[key] == nil)
        #expect(try store.ink(on: date)[key] == nil)
    }
}
