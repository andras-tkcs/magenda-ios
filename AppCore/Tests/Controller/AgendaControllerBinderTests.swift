// AppCore's agenda controller and the binder: opening a stored day, saving one at Render, keeping
// handwriting across renders, and exporting.

import Foundation
import Testing

@testable import AppCore

private func storedDay(_ iso: String) -> BinderDay {
    BinderDay(
        content: AgendaContent(
            date: date(iso), todoItems: [],
            schedule: [ScheduleEntry(slot: 2, text: "A", meetingIndex: 0)],
            meetings: ["A"], meetingIDs: ["a"], delegated: []),
        theme: Theme())
}

@MainActor
private func baseKeys(_ controller: AgendaController) throws -> [PageKey] {
    let content = try #require(controller.draft?.content())
    return AgendaLayout(
        manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer(),
        theme: controller.settings.theme
    ).plan(for: content).pages.map(\.key)
}

@MainActor
@Suite("Agenda controller binder")
struct AgendaControllerBinderTests {
    @Test("render creates and saves a binder for the day")
    func renderCreatesBinder() async throws {
        let context = try await started(.standard)
        #expect(context.controller.binder == nil)
        await context.controller.render()
        let binder = try #require(context.controller.binder)
        let saved = try context.binderStore.day(wednesday)
        let keys = try baseKeys(context.controller)
        #expect(binder.date == wednesday)
        #expect(saved == binder.day)
        #expect(binder.plan.pages.map(\.key) == keys)
        #expect(context.controller.message == nil)
    }

    @Test("a page switched off after handwriting is kept with its handwriting")
    func retainedAfterSwitchOff() async throws {
        let context = try await started(.standard)
        await context.controller.render()
        let binder = try #require(context.controller.binder)
        let key = try #require(
            binder.plan.pages.map(\.key).first {
                if case .meeting = $0 { return true }
                return false
            })
        guard case .meeting(let eventID) = key else {
            Issue.record("Expected a meeting page.")
            return
        }
        binder.setInk(Data([7]), on: key)
        context.controller.updateDraft { $0.setMeetingPage(false, forEvent: eventID) }
        await context.controller.render()
        #expect(binder.plan.pages.map(\.key).contains(key))
        #expect(binder.day.retained.map(\.key) == [key])
        #expect(binder.ink[key] == Data([7]))
        let saved = try context.binderStore.day(wednesday)
        #expect(saved == binder.day)
    }

    @Test("load opens the stored binder before fetching, so it is there when the fetch fails")
    func loadOpensStoredBinder() async throws {
        let store = InMemoryBinderStore()
        try store.saveDay(storedDay("2026-09-30"))
        try store.saveInk(Data([5]), for: .overview, on: wednesday)
        let context = try make(data: FailingDataSource(error: Failure()), binderStore: store)
        await context.controller.start()
        #expect(context.controller.status == .failed(GoogleAPIError.unexpectedResponse.userMessage))
        let binder = try #require(context.controller.binder)
        #expect(binder.day == storedDay("2026-09-30"))
        #expect(binder.ink == [.overview: Data([5])])
    }

    @Test("a day with nothing stored has no binder, and another day swaps it")
    func loadSwapsBinder() async throws {
        let store = InMemoryBinderStore()
        try store.saveDay(storedDay("2026-09-30"))
        try store.saveDay(storedDay("2026-10-01"))
        let empty = try await started(.standard)
        #expect(empty.controller.binder == nil)
        let context = try make(binderStore: store)
        await context.controller.start()
        #expect(context.controller.binder?.date == wednesday)
        await context.controller.setDay(date("2026-10-01"))
        #expect(context.controller.binder?.date == date("2026-10-01"))
        await context.controller.setDay(date("2026-10-02"))
        #expect(context.controller.binder == nil)
    }

    @Test("loading the day that is open keeps the session")
    func loadKeepsSession() async throws {
        let store = InMemoryBinderStore()
        try store.saveDay(storedDay("2026-09-30"))
        let context = try make(binderStore: store)
        await context.controller.start()
        let binder = try #require(context.controller.binder)
        await context.controller.load()
        #expect(context.controller.binder === binder)
    }

    @Test("an unreadable store leaves no binder and a message")
    func unreadableStore() async throws {
        let store = FailingBinderStore(.unreadable, failing: [.day])
        let context = try make(binderStore: store)
        await context.controller.start()
        #expect(context.controller.binder == nil)
        #expect(context.controller.message == "Couldn't read the saved binder for this day.")
    }

    @Test("a binder that cannot be saved leaves the PDF rendered and a message")
    func saveDayFails() async throws {
        let store = FailingBinderStore(.unwritable, failing: [.saveDay])
        let context = try make(binderStore: store)
        await context.controller.start()
        await context.controller.render()
        #expect(context.controller.rendered != nil)
        #expect(context.controller.binder == nil)
        #expect(
            context.controller.message
                == "Couldn't save the binder. Free some space on this device and try again.")
    }

    @Test("a binder that cannot be saved keeps the previous session")
    func saveDayFailsKeepsSession() async throws {
        let store = FailingBinderStore(.unwritable, failing: [.saveDay])
        try store.base.saveDay(storedDay("2026-09-30"))
        let context = try make(binderStore: store)
        await context.controller.start()
        let binder = try #require(context.controller.binder)
        await context.controller.render()
        #expect(context.controller.binder === binder)
        #expect(binder.day == storedDay("2026-09-30"))
        #expect(context.controller.message != nil)
    }

    @Test("export passes the plan and handwriting in page order")
    func export() async throws {
        let context = try await started(.standard)
        await context.controller.render()
        let binder = try #require(context.controller.binder)
        binder.setInk(Data([1]), on: .overview)
        binder.setInk(Data([2]), on: .notes)
        await context.controller.exportBinder()
        let expected: [Data?] = binder.plan.pages.map { page -> Data? in
            if page.key == .overview {
                return Data([1])
            }
            return page.key == .notes ? Data([2]) : nil
        }
        #expect(context.renderer.plans.last == binder.plan)
        #expect(context.renderer.inks.last == expected)
        #expect(context.renderer.fileNames.last == "2026-09-30.pdf")
        #expect(context.controller.binderExport == context.renderer.url)
        context.controller.clearBinderExport()
        #expect(context.controller.binderExport == nil)
    }

    @Test("export without a binder does nothing")
    func exportWithoutBinder() async throws {
        let context = try make()
        await context.controller.exportBinder()
        #expect(context.renderer.plans.isEmpty)
        #expect(context.controller.binderExport == nil)
    }

    @Test("a failing renderer leaves a message and no export")
    func exportFails() async throws {
        let store = InMemoryBinderStore()
        try store.saveDay(storedDay("2026-09-30"))
        let context = try make(renderer: FakeRenderer(fails: true), binderStore: store)
        await context.controller.start()
        await context.controller.exportBinder()
        #expect(context.controller.binderExport == nil)
        #expect(context.controller.message == "Couldn't create the PDF. Try again.")
    }

    @Test("signing out clears the binder and its export")
    func signOutClears() async throws {
        let context = try await started(.standard)
        await context.controller.render()
        await context.controller.exportBinder()
        #expect(context.controller.binder != nil)
        #expect(context.controller.binderExport != nil)
        await context.controller.signOut()
        #expect(context.controller.binder == nil)
        #expect(context.controller.binderExport == nil)
    }

    @Test("a render overtaken by a load saves no binder")
    func overtakenRenderSavesNothing() async throws {
        let gated = GatedRenderer()
        let context = try make(rendering: gated)
        await context.controller.start()
        let rendering = Task { await context.controller.render() }
        await gated.waitUntilBlocked()
        await context.controller.goToNextWorkingDay()
        await gated.release()
        await rendering.value
        let saved = try context.binderStore.day(wednesday)
        #expect(saved == nil)
        #expect(context.controller.binder == nil)
    }

    @Test("rendering again updates the open session and keeps its handwriting")
    func renderUpdatesSession() async throws {
        let context = try await started(.standard)
        await context.controller.render()
        let binder = try #require(context.controller.binder)
        binder.setInk(Data([1]), on: .overview)
        await context.controller.render()
        #expect(context.controller.binder === binder)
        #expect(binder.ink == [.overview: Data([1])])
    }

    @Test("a page added while a render runs is in the saved day")
    func addPageDuringRender() async throws {
        let store = InMemoryBinderStore()
        try store.saveDay(storedDay("2026-09-30"))
        let gated = GatedRenderer()
        let context = try make(rendering: gated, binderStore: store)
        await context.controller.start()
        let binder = try #require(context.controller.binder)
        let rendering = Task { await context.controller.render() }
        await gated.waitUntilBlocked()
        let key = binder.addPage(after: .overview)
        await gated.release()
        await rendering.value
        let stored = try store.day(wednesday)
        let saved = try #require(stored)
        #expect(key == .extra("id-1"))
        #expect(saved.extras.map(\.id) == ["id-1"])
        #expect(saved == binder.day)
        #expect(binder.index(of: key) == 1)
    }

    @Test("without an injected ID source, added pages still get distinct IDs")
    func defaultIDs() async throws {
        let store = InMemoryBinderStore()
        try store.saveDay(storedDay("2026-09-30"))
        let controller = AgendaController(
            account: FixtureGoogleAccount(signedIn: true),
            data: FixtureGoogleDataSource(.standard),
            settingsStore: InMemorySettingsStore(AgendaSettings()),
            credentials: InMemoryClientCredentialsStore(validCredentials),
            measurer: FakeTextMeasurer(), renderer: FakeRenderer(), binderStore: store,
            manifest: try TemplateManifest.bundled(), timeZone: .gmt, today: tuesday)
        await controller.start()
        let binder = try #require(controller.binder)
        let first = binder.addPage(after: .overview)
        let second = binder.addPage(after: .overview)
        #expect(first != second)
    }
}
