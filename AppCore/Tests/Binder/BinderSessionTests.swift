// AppCore's `BinderSession`: saving handwriting as it changes, adding pages, and reporting what
// could not be saved.

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
