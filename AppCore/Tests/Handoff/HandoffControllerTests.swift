// AppCore's `HandoffController`: finishing a day, the queue and the review loop, the purge, and
// the routine settings.

import Foundation
import Testing

@testable import AppCore

// `@unchecked Sendable` is safe because every access to the mutable state goes through `lock`.
private final class Reads: @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private var data = Data("pdf".utf8)
    private var fails = false

    func set(_ data: Data) {
        lock.withLock { self.data = data }
    }

    func failFromNowOn() {
        lock.withLock { fails = true }
    }

    func read() throws -> Data {
        let (data, fails) = lock.withLock { (self.data, self.fails) }
        if fails {
            throw Failure()
        }
        return data
    }
}

// `@unchecked Sendable` is safe because every access to `removed` goes through `lock`.
private final class Removals: @unchecked Sendable {
    private let lock = NSLock()
    private var removed: [URL] = []

    var urls: [URL] {
        lock.withLock { removed }
    }

    func remove(_ url: URL) {
        lock.withLock { removed.append(url) }
    }
}

// `@unchecked Sendable` is safe because every access to `day` goes through `lock`.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var day: CalendarDay

    init(_ day: CalendarDay) {
        self.day = day
    }

    var today: CalendarDay {
        lock.withLock { day }
    }

    func set(_ day: CalendarDay) {
        lock.withLock { self.day = day }
    }
}

// A hand-off store whose `handoffs()`, `savePDF` and `save` can be made to throw.
// `@unchecked Sendable` is safe because `failing` and `saveSuccesses` go through `lock`.
private final class FailingHandoffStore: HandoffStore, @unchecked Sendable {
    enum Method: Sendable {
        case handoffs, save, savePDF
    }

    let base = InMemoryHandoffStore()
    private let lock = NSLock()
    private var failing: Set<Method>
    private var saveSuccesses: Int?

    init(failing: Set<Method> = []) {
        self.failing = failing
    }

    /// Lets `save` succeed `count` more times, then makes it throw.
    func failSave(after count: Int) {
        lock.withLock { saveSuccesses = count }
    }

    func handoffs() throws -> [DayHandoff] {
        try check(.handoffs)
        return try base.handoffs()
    }

    func handoff(_ date: CalendarDay) throws -> DayHandoff? {
        try base.handoff(date)
    }

    func save(_ handoff: DayHandoff) throws {
        try check(.save)
        let exhausted = lock.withLock { () -> Bool in
            guard let remaining = saveSuccesses else {
                return false
            }
            saveSuccesses = remaining - 1
            return remaining <= 0
        }
        if exhausted {
            throw HandoffStoreError.unwritable
        }
        try base.save(handoff)
    }

    func pdf(for date: CalendarDay) throws -> Data? {
        try base.pdf(for: date)
    }

    func savePDF(_ data: Data, for date: CalendarDay) throws {
        try check(.savePDF)
        try base.savePDF(data, for: date)
    }

    func deletePDF(for date: CalendarDay) throws {
        try base.deletePDF(for: date)
    }

    private func check(_ method: Method) throws {
        if lock.withLock({ failing.contains(method) }) {
            throw HandoffStoreError.unwritable
        }
    }
}

private struct KeychainFailure: Error {}

private struct FailingCredentialsStore: RoutineCredentialsStore {
    func load() throws -> RoutineCredentials? { nil }
    func save(_ credentials: RoutineCredentials) throws { throw KeychainFailure() }
    func delete() throws { throw KeychainFailure() }
}

private struct OtherFailure: Error {}

@MainActor
@Suite("Hand-off controller")
struct HandoffControllerTests {
    private static let fireURL = "https://api.anthropic.com/v1/claude_code/routines/trig_abc/fire"
    private static let token = "sk-ant-oat01-secret"

    private let date: CalendarDay
    private let otherDay: CalendarDay
    private let drive: FakeDrive
    private let trigger = FakeRoutineTrigger()
    private let renderer = FakeRenderer(url: URL(fileURLWithPath: "/tmp/finished.pdf"))
    private let store: any HandoffStore
    private let binderStore: any BinderStore
    private let credentials = InMemoryRoutineCredentialsStore()
    private let clock: TestClock
    private let reads = Reads()
    private let removals = Removals()
    private let binder: BinderSession
    private let controller: HandoffController

    init(
        drive: FakeDrive = FakeDrive(), renderer: FakeRenderer? = nil,
        store: any HandoffStore = InMemoryHandoffStore(),
        binderStore: any BinderStore = InMemoryBinderStore(),
        credentials: (any RoutineCredentialsStore)? = nil
    ) throws {
        let layout = BinderLayout(
            manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer())
        date = try #require(CalendarDay(year: 2026, month: 9, day: 30))
        otherDay = try #require(CalendarDay(year: 2026, month: 9, day: 1))
        let day = BinderDay(
            content: AgendaContent(
                date: date, todoItems: [],
                schedule: [ScheduleEntry(slot: 2, text: "A", meetingIndex: 0)],
                meetings: ["A"], meetingIDs: ["cal|a"], delegated: []),
            theme: Theme())
        self.drive = drive
        self.store = store
        self.binderStore = binderStore
        clock = TestClock(try #require(CalendarDay(year: 2026, month: 10, day: 1)))
        binder = BinderSession(
            day: day, plan: layout.plan(for: day), ink: [:], store: binderStore, layout: layout,
            makeID: CountingIDs().next)
        let reads = reads
        let removals = removals
        let clock = clock
        controller = HandoffController(
            store: store, binderStore: binderStore, drive: drive, trigger: trigger,
            routineCredentials: credentials ?? self.credentials,
            renderer: renderer ?? self.renderer,
            hasher: FakeHasher([
                Data("pdf".utf8): Data(repeating: 0xAB, count: 32),
                Data("pdf2".utf8): Data(repeating: 0xCD, count: 32),
            ]),
            today: { clock.today }, readFile: { _ in try reads.read() },
            removeFile: { removals.remove($0) })
    }

    private func fired(_ index: Int) throws -> [String: Any] {
        let text = try #require(trigger.texts[safe: index])
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(object as? [String: Any])
    }

    private func saved() throws -> DayHandoff {
        try #require(try store.handoff(date))
    }

    private func uploads() async -> [FakeDrive.Call] {
        await drive.calls.filter {
            if case .uploadPDF = $0 { return true }
            return false
        }
    }

    // MARK: - Finish

    @Test("finishing renders, uploads, creates the Doc and asks Claude for the notes")
    func finishSends() async throws {
        await controller.finish(binder)
        #expect(renderer.fileNames == ["2026-09-30-finished.pdf"])
        #expect(renderer.plans.count == 1)
        #expect(removals.urls == [renderer.url])
        #expect(
            await drive.calls == [
                .folderID(named: "Magenda"),
                .uploadPDF(
                    data: Data("pdf".utf8), name: "Magenda 2026-09-30.pdf", folderID: "folder-1",
                    replacing: nil),
                .createDoc(
                    name: "Magenda 2026-09-30 notes", folderID: "folder-1",
                    text: DocStatus.initialDocText),
            ])
        let payload = try fired(0)
        #expect(trigger.texts.count == 1)
        #expect(payload["step"] as? String == "notes")
        #expect(payload["checksum"] as? String == "sha256:" + String(repeating: "ab", count: 32))
        #expect(payload["driveFileID"] as? String == "file-1")
        #expect(payload["docID"] as? String == "doc-1")
        let handoff = try saved()
        #expect(handoff.stage == .notesRequested)
        #expect(handoff.sessionURL == trigger.sessionURL)
        #expect(handoff.lastError == nil)
        #expect(try store.pdf(for: date) == Data("pdf".utf8))
        #expect(controller.days == [handoff])
        #expect(controller.message == "Sent to Claude. The notes appear in the day's Google Doc.")
        #expect(!controller.isBusy)
        #expect(!controller.canFinish(date))
        #expect(
            controller.docURL(for: date)?.absoluteString
                == "https://docs.google.com/document/d/doc-1/edit")
        #expect(controller.docURL(for: otherDay) == nil)
    }

    @Test("finishing offline queues the day, and a later refresh completes it")
    func finishOffline() async throws {
        await drive.setError(GoogleAPIError.network, for: .folderID)
        await controller.finish(binder)
        #expect(try saved().stage == .queued)
        #expect(try saved().lastError == GoogleAPIError.network.userMessage)
        #expect(controller.message == GoogleAPIError.network.userMessage)
        #expect(trigger.texts.isEmpty)
        #expect(controller.canFinish(date))
        await drive.setError(nil, for: .folderID)
        await controller.refresh(excluding: otherDay)
        #expect(try saved().stage == .notesRequested)
        #expect(try saved().lastError == nil)
        #expect(trigger.texts.count == 1)
    }

    @Test("a trigger error leaves the day uploaded; only Try again fires again")
    func triggerError() async throws {
        trigger.setError(RoutineTriggerError.rejectedToken)
        await controller.finish(binder)
        #expect(try saved().stage == .uploaded)
        #expect(try saved().lastError == RoutineTriggerError.rejectedToken.userMessage)
        #expect(controller.message == RoutineTriggerError.rejectedToken.userMessage)
        #expect(controller.canFinish(date))
        #expect(trigger.texts.count == 1)
        trigger.setError(nil)
        await controller.refresh(excluding: otherDay)
        #expect(try saved().stage == .uploaded)
        #expect(trigger.texts.count == 1)
        await controller.perform(.retry, on: date)
        #expect(try saved().stage == .notesRequested)
        #expect(try saved().lastError == nil)
        #expect(trigger.texts.count == 2)
        #expect(await uploads().count == 1)
    }

    @Test("while a finish is held in the upload, a second finish, a refresh and a perform return")
    func oneRunAtATime() async throws {
        let held = FakeDrive(holdingUpload: true)
        let rig = try HandoffControllerTests(drive: held)
        let first = Task { await rig.controller.finish(rig.binder) }
        await held.waitUntilBlocked()
        #expect(rig.controller.isBusy)
        await rig.controller.finish(rig.binder)
        await rig.controller.refresh(excluding: rig.otherDay)
        await rig.controller.perform(.retry, on: rig.date)
        #expect(rig.renderer.fileNames.count == 1)
        #expect(await held.calls.count == 2)
        await held.release()
        await first.value
        #expect(!rig.controller.isBusy)
        #expect(await rig.uploads().count == 1)
        #expect(rig.trigger.texts.count == 1)
        #expect(try rig.saved().stage == .notesRequested)
    }

    @Test("finishing again before sending keeps the Drive IDs and replaces the PDF")
    func finishAgain() async throws {
        trigger.setError(RoutineTriggerError.network)
        await controller.finish(binder)
        trigger.setError(nil)
        reads.set(Data("pdf2".utf8))
        await controller.finish(binder)
        let calls = await drive.calls
        #expect(calls.count == 5)
        #expect(
            calls[4]
                == .uploadPDF(
                    data: Data("pdf2".utf8), name: "Magenda 2026-09-30.pdf",
                    folderID: "folder-1", replacing: "file-1"))
        #expect(calls.filter { if case .createDoc = $0 { true } else { false } }.count == 1)
        let handoff = try saved()
        #expect(handoff.driveFileID == "file-1")
        #expect(handoff.docID == "doc-1")
        #expect(handoff.stage == .notesRequested)
        #expect(handoff.checksum == "sha256:" + String(repeating: "cd", count: 32))
        #expect(try store.pdf(for: date) == Data("pdf2".utf8))
        #expect(try fired(1)["docID"] as? String == "doc-1")
    }

    @Test("finishing after the notes were requested is refused")
    func finishRefused() async throws {
        await controller.finish(binder)
        await controller.finish(binder)
        #expect(controller.message == "This day was already sent to Claude.")
        #expect(renderer.fileNames.count == 1)
        #expect(trigger.texts.count == 1)
    }

    @Test("a missing PDF is reported on the day")
    func missingPDF() async throws {
        await drive.setError(GoogleAPIError.network, for: .folderID)
        await controller.finish(binder)
        try store.deletePDF(for: date)
        await controller.refresh(excluding: otherDay)
        #expect(try saved().lastError == "This day's PDF is missing. Finish the day again.")
        #expect(try saved().stage == .queued)
    }

    @Test("a render failure queues nothing")
    func renderFails() async throws {
        let rig = try HandoffControllerTests(renderer: FakeRenderer(fails: true))
        await rig.controller.finish(rig.binder)
        #expect(rig.controller.message == "Couldn't create the PDF. Try again.")
        #expect(rig.controller.days.isEmpty)
        #expect(try rig.store.handoffs().isEmpty)
        #expect(await rig.drive.calls.isEmpty)
        #expect(!rig.controller.isBusy)
    }

    @Test("a file that cannot be read queues nothing and is still removed")
    func readFails() async throws {
        reads.failFromNowOn()
        await controller.finish(binder)
        #expect(controller.message == "Couldn't create the PDF. Try again.")
        #expect(controller.days.isEmpty)
        #expect(removals.urls == [renderer.url])
    }

    @Test("a store failure queues nothing")
    func storeFails() async throws {
        let rig = try HandoffControllerTests(store: FailingHandoffStore(failing: [.savePDF]))
        await rig.controller.finish(rig.binder)
        #expect(
            rig.controller.message
                == "Couldn't save the finished day. Free some space on this device and try again.")
        #expect(rig.controller.days.isEmpty)
        #expect(await rig.drive.calls.isEmpty)
    }

    @Test("a store failure during the upload is recorded on the day")
    func storeFailsDuringUpload() async throws {
        let failing = FailingHandoffStore()
        failing.failSave(after: 1)
        let rig = try HandoffControllerTests(store: failing)
        await rig.controller.finish(rig.binder)
        let message =
            "Couldn't save the finished day. Free some space on this device and try again."
        #expect(rig.controller.days.first?.lastError == message)
        #expect(rig.controller.message == message)
        #expect(rig.trigger.texts.isEmpty)
    }

    @Test("an error that is not Google's or Claude's gets a general message")
    func otherError() async throws {
        await drive.setError(OtherFailure(), for: .createDoc)
        await controller.finish(binder)
        #expect(try saved().lastError == "Something went wrong. Try again.")
        #expect(try saved().driveFileID == "file-1")
        #expect(try saved().docID == nil)
    }

    // MARK: - Review loop

    @Test("a refresh reads the Doc and moves a day to notes ready")
    func refreshReadsDoc() async throws {
        await controller.finish(binder)
        #expect(controller.days.first?.phase == .writingNotes)
        await controller.refresh(excluding: otherDay)
        #expect(try saved().docStatus == .waitingForNotes)
        await drive.setExportedText("\u{FEFF}Status: Notes ready for review\nNotes")
        await controller.refresh(excluding: otherDay)
        #expect(try saved().docStatus == .notesReady)
        #expect(controller.days.first?.phase == .notesReady)
        #expect(await drive.calls.last == .exportText(docID: "doc-1"))
    }

    @Test("a Doc that cannot be read sets the error and the refresh goes on")
    func refreshDocError() async throws {
        await controller.finish(binder)
        await drive.setError(GoogleAPIError.notFound, for: .exportText)
        await controller.refresh(excluding: otherDay)
        #expect(try saved().lastError == GoogleAPIError.notFound.userMessage)
        #expect(try saved().stage == .notesRequested)
    }

    @Test("approving the notes fires the step and reads the Doc again")
    func approveNotes() async throws {
        await controller.finish(binder)
        await drive.setExportedText("Status: Notes ready for review\n")
        await controller.refresh(excluding: otherDay)
        await drive.setExportedText("Status: Summary ready for review\n")
        await controller.perform(.approve(.approveNotes), on: date)
        #expect(try fired(1)["step"] as? String == "approve-notes")
        #expect(try saved().stage == .notesApproved)
        #expect(try saved().docStatus == .summaryReady)
        #expect(controller.days.first?.phase == .summaryReady)
        await controller.perform(.approve(.approveSummary), on: date)
        #expect(try fired(2)["step"] as? String == "approve-summary")
        #expect(try saved().stage == .summaryApproved)
        #expect(controller.days.first?.phase == .closing)
    }

    @Test("approving the notes of a day that closes at once makes it closed")
    func approveClosesAtOnce() async throws {
        await controller.finish(binder)
        await drive.setExportedText("Status: Notes ready for review\n")
        await controller.refresh(excluding: otherDay)
        await drive.setExportedText("Status: Closed\n")
        await controller.perform(.approve(.approveNotes), on: date)
        let closeOn = try #require(CalendarDay(year: 2026, month: 10, day: 6))
        #expect(try saved().closedOn == clock.today)
        #expect(controller.days.first?.phase == .closed(deleteOn: closeOn, purged: false))
    }

    @Test("an approve the phase does not offer does nothing")
    func approveNotOffered() async throws {
        await controller.finish(binder)
        await controller.perform(.approve(.approveNotes), on: date)
        await controller.perform(.approve(.approveSummary), on: date)
        await controller.perform(.retry, on: date)
        await controller.perform(.retry, on: otherDay)
        #expect(trigger.texts.count == 1)
        #expect(try saved().stage == .notesRequested)
    }

    @Test("a failed approve keeps the stage and records the error")
    func approveFails() async throws {
        await controller.finish(binder)
        await drive.setExportedText("Status: Notes ready for review\n")
        await controller.refresh(excluding: otherDay)
        trigger.setError(RoutineTriggerError.unavailable)
        await controller.perform(.approve(.approveNotes), on: date)
        #expect(try saved().stage == .notesRequested)
        #expect(try saved().lastError == RoutineTriggerError.unavailable.userMessage)
        #expect(controller.days.first?.phase == .notesReady)
    }

    // MARK: - Purge

    @Test("the day's files are deleted five days after the Doc was first read as closed")
    func purge() async throws {
        try binderStore.saveDay(binder.day)
        await controller.finish(binder)
        await drive.setExportedText("Status: Closed\n")
        await controller.refresh(excluding: otherDay)
        #expect(try saved().closedOn == clock.today)
        #expect(try saved().purged == false)
        // Later reads do not move the day the clock started.
        clock.set(try #require(CalendarDay(year: 2026, month: 10, day: 5)))
        await controller.refresh(excluding: otherDay)
        #expect(try saved().closedOn == CalendarDay(year: 2026, month: 10, day: 1))
        #expect(try saved().purged == false)
        #expect(try binderStore.day(date) != nil)
        // On the fifth day it is due, but the open day is kept.
        clock.set(try #require(CalendarDay(year: 2026, month: 10, day: 6)))
        await controller.refresh(excluding: date)
        #expect(try saved().purged == false)
        #expect(try binderStore.day(date) != nil)
        #expect(try store.pdf(for: date) != nil)
        await controller.refresh(excluding: otherDay)
        #expect(try saved().purged)
        #expect(controller.days.first?.purged == true)
        #expect(try binderStore.day(date) == nil)
        #expect(try store.pdf(for: date) == nil)
        let deleteOn = try #require(CalendarDay(year: 2026, month: 10, day: 6))
        #expect(controller.days.first?.phase == .closed(deleteOn: deleteOn, purged: true))
        #expect(!controller.canFinish(date))
        await controller.finish(binder)
        #expect(controller.message == "This day was already sent to Claude.")
        #expect(await uploads().count == 1)
    }

    @Test("a purge that fails is tried again by the next refresh")
    func purgeRetries() async throws {
        let failing = FailingBinderStore(.unwritable, failing: [.deleteDay])
        let rig = try HandoffControllerTests(binderStore: failing)
        await rig.controller.finish(rig.binder)
        await rig.drive.setExportedText("Status: Closed\n")
        await rig.controller.refresh(excluding: rig.otherDay)
        rig.clock.set(try #require(CalendarDay(year: 2026, month: 10, day: 6)))
        await rig.controller.refresh(excluding: rig.otherDay)
        #expect(try rig.saved().purged == false)
        #expect(try rig.store.pdf(for: rig.date) != nil)
        failing.setFailing([])
        await rig.controller.refresh(excluding: rig.otherDay)
        #expect(try rig.saved().purged)
    }

    // MARK: - Start and routine

    @Test("start loads the finished days and the stored routine")
    func startLoads() async throws {
        await controller.finish(binder)
        let credentials = InMemoryRoutineCredentialsStore()
        credentials.save(
            try #require(RoutineCredentials(fireURL: Self.fireURL, token: Self.token)))
        let rig = try HandoffControllerTests(store: store, credentials: credentials)
        #expect(rig.controller.days.isEmpty)
        rig.controller.start()
        #expect(rig.controller.days.map(\.date) == [date])
        #expect(rig.controller.routineTriggerID == "trig_abc")
        #expect(rig.controller.message == nil)
    }

    @Test("start with an unreadable store says so and shows no days")
    func startFails() async throws {
        let rig = try HandoffControllerTests(store: FailingHandoffStore(failing: [.handoffs]))
        rig.controller.start()
        #expect(rig.controller.message == "Couldn't read the finished days on this device.")
        #expect(rig.controller.days.isEmpty)
        #expect(rig.controller.routineTriggerID == nil)
    }

    @Test("a bad fire URL and a bad token are rejected with their messages")
    func saveRoutineRejects() {
        #expect(!controller.saveRoutine(fireURL: "https://example.com/fire", token: Self.token))
        #expect(
            controller.message
                == "That isn't a routine fire URL. Copy it from the routine's API trigger at claude.ai/code/routines; it ends in /fire."
        )
        #expect(!controller.saveRoutine(fireURL: Self.fireURL, token: "nope"))
        #expect(controller.message == "That isn't a routine token. It starts with sk-ant-oat01-.")
        #expect(controller.routineTriggerID == nil)
        #expect(credentials.load() == nil)
    }

    @Test("a valid routine is saved and can be forgotten")
    func saveAndForgetRoutine() throws {
        #expect(!controller.saveRoutine(fireURL: "bad", token: Self.token))
        #expect(controller.saveRoutine(fireURL: " \(Self.fireURL) ", token: " \(Self.token)\n"))
        #expect(controller.message == nil)
        #expect(controller.routineTriggerID == "trig_abc")
        #expect(credentials.load()?.token == Self.token)
        controller.forgetRoutine()
        #expect(controller.routineTriggerID == nil)
        #expect(credentials.load() == nil)
    }

    @Test("a Keychain failure is reported and keeps the routine unset")
    func keychainFails() throws {
        let rig = try HandoffControllerTests(credentials: FailingCredentialsStore())
        #expect(!rig.controller.saveRoutine(fireURL: Self.fireURL, token: Self.token))
        #expect(rig.controller.message == "Couldn't save the routine in the Keychain. Try again.")
        #expect(rig.controller.routineTriggerID == nil)
        rig.controller.forgetRoutine()
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
