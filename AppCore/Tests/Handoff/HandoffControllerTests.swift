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
        case handoffs, save, savePDF, deleteHandoff
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

    func handoff(_ id: HandoffID) throws -> DayHandoff? {
        try base.handoff(id)
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

    func pdf(for id: HandoffID) throws -> Data? {
        try base.pdf(for: id)
    }

    func savePDF(_ data: Data, for id: HandoffID) throws {
        try check(.savePDF)
        try base.savePDF(data, for: id)
    }

    func deletePDF(for id: HandoffID) throws {
        try base.deletePDF(for: id)
    }

    func deleteHandoff(for date: CalendarDay) throws {
        try check(.deleteHandoff)
        try base.deleteHandoff(for: date)
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

private struct FailingSummaryCredentialsStore: SummaryRoutineCredentialsStore {
    func load(id: String) throws -> RoutineCredentials? { nil }
    func save(_ credentials: RoutineCredentials, id: String) throws { throw KeychainFailure() }
    func delete(id: String) throws { throw KeychainFailure() }
}

private struct OtherFailure: Error {}

@MainActor
private final class FolderNameBox {
    var name = "Magenda"
}

@MainActor
@Suite("Hand-off controller")
struct HandoffControllerTests {
    private static let fireURL = "https://api.anthropic.com/v1/claude_code/routines/trig_abc/fire"
    private static let token = "sk-ant-oat01-secret"

    private let date: CalendarDay
    private let otherDay: CalendarDay
    private let drive: FakeDrive
    private let trigger = FakeRoutineTrigger()
    private let summaryTrigger = FakeSummaryTrigger()
    private let summaryCredentials = InMemorySummaryRoutineCredentialsStore()
    private let renderer = FakeRenderer(url: URL(fileURLWithPath: "/tmp/finished.pdf"))
    private let store: any HandoffStore
    private let binderStore: any BinderStore
    private let credentials = InMemoryRoutineCredentialsStore()
    private let clock: TestClock
    private let reads = Reads()
    private let removals = Removals()
    private let layout: BinderLayout
    private let binder: BinderSession
    private let controller: HandoffController

    init(
        drive: FakeDrive = FakeDrive(), renderer: FakeRenderer? = nil,
        store: any HandoffStore = InMemoryHandoffStore(),
        binderStore: any BinderStore = InMemoryBinderStore(),
        credentials: (any RoutineCredentialsStore)? = nil,
        summaryCredentials: (any SummaryRoutineCredentialsStore)? = nil,
        routines: [SummaryRoutine] = [],
        folderName: (@MainActor () -> String)? = nil
    ) throws {
        layout = BinderLayout(
            manifest: try TemplateManifest.bundled(), measurer: FakeTextMeasurer())
        date = try #require(CalendarDay(year: 2026, month: 9, day: 30))
        otherDay = try #require(CalendarDay(year: 2026, month: 9, day: 1))
        let day = Self.binderDay(on: date, routines: routines)
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
        let hasher = FakeHasher([
            Data("pdf".utf8): Data(repeating: 0xAB, count: 32),
            Data("pdf2".utf8): Data(repeating: 0xCD, count: 32),
        ])
        if let folderName {
            controller = HandoffController(
                store: store, binderStore: binderStore, drive: drive, trigger: trigger,
                routineCredentials: credentials ?? self.credentials,
                summaryTrigger: summaryTrigger,
                summaryCredentials: summaryCredentials ?? self.summaryCredentials,
                renderer: renderer ?? self.renderer, hasher: hasher,
                today: { clock.today }, readFile: { _ in try reads.read() },
                removeFile: { removals.remove($0) }, folderName: folderName)
        } else {
            controller = HandoffController(
                store: store, binderStore: binderStore, drive: drive, trigger: trigger,
                routineCredentials: credentials ?? self.credentials,
                summaryTrigger: summaryTrigger,
                summaryCredentials: summaryCredentials ?? self.summaryCredentials,
                renderer: renderer ?? self.renderer, hasher: hasher,
                today: { clock.today }, readFile: { _ in try reads.read() },
                removeFile: { removals.remove($0) })
        }
    }

    private static let memo = SummaryRoutine(
        id: "11111111-1111-4111-8111-111111111111", name: "Client memo")
    private static let decisionLog = SummaryRoutine(
        id: "22222222-2222-4222-8222-222222222222", name: "Decision log")

    private static func binderDay(
        on date: CalendarDay, routines: [SummaryRoutine] = []
    ) -> BinderDay {
        BinderDay(
            content: AgendaContent(
                date: date, todoItems: [],
                schedule: [ScheduleEntry(slot: 2, text: "A", meetingIndex: 0)],
                meetings: ["A"], meetingIDs: ["cal|a"], delegated: [],
                meetingSummaryRoutines: routines.isEmpty ? [] : [routines]),
            theme: Theme())
    }

    private func fired(_ index: Int) throws -> [String: Any] {
        let text = try #require(trigger.texts[safe: index])
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(object as? [String: Any])
    }

    private var dayID: HandoffID {
        HandoffID(date: date, part: nil)
    }

    private func saved() throws -> DayHandoff {
        try #require(try store.handoff(dayID))
    }

    private func uploads() async -> [FakeDrive.Call] {
        await drive.calls.filter {
            if case .uploadPDF = $0 { return true }
            return false
        }
    }

    private func partID(_ number: Int) -> HandoffID {
        HandoffID(date: date, part: number)
    }

    /// A record of the meeting sent as part `number`, as the store would hold it.
    private func partRecord(
        _ number: Int, stage: HandoffStage = .closing, closedOn: CalendarDay? = nil,
        docID: String? = nil
    ) -> DayHandoff {
        var record = DayHandoff(
            date: date, checksum: "sha256:" + String(repeating: "ef", count: 32),
            pages: [HandoffPage(page: 1, key: "meeting:cal|a")], tasks: [], delegated: [],
            part: HandoffPart(number: number, meetingKey: "meeting:cal|a", title: "A"))
        record.stage = stage
        record.closedOn = closedOn
        record.docID = docID
        return record
    }

    /// A day record that was sent and closed on `closedOn`.
    private func closedDayRecord(on closedOn: CalendarDay) -> DayHandoff {
        var record = DayHandoff(
            date: date, checksum: "sha256:" + String(repeating: "ab", count: 32),
            pages: [HandoffPage(page: 1, key: "meeting:cal|a")], tasks: [], delegated: [])
        record.stage = .closing
        record.closedOn = closedOn
        return record
    }

    /// Saves `records` with a PDF each straight into the store and loads them.
    private func seed(_ records: [DayHandoff]) throws {
        for record in records {
            try store.save(record)
            try store.savePDF(Data("pdf-\(record.id.part ?? 0)".utf8), for: record.id)
        }
        controller.start()
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
        #expect(try store.pdf(for: dayID) == Data("pdf".utf8))
        #expect(controller.days == [handoff])
        #expect(controller.message == "Sent to Claude. The notes appear in the day's Google Doc.")
        #expect(!controller.isBusy)
        #expect(!controller.canFinish(date))
        #expect(
            controller.docURL(for: dayID)?.absoluteString
                == "https://docs.google.com/document/d/doc-1/edit")
        #expect(controller.docURL(for: HandoffID(date: otherDay, part: nil)) == nil)
    }

    @Test("resetting a sent day forgets it, so it can be finished and sent again")
    func resetAfterSending() async throws {
        await controller.finish(binder)
        #expect(controller.hasHandoff(on: date))
        controller.resetHandoff(for: date)
        #expect(!controller.hasHandoff(on: date))
        #expect(controller.days.isEmpty)
        #expect(try store.handoff(dayID) == nil)
        #expect(try store.pdf(for: dayID) == nil)
        #expect(controller.canFinish(date))
        #expect(controller.message == "This day can be finished again.")
        await controller.finish(binder)
        #expect(try saved().stage == .notesRequested)
        #expect(trigger.texts.count == 2)
        #expect(await uploads().count == 2)
    }

    @Test("resetting a day that was never finished does nothing")
    func resetWithoutHandoff() async throws {
        controller.resetHandoff(for: date)
        #expect(controller.message == nil)
        #expect(!controller.hasHandoff(on: date))
    }

    @Test("a reset that cannot delete keeps the day and says so")
    func resetFails() async throws {
        let failing = FailingHandoffStore(failing: [.deleteHandoff])
        let rig = try HandoffControllerTests(store: failing)
        await rig.controller.finish(rig.binder)
        rig.controller.resetHandoff(for: rig.date)
        #expect(rig.controller.hasHandoff(on: rig.date))
        #expect(try failing.handoff(rig.dayID) != nil)
        #expect(rig.controller.message == "Couldn't reset this day. Try again.")
    }

    @Test("finished days are listed newest first")
    func daysNewestFirst() async throws {
        let older = Self.binderDay(on: otherDay)
        let olderBinder = BinderSession(
            day: older, plan: layout.plan(for: older), ink: [:], store: binderStore,
            layout: layout, makeID: CountingIDs().next)
        await controller.finish(olderBinder)
        await controller.finish(binder)
        #expect(controller.days.map(\.date) == [date, otherDay])
        await controller.finish(olderBinder)
        #expect(controller.days.map(\.date) == [date, otherDay])
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
        #expect(try saved().lastError == RoutineTriggerError.rejectedToken.userMessage)
        #expect(trigger.texts.count == 1)
        await controller.perform(.retry, on: dayID)
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
        await rig.controller.perform(.retry, on: rig.dayID)
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
        #expect(calls.count == 4)
        #expect(calls.filter { if case .folderID = $0 { true } else { false } }.count == 1)
        #expect(
            calls[3]
                == .uploadPDF(
                    data: Data("pdf2".utf8), name: "Magenda 2026-09-30.pdf",
                    folderID: "folder-1", replacing: "file-1"))
        #expect(calls.filter { if case .createDoc = $0 { true } else { false } }.count == 1)
        let handoff = try saved()
        #expect(handoff.driveFileID == "file-1")
        #expect(handoff.docID == "doc-1")
        #expect(handoff.folderID == "folder-1")
        #expect(handoff.stage == .notesRequested)
        #expect(handoff.checksum == "sha256:" + String(repeating: "cd", count: 32))
        #expect(try store.pdf(for: dayID) == Data("pdf2".utf8))
        #expect(try fired(1)["docID"] as? String == "doc-1")
    }

    @Test("the first upload uses the folder the setting names")
    func folderFromSetting() async throws {
        let box = FolderNameBox()
        let rig = try HandoffControllerTests(folderName: { box.name })
        box.name = "Work notes"
        await rig.controller.finish(rig.binder)
        #expect(await rig.drive.calls.contains(.folderID(named: "Work notes")))
        #expect(try rig.saved().folderID == "folder-1")
    }

    @Test("a day keeps the folder of its first upload")
    func dayKeepsFolder() async throws {
        let box = FolderNameBox()
        let rig = try HandoffControllerTests(folderName: { box.name })
        await rig.drive.setError(GoogleAPIError.network, for: .createDoc)
        await rig.controller.finish(rig.binder)
        box.name = "Other"
        await rig.drive.setError(nil, for: .createDoc)
        await rig.controller.refresh(excluding: rig.otherDay)
        let calls = await rig.drive.calls
        let folderCalls = calls.filter { if case .folderID = $0 { true } else { false } }
        #expect(folderCalls == [.folderID(named: "Magenda")])
        let docCalls = calls.filter { if case .createDoc = $0 { true } else { false } }
        #expect(docCalls.count == 2)
        for case .createDoc(_, let folderID, _) in docCalls {
            #expect(folderID == "folder-1")
        }
    }

    @Test("a meeting and its day share a folder across a rename")
    func meetingAndDayShareFolder() async throws {
        let box = FolderNameBox()
        let rig = try HandoffControllerTests(folderName: { box.name })
        let meeting = rig.meetingBinder()
        await rig.controller.sendMeeting(containing: Self.meetingA, of: meeting)
        box.name = "Other"
        await rig.controller.finish(meeting)
        let folderCalls = await rig.drive.calls.filter {
            if case .folderID = $0 { true } else { false }
        }
        #expect(folderCalls == [.folderID(named: "Magenda")])
        #expect(rig.controller.days.count == 2)
        #expect(rig.controller.days.allSatisfy { $0.folderID == "folder-1" })
    }

    @Test("a day uploaded before folders were recorded is replaced in the default folder")
    func legacyDayUsesDefaultFolder() async throws {
        let box = FolderNameBox()
        let store = InMemoryHandoffStore()
        var legacy = DayHandoff(
            date: try #require(CalendarDay(year: 2026, month: 9, day: 30)),
            checksum: "sha256:" + String(repeating: "ab", count: 32),
            pages: [HandoffPage(page: 1, key: "meeting:cal|a")], tasks: [], delegated: [])
        legacy.driveFileID = "file-0"
        legacy.stage = .queued
        try store.savePDF(Data("pdf".utf8), for: legacy.id)
        try store.save(legacy)
        let rig = try HandoffControllerTests(store: store, folderName: { box.name })
        box.name = "Other"
        rig.controller.start()
        await rig.controller.refresh(excluding: rig.otherDay)
        let folderCalls = await rig.drive.calls.filter {
            if case .folderID = $0 { true } else { false }
        }
        #expect(folderCalls == [.folderID(named: "Magenda")])
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
        try store.deletePDF(for: dayID)
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

    @Test("a refresh clears the error of a day once its Doc read succeeds past the upload")
    func refreshClearsErrorAfterUpload() async throws {
        await controller.finish(binder)
        await drive.setError(GoogleAPIError.notFound, for: .exportText)
        await controller.refresh(excluding: otherDay)
        #expect(try saved().lastError == GoogleAPIError.notFound.userMessage)
        await drive.setError(nil, for: .exportText)
        await controller.refresh(excluding: otherDay)
        #expect(try saved().stage == .notesRequested)
        #expect(try saved().lastError == nil)
    }

    @Test("a refresh keeps the error of a queued day that has a Doc")
    func refreshKeepsQueuedError() async throws {
        await drive.setError(GoogleAPIError.network, for: .folderID)
        await controller.finish(binder)
        var queued = try saved()
        queued.docID = "doc-1"
        try store.save(queued)
        controller.start()
        await controller.refresh(excluding: otherDay)
        #expect(try saved().stage == .queued)
        #expect(try saved().lastError == GoogleAPIError.network.userMessage)
        #expect(await drive.calls.last == .exportText(docID: "doc-1"))
    }

    @Test("approving the notes with no summary asked for fires close once and ends in closing")
    func approveNotesWithoutSummaries() async throws {
        await controller.finish(binder)
        await drive.setExportedText("Status: Notes ready for review\n")
        await controller.refresh(excluding: otherDay)
        await controller.perform(.approveNotes, on: dayID)
        #expect(trigger.texts.count == 2)
        #expect(try fired(1)["step"] as? String == "close")
        #expect(summaryTrigger.fires.isEmpty)
        #expect(try saved().stage == .closing)
        #expect(try saved().sessionURL == trigger.sessionURL)
        #expect(controller.days.first?.phase == .closing)
        #expect(await drive.calls.last == .exportText(docID: "doc-1"))
    }

    @Test("approving the notes of a day that closes at once makes it closed")
    func approveClosesAtOnce() async throws {
        await controller.finish(binder)
        await drive.setExportedText("Status: Notes ready for review\n")
        await controller.refresh(excluding: otherDay)
        await drive.setExportedText("Status: Closed\n")
        await controller.perform(.approveNotes, on: dayID)
        let closeOn = try #require(CalendarDay(year: 2026, month: 10, day: 6))
        #expect(try saved().closedOn == clock.today)
        #expect(controller.days.first?.phase == .closed(deleteOn: closeOn, purged: false))
    }

    @Test("an approve the phase does not offer does nothing")
    func approveNotOffered() async throws {
        await controller.finish(binder)
        await controller.perform(.approveNotes, on: dayID)
        await controller.perform(.approveSummaries, on: dayID)
        await controller.perform(.retry, on: dayID)
        await controller.perform(.retry, on: HandoffID(date: otherDay, part: nil))
        #expect(trigger.texts.count == 1)
        #expect(try saved().stage == .notesRequested)
    }

    @Test("a failed approve keeps the stage and records the error")
    func approveFails() async throws {
        await controller.finish(binder)
        await drive.setExportedText("Status: Notes ready for review\n")
        await controller.refresh(excluding: otherDay)
        trigger.setError(RoutineTriggerError.unavailable)
        await controller.perform(.approveNotes, on: dayID)
        #expect(try saved().stage == .notesRequested)
        #expect(try saved().lastError == RoutineTriggerError.unavailable.userMessage)
        #expect(controller.days.first?.phase == .notesReady)
    }

    // MARK: - Summaries

    /// The Doc text a summary routine leaves for `routines` on the meeting page of `record`.
    private func summaryText(_ routines: [SummaryRoutine], of record: DayHandoff) throws -> String {
        let page = try #require(record.pages.first { $0.key == "meeting:cal|a" }).page
        return "Status: Notes ready for review\n"
            + routines.map { "Summary ready: \($0.id) \(page)\nFixture summary.\n" }.joined()
    }

    /// Finishes the day and reads its Doc as notes ready for review.
    private func reachNotesReady() async {
        await controller.finish(binder)
        await drive.setExportedText("Status: Notes ready for review\n")
        await controller.refresh(excluding: otherDay)
    }

    private func summaryPayload(_ index: Int) throws -> [String: Any] {
        let text = try #require(summaryTrigger.fires[safe: index]?.text)
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(object as? [String: Any])
    }

    @Test("approving the notes starts each summary routine once with its own payload")
    func approveNotesStartsSummaries() async throws {
        let rig = try HandoffControllerTests(routines: [Self.memo, Self.decisionLog])
        await rig.reachNotesReady()
        await rig.controller.perform(.approveNotes, on: rig.dayID)
        #expect(rig.summaryTrigger.fires.map(\.routineID) == [Self.memo.id, Self.decisionLog.id])
        #expect(try rig.summaryPayload(0)["routineName"] as? String == "Client memo")
        #expect(try rig.summaryPayload(1)["routineName"] as? String == "Decision log")
        #expect(try rig.summaryPayload(1)["schema"] as? String == "magenda.summary/1")
        let meetings = try #require(try rig.summaryPayload(0)["meetings"] as? [[String: Any]])
        #expect(meetings.map { $0["key"] as? String } == ["meeting:cal|a"])
        #expect(rig.trigger.texts.count == 1)
        let handoff = try rig.saved()
        #expect(handoff.stage == .summariesRequested)
        #expect(handoff.firedSummaries == [Self.memo.id, Self.decisionLog.id])
        #expect(handoff.sessionURL == rig.summaryTrigger.sessionURL)
        #expect(handoff.lastError == nil)
        #expect(rig.controller.days.first?.phase == .writingSummaries)
        #expect(await rig.drive.calls.last == .exportText(docID: "doc-1"))
    }

    @Test("markers read by a refresh flip the row to summaries ready, and approving closes")
    func summariesReadyThenApprove() async throws {
        let rig = try HandoffControllerTests(routines: [Self.memo, Self.decisionLog])
        await rig.reachNotesReady()
        await rig.controller.perform(.approveNotes, on: rig.dayID)
        await rig.drive.setExportedText(try rig.summaryText([Self.memo], of: try rig.saved()))
        await rig.controller.refresh(excluding: rig.otherDay)
        #expect(try rig.saved().summaryMarkers.count == 1)
        #expect(rig.controller.days.first?.phase == .writingSummaries)
        await rig.drive.setExportedText(
            try rig.summaryText([Self.memo, Self.decisionLog], of: try rig.saved()))
        await rig.controller.refresh(excluding: rig.otherDay)
        #expect(try rig.saved().summaryMarkers.count == 2)
        #expect(rig.controller.days.first?.phase == .summaryReady)
        await rig.controller.perform(.approveSummaries, on: rig.dayID)
        #expect(rig.trigger.texts.count == 2)
        #expect(try rig.fired(1)["step"] as? String == "close")
        #expect(rig.summaryTrigger.fires.count == 2)
        #expect(try rig.saved().stage == .closing)
        #expect(rig.controller.days.first?.phase == .closing)
    }

    @Test("a failing second routine leaves the day pending and Try again fires only that one")
    func secondSummaryFails() async throws {
        let rig = try HandoffControllerTests(routines: [Self.memo, Self.decisionLog])
        await rig.reachNotesReady()
        rig.summaryTrigger.setFailing([Self.decisionLog.id])
        await rig.controller.perform(.approveNotes, on: rig.dayID)
        let failure = "Something went wrong. Try again."
        var handoff = try rig.saved()
        #expect(handoff.stage == .summariesPending)
        #expect(handoff.firedSummaries == [Self.memo.id])
        #expect(handoff.lastError == failure)
        #expect(rig.controller.days.first?.phase == .summariesWaitingToSend)
        #expect(rig.controller.days.first?.phase.action == .retry)

        await rig.controller.refresh(excluding: rig.otherDay)
        handoff = try rig.saved()
        #expect(handoff.stage == .summariesPending)
        #expect(handoff.lastError == failure)

        rig.summaryTrigger.setFailing([])
        await rig.controller.perform(.retry, on: rig.dayID)
        #expect(
            rig.summaryTrigger.fires.map(\.routineID)
                == [Self.memo.id, Self.decisionLog.id, Self.decisionLog.id])
        handoff = try rig.saved()
        #expect(handoff.stage == .summariesRequested)
        #expect(handoff.firedSummaries == [Self.memo.id, Self.decisionLog.id])
        #expect(handoff.lastError == nil)
        #expect(rig.trigger.texts.count == 1)
    }

    @Test("approving the notes saves the pending stage first, so a save failure fires nothing")
    func approveNotesSaveFails() async throws {
        let failing = FailingHandoffStore()
        let rig = try HandoffControllerTests(store: failing, routines: [Self.memo])
        var record = DayHandoff(
            date: rig.date, checksum: "sha256:" + String(repeating: "ab", count: 32),
            pages: [
                HandoffPage(
                    page: 1, key: "meeting:cal|a", calendarID: "cal", eventID: "a", title: "A",
                    summaryRoutines: [Self.memo])
            ], tasks: [], delegated: [])
        record.stage = .notesRequested
        record.docStatus = .notesReady
        record.docID = "doc-1"
        try rig.seed([record])
        failing.failSave(after: 0)
        await rig.controller.perform(.approveNotes, on: rig.dayID)
        #expect(rig.summaryTrigger.fires.isEmpty)
        #expect(
            rig.controller.days.first?.lastError
                == "Couldn't save the finished day. Free some space on this device and try again.")
    }

    @Test("a meeting sent early walks the same flow: summaries for its part, then close")
    func meetingSummariesFlow() async throws {
        let rig = try HandoffControllerTests(routines: [Self.memo])
        let meeting = rig.meetingBinder(routines: [Self.memo])
        await rig.controller.sendMeeting(containing: Self.meetingA, of: meeting)
        await rig.drive.setExportedText("Status: Notes ready for review\n")
        await rig.controller.refresh(excluding: rig.otherDay)
        await rig.controller.perform(.approveNotes, on: rig.partID(1))
        let payload = try rig.summaryPayload(0)
        #expect(payload["scope"] as? String == "meeting")
        #expect(payload["part"] as? Int == 1)
        #expect(payload["routineID"] as? String == Self.memo.id)
        #expect(rig.summaryTrigger.fires.count == 1)
        let part = try #require(try rig.store.handoff(rig.partID(1)))
        #expect(part.stage == .summariesRequested)
        await rig.drive.setExportedText(try rig.summaryText([Self.memo], of: part))
        await rig.controller.refresh(excluding: rig.otherDay)
        #expect(rig.controller.days.first?.phase == .summaryReady)
        await rig.controller.perform(.approveSummaries, on: rig.partID(1))
        #expect(try rig.fired(1)["step"] as? String == "close")
        #expect(try rig.fired(1)["part"] as? Int == 1)
        #expect(try rig.store.handoff(rig.partID(1))?.stage == .closing)
        #expect(try rig.store.handoff(rig.dayID) == nil)
    }

    @Test("a summary routine with a bad name, URL or token is rejected with its message")
    func saveSummaryRoutineRejects() throws {
        #expect(
            controller.saveSummaryRoutine(name: " ", fireURL: Self.fireURL, token: Self.token)
                == nil)
        #expect(controller.message == SummaryRoutine.invalidNameMessage)
        #expect(
            controller.saveSummaryRoutine(
                name: "Memo", fireURL: "https://example.com/fire", token: Self.token) == nil)
        #expect(
            controller.message
                == "That isn't a routine fire URL. Copy it from the routine's API trigger at claude.ai/code/routines; it ends in /fire."
        )
        #expect(
            controller.saveSummaryRoutine(name: "Memo", fireURL: Self.fireURL, token: "nope")
                == nil)
        #expect(controller.message == "That isn't a routine token. It starts with sk-ant-oat01-.")
        #expect(try summaryCredentials.load(id: Self.memo.id) == nil)
    }

    @Test("a valid summary routine is stored, replaced under the same ID and forgotten")
    func saveReplaceAndForgetSummaryRoutine() throws {
        let saved = try #require(
            controller.saveSummaryRoutine(
                name: "  Client memo ", fireURL: Self.fireURL, token: Self.token,
                id: Self.memo.id))
        #expect(saved == Self.memo)
        #expect(controller.message == nil)
        #expect(try summaryCredentials.load(id: Self.memo.id)?.token == Self.token)

        let replaced = try #require(
            controller.saveSummaryRoutine(
                name: "Client memo", fireURL: Self.fireURL, token: "sk-ant-oat01-other",
                id: Self.memo.id))
        #expect(replaced.id == Self.memo.id)
        #expect(try summaryCredentials.load(id: Self.memo.id)?.token == "sk-ant-oat01-other")

        let fresh = try #require(
            controller.saveSummaryRoutine(name: "Log", fireURL: Self.fireURL, token: Self.token))
        #expect(SummaryRoutine.isValidID(fresh.id) && fresh.id != Self.memo.id)

        controller.forgetSummaryRoutine(id: Self.memo.id)
        #expect(try summaryCredentials.load(id: Self.memo.id) == nil)
        #expect(try summaryCredentials.load(id: fresh.id) != nil)
    }

    @Test("a Keychain failure saving a summary routine is reported")
    func summaryKeychainFails() throws {
        let rig = try HandoffControllerTests(summaryCredentials: FailingSummaryCredentialsStore())
        #expect(
            rig.controller.saveSummaryRoutine(
                name: "Memo", fireURL: Self.fireURL, token: Self.token) == nil)
        #expect(rig.controller.message == "Couldn't save the routine in the Keychain. Try again.")
        rig.controller.forgetSummaryRoutine(id: Self.memo.id)
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
        #expect(try store.pdf(for: dayID) != nil)
        await controller.refresh(excluding: otherDay)
        #expect(try saved().purged)
        #expect(controller.days.first?.purged == true)
        #expect(try binderStore.day(date) == nil)
        #expect(try store.pdf(for: dayID) == nil)
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
        #expect(try rig.store.pdf(for: rig.dayID) != nil)
        failing.setFailing([])
        await rig.controller.refresh(excluding: rig.otherDay)
        #expect(try rig.saved().purged)
    }

    // MARK: - Meetings sent early

    @Test("a part is listed after its day, parts by number, and remembering one keeps the day")
    func partsListAfterTheirDay() async throws {
        let closed = try #require(CalendarDay(year: 2026, month: 10, day: 1))
        try seed([
            partRecord(2, stage: .queued), partRecord(1), closedDayRecord(on: closed),
        ])
        #expect(controller.days.map(\.id) == [dayID, partID(1), partID(2)])
        await controller.refresh(excluding: otherDay)
        #expect(controller.days.map(\.id) == [dayID, partID(1), partID(2)])
        #expect(try saved().closedOn == closed)
        #expect(controller.hasHandoff(on: date))
        #expect(controller.canFinish(date) == false)
        let part = try #require(try store.handoff(partID(2)))
        #expect(part.stage == .notesRequested)
        #expect(part.driveFileID == "file-1")
        #expect(part.docID == "doc-1")
        #expect(
            await drive.calls == [
                .folderID(named: "Magenda"),
                .uploadPDF(
                    data: Data("pdf-2".utf8), name: "Magenda 2026-09-30 part 2.pdf",
                    folderID: "folder-1", replacing: nil),
                .createDoc(
                    name: "Magenda 2026-09-30 part 2 notes", folderID: "folder-1",
                    text: DocStatus.initialDocText),
                .exportText(docID: "doc-1"),
            ])
        let payload = try fired(0)
        #expect(payload["part"] as? Int == 2)
        #expect(payload["scope"] as? String == "meeting")
        #expect(controller.docURL(for: partID(2))?.absoluteString.contains("doc-1") == true)
        #expect(controller.docURL(for: partID(1)) == nil)
    }

    @Test("a part does not make the day finished, and a day can still be finished with parts")
    func partsDoNotBlockFinishing() async throws {
        try seed([partRecord(1, stage: .notesRequested, docID: "doc-p")])
        #expect(controller.hasHandoff(on: date))
        #expect(controller.canFinish(date))
        #expect(controller.docURL(for: dayID) == nil)
        await controller.finish(binder)
        #expect(controller.days.map(\.id) == [dayID, partID(1)])
        #expect(try saved().stage == .notesRequested)
        #expect(try #require(try store.handoff(partID(1))).docID == "doc-p")
        #expect(try store.pdf(for: partID(1)) == Data("pdf-1".utf8))
        #expect(!controller.canFinish(date))
    }

    @Test("approving a part's notes fires for the part only")
    func approvePart() async throws {
        var part = partRecord(1, stage: .notesRequested, docID: "doc-p")
        part.docStatus = .notesReady
        let closed = try #require(CalendarDay(year: 2026, month: 10, day: 1))
        try seed([closedDayRecord(on: closed), part])
        #expect(controller.days.last?.phase == .notesReady)
        await controller.perform(.approveNotes, on: dayID)
        #expect(trigger.texts.isEmpty)
        await drive.setExportedText("Status: Notes ready for review\n")
        await controller.perform(.approveNotes, on: partID(1))
        #expect(try fired(0)["step"] as? String == "close")
        #expect(try fired(0)["part"] as? Int == 1)
        let after = try #require(try store.handoff(partID(1)))
        #expect(after.stage == .closing)
        #expect(after.docStatus == .notesReady)
        #expect(try saved().stage == .closing)
        #expect(await drive.calls.last == .exportText(docID: "doc-p"))
    }

    @Test("a refresh reads a part's Doc and closes it")
    func refreshClosesPart() async throws {
        try seed([partRecord(1, stage: .closing, docID: "doc-p")])
        await drive.setExportedText("Status: Closed\n")
        await controller.refresh(excluding: otherDay)
        #expect(try store.handoff(partID(1))?.closedOn == clock.today)
        #expect(controller.days.first?.phase == .meetingClosed)
    }

    @Test("a queued part whose PDF is missing says so")
    func missingPartPDF() async throws {
        try seed([partRecord(1, stage: .queued)])
        try store.deletePDF(for: partID(1))
        await controller.refresh(excluding: otherDay)
        let part = try #require(try store.handoff(partID(1)))
        #expect(
            part.lastError
                == "This meeting's PDF is missing. Reset the hand-off and send it again.")
        #expect(part.stage == .queued)
        #expect(await drive.calls.isEmpty)
    }

    @Test("resetting removes the day's parts from the list and the store")
    func resetRemovesParts() async throws {
        await controller.finish(binder)
        try store.save(partRecord(1))
        try store.savePDF(Data("p".utf8), for: partID(1))
        controller.start()
        #expect(controller.days.map(\.id) == [dayID, partID(1)])
        controller.resetHandoff(for: date)
        #expect(controller.days.isEmpty)
        #expect(try store.handoffs().isEmpty)
        #expect(try store.pdf(for: partID(1)) == nil)
        #expect(!controller.hasHandoff(on: date))
        #expect(controller.canFinish(date))
    }

    @Test("a date with only parts can be reset")
    func resetOnlyParts() async throws {
        try seed([partRecord(1)])
        controller.resetHandoff(for: date)
        #expect(controller.days.isEmpty)
        #expect(try store.handoffs().isEmpty)
        #expect(controller.message == "This day can be finished again.")
    }

    // MARK: - Purge of parts

    @Test("the purge deletes a finished part's PDF and marks it purged before the day")
    func purgeFinishedPart() async throws {
        let closed = try #require(CalendarDay(year: 2026, month: 10, day: 1))
        let failing = FailingHandoffStore()
        let rig = try HandoffControllerTests(store: failing)
        try rig.binderStore.saveDay(rig.binder.day)
        for record in [rig.closedDayRecord(on: closed), rig.partRecord(1, closedOn: closed)] {
            try failing.save(record)
            try failing.savePDF(Data("x".utf8), for: record.id)
        }
        rig.controller.start()
        rig.clock.set(try #require(CalendarDay(year: 2026, month: 10, day: 6)))
        // The part is saved first; the day's save fails.
        failing.failSave(after: 1)
        await rig.controller.refresh(excluding: rig.otherDay)
        #expect(try failing.handoff(rig.partID(1))?.purged == true)
        #expect(try failing.pdf(for: rig.partID(1)) == nil)
        #expect(try failing.handoff(rig.dayID)?.purged == false)
        #expect(try rig.binderStore.day(rig.date) == nil)
        // The next refresh repeats the purge and finishes it.
        failing.failSave(after: 10)
        await rig.controller.refresh(excluding: rig.otherDay)
        #expect(try failing.handoff(rig.dayID)?.purged == true)
        #expect(try failing.pdf(for: rig.dayID) == nil)
        #expect(rig.controller.days.map(\.purged) == [true, true])
    }

    @Test("a part that is still uploaded keeps its PDF when the day is purged")
    func purgeKeepsWaitingPart() async throws {
        let closed = try #require(CalendarDay(year: 2026, month: 10, day: 1))
        try seed([
            closedDayRecord(on: closed), partRecord(1, closedOn: closed),
            partRecord(2, stage: .uploaded),
        ])
        clock.set(try #require(CalendarDay(year: 2026, month: 10, day: 6)))
        await controller.refresh(excluding: otherDay)
        #expect(try saved().purged)
        #expect(try store.pdf(for: dayID) == nil)
        #expect(try store.handoff(partID(1))?.purged == true)
        #expect(try store.pdf(for: partID(1)) == nil)
        #expect(try store.handoff(partID(2))?.purged == false)
        #expect(try store.pdf(for: partID(2)) == Data("pdf-2".utf8))
    }

    @Test("a closed day still waiting to upload keeps its PDF and is not marked purged")
    func purgeKeepsWaitingDay() async throws {
        let closed = try #require(CalendarDay(year: 2026, month: 10, day: 1))
        var day = closedDayRecord(on: closed)
        day.stage = .queued
        try seed([day])
        await drive.setError(GoogleAPIError.network, for: .folderID)
        clock.set(try #require(CalendarDay(year: 2026, month: 10, day: 6)))
        await controller.refresh(excluding: otherDay)
        #expect(try saved().stage == .queued)
        #expect(try saved().purged == false)
        #expect(try store.pdf(for: dayID) != nil)
    }

    @Test("a date with only parts is never purged, however long ago they closed")
    func partsAloneAreNotPurged() async throws {
        let closed = try #require(CalendarDay(year: 2026, month: 10, day: 1))
        try binderStore.saveDay(binder.day)
        try seed([partRecord(1, closedOn: closed)])
        clock.set(try #require(CalendarDay(year: 2026, month: 12, day: 1)))
        await controller.refresh(excluding: otherDay)
        #expect(try store.handoff(partID(1))?.purged == false)
        #expect(try store.pdf(for: partID(1)) == Data("pdf-1".utf8))
        #expect(try binderStore.day(date) != nil)
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

    // MARK: - Send a meeting

    private static let meetingA = PageKey.meeting("cal|a")
    private static let meetingB = PageKey.meeting("cal|b")

    /// A binder of this rig's date with meetings `cal|a` and `cal|b`, and an added copy of the
    /// first, which is `extra:id-1`.
    private func meetingBinder(routines: [SummaryRoutine] = []) -> BinderSession {
        let day = BinderDay(
            content: AgendaContent(
                date: date, todoItems: [],
                schedule: [
                    ScheduleEntry(slot: 2, text: "A", meetingIndex: 0),
                    ScheduleEntry(slot: 4, text: "B", meetingIndex: 1),
                ],
                meetings: ["A", "B"], meetingIDs: ["cal|a", "cal|b"], delegated: [],
                meetingSummaryRoutines: routines.isEmpty ? [] : [routines, []]),
            theme: Theme())
        let session = BinderSession(
            day: day, plan: layout.plan(for: day), ink: [:], store: binderStore, layout: layout,
            makeID: CountingIDs().next)
        _ = session.addPage(after: Self.meetingA)
        return session
    }

    private let copyKey = PageKey.extra("id-1")

    @Test("sending a meeting uploads its own PDF and Doc, fires a meeting run and locks its pages")
    func sendMeeting() async throws {
        let meeting = meetingBinder()
        meeting.setInk(Data("ink-a".utf8), on: Self.meetingA)
        meeting.setInk(Data("ink-b".utf8), on: Self.meetingB)
        #expect(controller.canSendMeeting(containing: Self.meetingA, of: meeting))
        await controller.sendMeeting(containing: Self.meetingA, of: meeting)
        #expect(renderer.fileNames == ["2026-09-30-part-1.pdf"])
        #expect(renderer.plans.first?.pages.map(\.key) == [Self.meetingA, copyKey])
        #expect(renderer.inks == [[Data("ink-a".utf8), nil]])
        #expect(removals.urls == [renderer.url])
        #expect(
            await drive.calls == [
                .folderID(named: "Magenda"),
                .uploadPDF(
                    data: Data("pdf".utf8), name: "Magenda 2026-09-30 part 1.pdf",
                    folderID: "folder-1", replacing: nil),
                .createDoc(
                    name: "Magenda 2026-09-30 part 1 notes", folderID: "folder-1",
                    text: DocStatus.initialDocText),
            ])
        let payload = try fired(0)
        #expect(payload["schema"] as? String == "magenda.end-of-day/3")
        #expect(payload["scope"] as? String == "meeting")
        #expect(payload["part"] as? Int == 1)
        #expect(payload["step"] as? String == "notes")
        #expect(meeting.isLocked(Self.meetingA))
        #expect(meeting.isLocked(copyKey))
        #expect(!meeting.isLocked(Self.meetingB))
        #expect(
            controller.message == "Sent to Claude. The notes appear in the meeting's Google Doc.")
        let part = try #require(try store.handoff(partID(1)))
        #expect(part.stage == .notesRequested)
        #expect(controller.days == [part])
        #expect(!controller.isBusy)
        #expect(controller.sentKeys(on: date) == [Self.meetingA, copyKey])
        #expect(controller.sentKeys(on: otherDay).isEmpty)
        #expect(
            controller.docURL(for: partID(1))?.absoluteString
                == "https://docs.google.com/document/d/doc-1/edit")
    }

    @Test("the day's record lists before its meetings after Finish Day")
    func dayListsBeforeParts() async throws {
        let meeting = meetingBinder()
        await controller.sendMeeting(containing: Self.meetingA, of: meeting)
        await controller.finish(meeting)
        #expect(controller.days.map(\.id) == [dayID, partID(1)])
    }

    @Test("a second meeting becomes part 2")
    func secondMeeting() async throws {
        let meeting = meetingBinder()
        await controller.sendMeeting(containing: Self.meetingA, of: meeting)
        await controller.sendMeeting(containing: Self.meetingB, of: meeting)
        #expect(controller.days.map(\.id) == [partID(1), partID(2)])
        #expect(try fired(1)["part"] as? Int == 2)
        #expect(controller.sentKeys(on: date) == [Self.meetingA, copyKey, Self.meetingB])
    }

    @Test("a meeting can be sent from its page or from a copy of it, not from other pages")
    func canSendMeeting() async throws {
        let meeting = meetingBinder()
        #expect(!controller.canSendMeeting(containing: .overview, of: meeting))
        #expect(controller.canSendMeeting(containing: Self.meetingA, of: meeting))
        #expect(controller.canSendMeeting(containing: copyKey, of: meeting))
        await controller.sendMeeting(containing: .overview, of: meeting)
        #expect(controller.message == nil)
        #expect(controller.days.isEmpty)
        await controller.sendMeeting(containing: copyKey, of: meeting)
        #expect(!controller.canSendMeeting(containing: Self.meetingA, of: meeting))
        #expect(controller.canSendMeeting(containing: Self.meetingB, of: meeting))
        await controller.finish(meeting)
        #expect(!controller.canSendMeeting(containing: Self.meetingB, of: meeting))
    }

    @Test("a meeting is not sent after the day, or twice")
    func refusals() async throws {
        let meeting = meetingBinder()
        await controller.finish(meeting)
        await controller.sendMeeting(containing: Self.meetingA, of: meeting)
        #expect(controller.message == "This day was already finished, so its meetings go with it.")
        #expect(trigger.texts.count == 1)
        controller.resetHandoff(for: date)
        await controller.sendMeeting(containing: Self.meetingA, of: meeting)
        await controller.sendMeeting(containing: Self.meetingA, of: meeting)
        #expect(controller.message == "This meeting was already sent to Claude.")
        #expect(trigger.texts.count == 2)
    }

    @Test("sending is skipped while another hand-off is running")
    func sendMeetingBusy() async throws {
        let rig = try HandoffControllerTests(drive: FakeDrive(holdingUpload: true))
        let meeting = rig.meetingBinder()
        let first = Task {
            await rig.controller.sendMeeting(containing: Self.meetingA, of: meeting)
        }
        await rig.drive.waitUntilBlocked()
        await rig.controller.sendMeeting(containing: Self.meetingB, of: meeting)
        #expect(!meeting.isLocked(Self.meetingB))
        await rig.drive.release()
        await first.value
        #expect(rig.controller.days.count == 1)
    }

    @Test("a render failure sets its message, stores nothing and unlocks the pages")
    func sendMeetingRenderFails() async throws {
        let rig = try HandoffControllerTests(renderer: FakeRenderer(fails: true))
        let meeting = rig.meetingBinder()
        await rig.controller.sendMeeting(containing: Self.meetingA, of: meeting)
        #expect(rig.controller.message == "Couldn't create the PDF. Try again.")
        #expect(rig.controller.days.isEmpty)
        #expect(try rig.store.handoffs().isEmpty)
        #expect(!meeting.isLocked(Self.meetingA))
        #expect(!meeting.isLocked(rig.copyKey))
    }

    @Test("a save failure sets its message, stores no record and unlocks the pages")
    func sendMeetingSaveFails() async throws {
        let rig = try HandoffControllerTests(store: FailingHandoffStore(failing: [.savePDF]))
        let meeting = rig.meetingBinder()
        await rig.controller.sendMeeting(containing: Self.meetingA, of: meeting)
        #expect(
            rig.controller.message
                == "Couldn't save the meeting. Free some space on this device and try again.")
        #expect(rig.controller.days.isEmpty)
        #expect(try rig.store.handoffs().isEmpty)
        #expect(!meeting.isLocked(Self.meetingA))
        #expect(trigger.texts.isEmpty)
    }

    @Test("a fire failure keeps the part and the lock, and Try again sends it")
    func sendMeetingFireFails() async throws {
        let meeting = meetingBinder()
        trigger.setError(RoutineTriggerError.network)
        await controller.sendMeeting(containing: Self.meetingA, of: meeting)
        let part = try #require(controller.days.first)
        #expect(part.stage == .uploaded)
        #expect(part.lastError != nil)
        #expect(controller.message == part.lastError)
        #expect(meeting.isLocked(Self.meetingA))
        trigger.setError(nil)
        await controller.perform(.retry, on: part.id)
        #expect(try #require(try store.handoff(part.id)).stage == .notesRequested)
        #expect(try fired(1)["part"] as? Int == 1)
        #expect(await uploads().count == 1)
    }

    @Test("Finish Day marks the pages of a sent meeting and reuses only the day's Drive IDs")
    func finishAfterMeeting() async throws {
        let meeting = meetingBinder()
        await controller.sendMeeting(containing: Self.meetingA, of: meeting)
        var queued = DayHandoff(
            date: date, checksum: "sha256:" + String(repeating: "ab", count: 32),
            pages: [], tasks: [], delegated: [])
        queued.stage = .uploaded
        queued.driveFileID = "day-file"
        queued.docID = "day-doc"
        try store.save(queued)
        controller.start()
        await controller.finish(meeting)
        let payload = try fired(1)
        #expect(payload["scope"] as? String == "day")
        // The day replaces its own file and keeps its own Doc; the part's IDs are never used.
        let uploaded = await uploads()
        #expect(uploaded.count == 2)
        guard case .uploadPDF(_, "Magenda 2026-09-30.pdf", _, let replacing)? = uploaded.last
        else {
            Issue.record("the day's PDF was not uploaded")
            return
        }
        #expect(replacing == "day-file")
        #expect(payload["docID"] as? String == "day-doc")
        let pages = try #require(payload["pages"] as? [[String: Any]])
        let marked = pages.compactMap { page in
            (page["earlierPart"] as? Int).map { (page["key"] as? String ?? "", $0) }
        }
        #expect(marked.map(\.0) == ["meeting:cal|a", "extra:id-1"])
        #expect(marked.map(\.1) == [1, 1])
        #expect(pages.filter { $0["earlierPart"] == nil }.count == pages.count - 2)
    }

    @Test("approving a part's notes fires for the part only")
    func approveSentMeeting() async throws {
        let meeting = meetingBinder()
        await controller.sendMeeting(containing: Self.meetingA, of: meeting)
        await drive.setExportedText(DocStatus.initialDocText)
        var part = try #require(try store.handoff(partID(1)))
        part.docStatus = .notesReady
        try store.save(part)
        controller.start()
        await controller.perform(.approveNotes, on: partID(1))
        let payload = try fired(1)
        #expect(payload["step"] as? String == "close")
        #expect(payload["part"] as? Int == 1)
        #expect(try store.handoff(dayID) == nil)
        #expect(controller.days.map(\.id) == [partID(1)])
    }

    @Test("resetting unlocks the binder and makes the meeting sendable again")
    func resetUnlocks() async throws {
        let meeting = meetingBinder()
        await controller.sendMeeting(containing: Self.meetingA, of: meeting)
        await controller.finish(meeting)
        controller.resetHandoff(for: date, unlocking: meeting)
        #expect(controller.days.isEmpty)
        #expect(try store.handoffs().isEmpty)
        #expect(!meeting.isLocked(Self.meetingA))
        #expect(controller.canSendMeeting(containing: Self.meetingA, of: meeting))
        #expect(controller.message == "This day can be finished again.")
    }

    @Test("resetting without a binder, or for another date's binder, leaves the pages locked")
    func resetWithoutBinder() async throws {
        let meeting = meetingBinder()
        await controller.sendMeeting(containing: Self.meetingA, of: meeting)
        controller.resetHandoff(for: date)
        #expect(controller.days.isEmpty)
        #expect(meeting.isLocked(Self.meetingA))
        meeting.lock([Self.meetingB])
        controller.resetHandoff(for: otherDay, unlocking: meeting)
        #expect(meeting.isLocked(Self.meetingB))
    }

    @Test("with no record but locked pages, resetting only unlocks them")
    func resetStuckLock() async throws {
        let meeting = meetingBinder()
        meeting.lock([Self.meetingA])
        controller.resetHandoff(for: date, unlocking: meeting)
        #expect(!meeting.isLocked(Self.meetingA))
        #expect(controller.message == "This day can be finished again.")
        controller.resetHandoff(for: date, unlocking: meeting)
        #expect(controller.days.isEmpty)
    }

    @Test("a failing delete keeps the pages locked")
    func resetDeleteFails() async throws {
        let rig = try HandoffControllerTests(store: FailingHandoffStore(failing: [.deleteHandoff]))
        let meeting = rig.meetingBinder()
        await rig.controller.sendMeeting(containing: Self.meetingA, of: meeting)
        rig.controller.resetHandoff(for: rig.date, unlocking: meeting)
        #expect(rig.controller.message == "Couldn't reset this day. Try again.")
        #expect(meeting.isLocked(Self.meetingA))
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
