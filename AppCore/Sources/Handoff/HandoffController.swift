import Foundation
import Observation

/// Finishes days: uploads each one's PDF to Google Drive, creates its Doc, starts the end-of-day
/// routine, and follows the day through the review loop until it is closed and purged.
@MainActor @Observable
public final class HandoffController {
    /// The finished days and the meetings sent before them, in `HandoffID.listOrder`, as last read
    /// from the store.
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

    /// Whether `date` can be finished: its day has no hand-off, or none beyond the upload. Meetings
    /// sent early do not count.
    public func canFinish(_ date: CalendarDay) -> Bool {
        guard let handoff = stored(Self.dayID(date)) else { return true }
        return handoff.stage == .queued || handoff.stage == .uploaded
    }

    /// Whether `date` has a hand-off, of the day or of a meeting, that `resetHandoff(for:)` can
    /// forget.
    public func hasHandoff(on date: CalendarDay) -> Bool {
        days.contains { $0.date == date }
    }

    /// The link to the Google Doc of `id`, or nil when it has none.
    public func docURL(for id: HandoffID) -> URL? {
        stored(id)?.docID.map {
            GoogleAPI.url(host: "docs.google.com", path: "/document/d").appending(path: $0)
                .appending(path: "edit")
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
        let earlier = stored(Self.dayID(date))
        handoff.driveFileID = earlier?.driveFileID
        handoff.docID = earlier?.docID
        do {
            try store.savePDF(pdf, for: Self.dayID(date))
            try store.save(handoff)
        } catch {
            message =
                "Couldn't save the finished day. Free some space on this device and try again."
            return
        }
        remember(handoff)
        await runPipeline(handoff)
        let result = stored(Self.dayID(date))
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
        for handoff in days where handoff.stage == .queued {
            await runPipeline(handoff)
        }
        for handoff in days where handoff.closedOn == nil {
            if let docID = handoff.docID { await readStatus(handoff, docID: docID) }
        }
        let now = today()
        // Only a day starts a purge; its meetings' handwriting goes with the day's.
        for handoff in days where handoff.part == nil {
            if !handoff.purged, handoff.date != openDay, let closedOn = handoff.closedOn,
                closedOn.adding(days: DayHandoff.purgeDelayDays) <= now
            {
                // A failure leaves the day for the next refresh.
                try? purge(handoff)
            }
        }
        if let loaded = try? store.handoffs() { days = loaded }
    }

    /// Does what the Review list offers for `id`: sends it again, or approves the next step.
    public func perform(_ action: HandoffAction, on id: HandoffID) async {
        guard !isBusy, let handoff = stored(id), handoff.phase.action == action else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        switch action {
        case .retry:
            await runPipeline(handoff)
        case .approve(let step):
            await approve(step, on: handoff)
        }
    }

    /// Forgets the hand-offs of `date`, the day's and its meetings', and deletes their stored PDFs,
    /// so the day can be finished again as if it had never been sent. What is already in Drive
    /// stays, and finishing again creates a new Doc.
    public func resetHandoff(for date: CalendarDay) {
        guard !isBusy, hasHandoff(on: date) else { return }
        do {
            try store.deleteHandoff(for: date)
        } catch {
            message = "Couldn't reset this day. Try again."
            return
        }
        days.removeAll { $0.date == date }
        message = "This day can be finished again."
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

    private static func dayID(_ date: CalendarDay) -> HandoffID {
        HandoffID(date: date, part: nil)
    }

    private func stored(_ id: HandoffID) -> DayHandoff? {
        days.first { $0.id == id }
    }

    /// Keeps `handoff` in `days`, in its place in `HandoffID.listOrder`, replacing the record with
    /// the same ID.
    private func remember(_ handoff: DayHandoff) {
        days.removeAll { $0.id == handoff.id }
        days.insert(
            handoff,
            at: days.firstIndex { HandoffID.listOrder(handoff.id, $0.id) } ?? days.endIndex)
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

    /// Uploads a queued record and sends it to the routine; stops at the first error, recording it.
    private func runPipeline(_ start: DayHandoff) async {
        var handoff = start
        do {
            if handoff.stage == .queued {
                guard let pdf = try store.pdf(for: handoff.id) else {
                    handoff.lastError =
                        handoff.part == nil
                        ? "This day's PDF is missing. Finish the day again."
                        : "This meeting's PDF is missing. Reset the hand-off and send it again."
                    try save(handoff)
                    return
                }
                let folderID = try await drive.folderID(named: Self.folderName)
                handoff.driveFileID = try await drive.uploadPDF(
                    pdf, name: handoff.pdfName, folderID: folderID,
                    replacing: handoff.driveFileID)
                try save(handoff)
                if handoff.docID == nil {
                    handoff.docID = try await drive.createDoc(
                        name: handoff.docName, folderID: folderID,
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
        if let docID = handoff.docID { await readStatus(handoff, docID: docID) }
    }

    /// Reads the status line of the day's Doc; the first time it is closed, notes today.
    private func readStatus(_ start: DayHandoff, docID: String) async {
        var handoff = start
        do {
            let status = DocStatus.parse(try await drive.exportText(ofDoc: docID))
            handoff.docStatus = status
            // A day that is not yet sent keeps the error that stopped it; reading its Doc
            // does not undo that.
            if handoff.stage != .queued && handoff.stage != .uploaded { handoff.lastError = nil }
            if status == .closed { handoff.closedOn = today() }
            try save(handoff)
        } catch {
            fail(&handoff, with: error)
        }
    }

    /// Deletes the binder day and the PDFs of the day and of its meetings, and keeps the records
    /// marked purged, the meetings' before the day's, so a failure partway leaves the day unpurged
    /// and the next refresh repeats it. A record still waiting to upload keeps its PDF.
    private func purge(_ day: DayHandoff) throws {
        try binderStore.deleteDay(day.date)
        let parts = days.filter { $0.date == day.date && $0.part != nil }
        for record in parts + [day] where record.stage != .queued && record.stage != .uploaded {
            try store.deletePDF(for: record.id)
            var purged = record
            purged.purged = true
            try save(purged)
        }
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
