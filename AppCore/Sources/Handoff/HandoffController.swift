import Foundation
import Observation

/// Finishes days: uploads each one's PDF to Google Drive, creates its Doc, starts the end-of-day
/// routine, and follows the day through the review loop until it is closed and purged.
@MainActor @Observable
public final class HandoffController {
    /// The finished days, newest first, as last read from the store.
    public private(set) var days: [DayHandoff] = []
    /// The last notice for the binder or the Review list.
    public private(set) var message: String?
    /// Whether a finish, refresh or action is running; another one returns at once meanwhile.
    public private(set) var isBusy = false
    /// The trigger ID of the stored routine, or nil when none is stored.
    public private(set) var routineTriggerID: String?

    @ObservationIgnored private let store: any HandoffStore
    @ObservationIgnored private let binderStore: any BinderStore
    @ObservationIgnored private let drive: any DriveFiling
    @ObservationIgnored private let trigger: any RoutineFiring
    @ObservationIgnored private let routineCredentials: any RoutineCredentialsStore
    @ObservationIgnored private let renderer: any AgendaRendering
    @ObservationIgnored private let hasher: any SHA256Hashing
    @ObservationIgnored private let today: @Sendable () -> CalendarDay
    @ObservationIgnored private let readFile: @Sendable (URL) throws -> Data
    @ObservationIgnored private let removeFile: @Sendable (URL) -> Void

    /// How many days after Magenda first reads a closed Doc the day's files are deleted.
    private static let purgeDelay = 5
    private static let folderName = "Magenda"

    /// Creates a controller. `readFile` and `removeFile` read and delete the rendered PDF.
    public init(
        store: any HandoffStore, binderStore: any BinderStore, drive: any DriveFiling,
        trigger: any RoutineFiring, routineCredentials: any RoutineCredentialsStore,
        renderer: any AgendaRendering, hasher: any SHA256Hashing,
        today: @escaping @Sendable () -> CalendarDay,
        readFile: @escaping @Sendable (URL) throws -> Data,
        removeFile: @escaping @Sendable (URL) -> Void
    ) {
        self.store = store
        self.binderStore = binderStore
        self.drive = drive
        self.trigger = trigger
        self.routineCredentials = routineCredentials
        self.renderer = renderer
        self.hasher = hasher
        self.today = today
        self.readFile = readFile
        self.removeFile = removeFile
    }

    /// Loads the finished days and the stored routine.
    public func start() {
        do {
            days = try store.handoffs()
        } catch {
            days = []
            message = "Couldn't read the finished days on this device."
        }
        routineTriggerID = (try? routineCredentials.load())?.triggerID
    }

    /// Whether `date` can be finished: it has no hand-off, or none beyond the upload.
    public func canFinish(_ date: CalendarDay) -> Bool {
        guard let handoff = stored(on: date) else { return true }
        return handoff.stage == .queued || handoff.stage == .uploaded
    }

    /// The link to the day's Google Doc, or nil when it has none.
    public func docURL(for date: CalendarDay) -> URL? {
        stored(on: date)?.docID.map {
            GoogleAPI.url(host: "docs.google.com", path: "/document/d/\($0)/edit")
        }
    }

    /// Renders the open binder to a PDF, queues it, and uploads and sends it when it can.
    public func finish(_ binder: BinderSession) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let date = binder.date
        guard canFinish(date) else {
            message = "This day was already sent to Claude."
            return
        }
        let pdf: Data
        do {
            pdf = try await renderedPDF(of: binder)
        } catch {
            message = "Couldn't create the PDF. Try again."
            return
        }
        let digest = hasher.sha256(pdf).map { String(format: "%02x", $0) }.joined()
        var handoff = DayHandoff(
            date: date, checksum: "sha256:" + digest, day: binder.day, plan: binder.plan)
        let earlier = stored(on: date)
        handoff.driveFileID = earlier?.driveFileID
        handoff.docID = earlier?.docID
        do {
            try store.savePDF(pdf, for: date)
            try store.save(handoff)
        } catch {
            message =
                "Couldn't save the finished day. Free some space on this device and try again."
            return
        }
        remember(handoff)
        await runPipeline(on: date)
        let result = stored(on: date)
        message =
            result?.stage == .notesRequested
            ? "Sent to Claude. The notes appear in the day's Google Doc." : result?.lastError
    }

    /// Uploads and sends the days still waiting, reads each Doc's status, and deletes the files
    /// of days closed long enough ago. The day `openDay` is open in the binder and is kept.
    public func refresh(excluding openDay: CalendarDay) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        for date in days.filter({ $0.stage == .queued }).map(\.date) {
            await runPipeline(on: date)
        }
        for handoff in days where handoff.docID != nil && handoff.closedOn == nil {
            await readStatus(of: handoff.date)
        }
        let now = today()
        for handoff in days where !handoff.purged && handoff.date != openDay {
            if let closedOn = handoff.closedOn, closedOn.adding(days: Self.purgeDelay) <= now {
                // A failure leaves the day for the next refresh.
                try? purge(handoff)
            }
        }
        if let loaded = try? store.handoffs() { days = loaded }
    }

    /// Does what the Review list offers for `date`: sends it again, or approves the next step.
    public func perform(_ action: HandoffAction, on date: CalendarDay) async {
        guard !isBusy, let handoff = stored(on: date), handoff.phase.action == action else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        switch action {
        case .retry:
            await runPipeline(on: date)
        case .approve(let step):
            await approve(step, on: handoff)
        }
    }

    /// Stores the routine's fire URL and token; returns false and sets `message` when they are
    /// not valid or cannot be stored.
    public func saveRoutine(fireURL: String, token: String) -> Bool {
        // The URL is checked alone with a token of the right shape, so a wrong token is not
        // reported as a wrong URL.
        guard RoutineCredentials(fireURL: fireURL, token: "sk-ant-oat01-x") != nil else {
            message =
                "That isn't a routine fire URL. Copy it from the routine's API trigger at claude.ai/code/routines; it ends in /fire."
            return false
        }
        guard let credentials = RoutineCredentials(fireURL: fireURL, token: token) else {
            message = "That isn't a routine token. It starts with sk-ant-oat01-."
            return false
        }
        do {
            try routineCredentials.save(credentials)
        } catch {
            message = "Couldn't save the routine in the Keychain. Try again."
            return false
        }
        routineTriggerID = credentials.triggerID
        message = nil
        return true
    }

    /// Deletes the stored routine.
    public func forgetRoutine() {
        if (try? routineCredentials.delete()) != nil { routineTriggerID = nil }
    }

    // MARK: - Steps

    private func stored(on date: CalendarDay) -> DayHandoff? {
        days.first { $0.date == date }
    }

    /// Keeps `handoff` in `days`, in its place by date, newest first.
    private func remember(_ handoff: DayHandoff) {
        days.removeAll { $0.date == handoff.date }
        days.insert(handoff, at: days.firstIndex { $0.date < handoff.date } ?? days.endIndex)
    }

    private func save(_ handoff: DayHandoff) throws {
        try store.save(handoff)
        remember(handoff)
    }

    /// Writes the binder's pages with their handwriting to a file named for the finished day (not
    /// the preview's), reads it and deletes it.
    private func renderedPDF(of binder: BinderSession) async throws -> Data {
        let url = try await renderer.render(
            binder.plan, ink: binder.plan.pages.map { binder.ink[$0.key] },
            fileName: "\(binder.date.isoString)-finished.pdf")
        defer { removeFile(url) }
        return try readFile(url)
    }

    /// Uploads a queued day and sends it to the routine; stops at the first error and records it.
    private func runPipeline(on date: CalendarDay) async {
        guard var handoff = stored(on: date) else { return }
        do {
            if handoff.stage == .queued {
                guard let pdf = try store.pdf(for: date) else {
                    handoff.lastError = "This day's PDF is missing. Finish the day again."
                    try save(handoff)
                    return
                }
                let folderID = try await drive.folderID(named: Self.folderName)
                handoff.driveFileID = try await drive.uploadPDF(
                    pdf, name: "Magenda \(date.isoString).pdf", folderID: folderID,
                    replacing: handoff.driveFileID)
                try save(handoff)
                if handoff.docID == nil {
                    handoff.docID = try await drive.createDoc(
                        name: "Magenda \(date.isoString) notes", folderID: folderID,
                        text: DocStatus.initialDocText)
                    try save(handoff)
                }
                handoff.stage = .uploaded
                try save(handoff)
            }
            if handoff.stage == .uploaded {
                handoff.sessionURL = try await trigger.fire(text: handoff.payload(step: .notes))
                handoff.stage = .notesRequested
                handoff.lastError = nil
                try save(handoff)
            }
        } catch {
            fail(&handoff, with: error)
        }
    }

    /// Fires `step`, then reads the Doc so the row shows the result at once.
    private func approve(_ step: RoutineStep, on current: DayHandoff) async {
        var handoff = current
        do {
            handoff.sessionURL = try await trigger.fire(text: handoff.payload(step: step))
            handoff.stage = step == .approveNotes ? .notesApproved : .summaryApproved
            handoff.lastError = nil
            try save(handoff)
        } catch {
            fail(&handoff, with: error)
            return
        }
        await readStatus(of: handoff.date)
    }

    /// Reads the status line of the day's Doc; the first time it is closed, notes today.
    private func readStatus(of date: CalendarDay) async {
        guard var handoff = stored(on: date), let docID = handoff.docID else { return }
        do {
            let status = DocStatus.parse(try await drive.exportText(ofDoc: docID))
            handoff.docStatus = status
            handoff.lastError = nil
            if status == .closed { handoff.closedOn = today() }
            try save(handoff)
        } catch {
            fail(&handoff, with: error)
        }
    }

    /// Deletes the binder day and the PDF, and keeps the record marked purged.
    private func purge(_ handoff: DayHandoff) throws {
        try binderStore.deleteDay(handoff.date)
        try store.deletePDF(for: handoff.date)
        var purged = handoff
        purged.purged = true
        try save(purged)
    }

    /// Records `error` on `handoff` and saves it; a save that fails too only updates `days`.
    private func fail(_ handoff: inout DayHandoff, with error: any Error) {
        handoff.lastError = Self.userMessage(for: error)
        remember(handoff)
        try? store.save(handoff)
    }

    private static func userMessage(for error: any Error) -> String {
        if let error = error as? GoogleAPIError { return error.userMessage }
        if let error = error as? RoutineTriggerError { return error.userMessage }
        if error is HandoffStoreError {
            return "Couldn't save the finished day. Free some space on this device and try again."
        }
        return "Something went wrong. Try again."
    }
}
