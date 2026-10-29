import Foundation

/// How far a finished day has come.
public enum HandoffStage: String, Codable, Sendable {
    case queued, uploaded, notesRequested
    /// Approve notes was tapped and some summary routine has not been started.
    case summariesPending
    case summariesRequested, closing

    /// Decodes the raw stage. `notesApproved` and `summaryApproved`, which an earlier build wrote
    /// once it had started the end-of-day routine's closing steps, read as `.closing`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "notesApproved", "summaryApproved": self = .closing
        default:
            guard let stage = HandoffStage(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unknown hand-off stage \(raw).")
            }
            self = stage
        }
    }
}

/// One page of the PDF, for the routine.
public struct HandoffPage: Equatable, Codable, Sendable {
    /// The 1-based position in the PDF.
    public let page: Int
    /// `PageKey.storageString`.
    public let key: String
    /// Meeting pages: the part of the event key before the first "|".
    public let calendarID: String?
    /// Meeting pages: the part of the event key after the first "|".
    public let eventID: String?
    /// Meeting pages: the meeting-page title.
    public let title: String?
    /// Meeting pages that ask for summaries: the summary routines; nil when none.
    public let summaryRoutines: [SummaryRoutine]?
    /// Added pages: the `storageString` of the page they copy.
    public let source: String?
    /// Day runs: the part that already sent this page; the routine must not process it again.
    public let earlierPart: Int?

    /// Creates a page entry.
    public init(
        page: Int, key: String, calendarID: String? = nil, eventID: String? = nil,
        title: String? = nil, summaryRoutines: [SummaryRoutine]? = nil, source: String? = nil,
        earlierPart: Int? = nil
    ) {
        self.page = page
        self.key = key
        self.calendarID = calendarID
        self.eventID = eventID
        self.title = title
        self.summaryRoutines = summaryRoutines
        self.source = source
        self.earlierPart = earlierPart
    }

    /// The same page without the fields that only describe it; `earlierPart` stays, because a
    /// routine that loses it would process the page twice.
    fileprivate var bare: HandoffPage {
        HandoffPage(
            page: page, key: key, calendarID: calendarID, eventID: eventID,
            earlierPart: earlierPart)
    }

    /// The same page, marked as already sent as part `number`.
    fileprivate func sent(inPart number: Int) -> HandoffPage {
        HandoffPage(
            page: page, key: key, calendarID: calendarID, eventID: eventID, title: title,
            summaryRoutines: summaryRoutines, source: source, earlierPart: number)
    }
}

/// A printed to-do row, for the routine.
public struct HandoffTask: Equatable, Codable, Sendable {
    /// The ID of the task the row came from, if it came from one.
    public let taskID: String?
    /// The task title.
    public let text: String
    /// The due date as `MM/DD`, or empty.
    public let due: String

    /// Creates a task entry.
    public init(taskID: String?, text: String, due: String) {
        self.taskID = taskID
        self.text = text
        self.due = due
    }
}

/// A delegated row, for the routine.
public struct HandoffDelegated: Equatable, Codable, Sendable {
    /// The ID of the task the row came from, if it came from one.
    public let taskID: String?
    /// The task.
    public let text: String
    /// Who owns it.
    public let owner: String

    /// Creates a delegated entry.
    public init(taskID: String?, text: String, owner: String) {
        self.taskID = taskID
        self.text = text
        self.owner = owner
    }
}

/// Which hand-off a record is: a finished day, or a meeting sent before the day ended.
public struct HandoffID: Hashable, Sendable {
    /// The day.
    public let date: CalendarDay
    /// nil for the finished day; the part's number for a meeting sent early.
    public let part: Int?

    /// Creates an ID.
    public init(date: CalendarDay, part: Int?) {
        self.date = date
        self.part = part
    }

    /// The Review list's order: newest date first; on one date the day before its parts, and
    /// parts by number.
    public static func listOrder(_ lhs: HandoffID, _ rhs: HandoffID) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return (lhs.part ?? 0) < (rhs.part ?? 0)
    }
}

/// A meeting sent to the routine before the day ended.
public struct HandoffPart: Equatable, Codable, Sendable {
    /// 1, 2, … in the order the day's meetings were sent.
    public let number: Int
    /// `PageKey.storageString` of the meeting page.
    public let meetingKey: String
    /// The meeting-page title, when known.
    public let title: String?

    /// Creates a part.
    public init(number: Int, meetingKey: String, title: String?) {
        self.number = number
        self.meetingKey = meetingKey
        self.title = title
    }
}

/// What the Review list can do with a day.
public enum HandoffAction: Equatable, Sendable {
    case retry, approveNotes, approveSummaries
}

/// What the Review list shows for a day.
public enum HandoffPhase: Equatable, Sendable {
    case closed(deleteOn: CalendarDay, purged: Bool)
    case waitingToUpload
    case waitingToSend
    case notesReady
    case writingNotes
    case summariesWaitingToSend
    case writingSummaries
    case summaryReady
    case closing
    case meetingClosed

    /// The status line of the day's row.
    public var title: String {
        switch self {
        case .closed(_, true): "Closed. Handwriting deleted."
        case .closed(let deleteOn, false):
            "Closed. Handwriting is deleted on \(deleteOn.isoString)."
        case .waitingToUpload: "Waiting to upload"
        case .waitingToSend: "Uploaded, not yet sent to Claude"
        case .notesReady: "Notes ready for review"
        case .writingNotes: "Claude is writing the notes"
        case .summariesWaitingToSend: "Notes approved. Summaries not yet sent to Claude"
        case .writingSummaries: "Claude is writing the summaries"
        case .summaryReady: "Summaries ready for review"
        case .closing: "Claude is closing the day"
        case .meetingClosed: "Closed"
        }
    }

    /// The button the row offers, if any.
    public var action: HandoffAction? {
        switch self {
        case .waitingToUpload, .waitingToSend, .summariesWaitingToSend: .retry
        case .notesReady: .approveNotes
        case .summaryReady: .approveSummaries
        case .closed, .meetingClosed, .writingNotes, .writingSummaries, .closing: nil
        }
    }
}

/// A finished day and how far its hand-off has come.
public struct DayHandoff: Equatable, Codable, Sendable {
    /// The version of the saved format; a hand-off saved with another version cannot be decoded.
    public static let formatVersion = 1

    /// The longest payload the routine accepts, in characters.
    static let maxPayloadLength = 65_536

    /// How many days after Magenda first reads a closed Doc the day's files are deleted.
    public static let purgeDelayDays = 5

    /// The format version; always `formatVersion` when created.
    public let version: Int
    /// The day.
    public let date: CalendarDay
    /// `sha256:` and the 64 lowercase hex digits of the PDF.
    public var checksum: String
    /// The pages of the PDF.
    public var pages: [HandoffPage]
    /// The printed to-do rows, in order.
    public var tasks: [HandoffTask]
    /// The delegated rows, in page order.
    public var delegated: [HandoffDelegated]
    /// The uploaded PDF's Drive file.
    public var driveFileID: String?
    /// The day's Google Doc.
    public var docID: String?
    /// The Drive folder holding the PDF and the Doc; set by the first upload.
    public var folderID: String?
    /// How far the hand-off has come.
    public var stage: HandoffStage
    /// The Doc's status as last read; `.waitingForNotes` until read.
    public var docStatus: DocStatus
    /// The day Magenda first read `.closed`.
    public var closedOn: CalendarDay?
    /// Whether the binder day and the PDF were deleted; this record stays.
    public var purged: Bool
    /// The last failure, as a message for the person.
    public var lastError: String?
    /// The last routine run started.
    public var sessionURL: URL?
    /// nil for the finished day; the meeting this record covers when it was sent early.
    public let part: HandoffPart?
    /// The IDs of the summary routines already started for this record.
    public var firedSummaries: [String]
    /// The summary markers read from the Doc, each `"<routine ID> <page>"`.
    public var summaryMarkers: [String]

    private enum CodingKeys: String, CodingKey {
        case version, date, checksum, pages, tasks, delegated, driveFileID, docID, folderID, stage
        case docStatus
        case closedOn, purged, lastError, sessionURL, part, firedSummaries, summaryMarkers
    }

    /// Which hand-off this is.
    public var id: HandoffID { HandoffID(date: date, part: part?.number) }

    /// The pages this record sent.
    public var pageKeys: Set<PageKey> {
        Set(pages.compactMap { PageKey(storageString: $0.key) })
    }

    /// The headline of the record's Review row.
    public var displayTitle: String {
        guard let part else { return date.isoString }
        return "\(date.isoString) · \(part.title ?? "Meeting")"
    }

    /// The PDF's name in Drive.
    public var pdfName: String {
        guard let part else { return "Magenda \(date.isoString).pdf" }
        return "Magenda \(date.isoString) part \(part.number).pdf"
    }

    /// The Google Doc's name in Drive.
    public var docName: String {
        guard let part else { return "Magenda \(date.isoString) notes" }
        return "Magenda \(date.isoString) part \(part.number) notes"
    }

    /// Creates a queued hand-off of `date` with nothing uploaded.
    public init(
        date: CalendarDay, checksum: String, pages: [HandoffPage], tasks: [HandoffTask],
        delegated: [HandoffDelegated], part: HandoffPart? = nil
    ) {
        version = Self.formatVersion
        self.date = date
        self.checksum = checksum
        self.pages = pages
        self.tasks = tasks
        self.delegated = delegated
        stage = .queued
        docStatus = .waitingForNotes
        purged = false
        self.part = part
        firedSummaries = []
        summaryMarkers = []
    }

    /// Creates a queued hand-off from the PDF's `checksum`, the binder `day` and its `plan`. A
    /// page whose key is in `earlierParts` was already sent in that part. A summary routine's own
    /// page asks for that routine only when it, or a page added as its copy, is in `inkedKeys`.
    public init(
        date: CalendarDay, checksum: String, day: BinderDay, plan: RenderPlan,
        earlierParts: [PageKey: Int] = [:], inkedKeys: Set<PageKey> = []
    ) {
        let pages = plan.pages.enumerated().map { index, page in
            let entry = Self.handoffPage(
                number: index + 1, page: page, in: day, inkedKeys: inkedKeys)
            return earlierParts[page.key].map(entry.sent(inPart:)) ?? entry
        }
        var printed = day.content.todoItems
        for omitted in plan.omittedTodoItems {
            if let index = printed.lastIndex(where: {
                $0.text == omitted.text && $0.due == omitted.due
            }) {
                printed.remove(at: index)
            }
        }
        self.init(
            date: date, checksum: checksum, pages: pages,
            tasks: printed.map { HandoffTask(taskID: $0.taskID, text: $0.text, due: $0.due) },
            delegated: day.content.delegated.sortedForPage().map {
                HandoffDelegated(taskID: $0.taskID, text: $0.text, owner: $0.owner)
            })
    }

    /// Creates a queued hand-off of the meeting page `meeting`, part `number` of `date`, from the
    /// meeting PDF's `checksum`, the binder `day` and the `plan` of the meeting's pages.
    public init(
        date: CalendarDay, part number: Int, meeting: PageKey, checksum: String, day: BinderDay,
        plan: RenderPlan
    ) {
        let pages = plan.pages.enumerated().map { index, page in
            Self.handoffPage(number: index + 1, page: page, in: day)
        }
        self.init(
            date: date, checksum: checksum, pages: pages, tasks: [], delegated: [],
            part: HandoffPart(
                number: number, meetingKey: meeting.storageString,
                title: pages.first { $0.key == meeting.storageString }?.title))
    }

    /// Decodes a hand-off; throws when it was saved with another format version.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.formatVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container,
                debugDescription: "Unsupported hand-off version \(version).")
        }
        self.version = version
        date = try container.decode(CalendarDay.self, forKey: .date)
        checksum = try container.decode(String.self, forKey: .checksum)
        pages = try container.decode([HandoffPage].self, forKey: .pages)
        tasks = try container.decode([HandoffTask].self, forKey: .tasks)
        delegated = try container.decode([HandoffDelegated].self, forKey: .delegated)
        driveFileID = try container.decodeIfPresent(String.self, forKey: .driveFileID)
        docID = try container.decodeIfPresent(String.self, forKey: .docID)
        folderID = try container.decodeIfPresent(String.self, forKey: .folderID)
        stage = try container.decode(HandoffStage.self, forKey: .stage)
        docStatus = try container.decode(DocStatus.self, forKey: .docStatus)
        closedOn = try container.decodeIfPresent(CalendarDay.self, forKey: .closedOn)
        purged = try container.decode(Bool.self, forKey: .purged)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        sessionURL = try container.decodeIfPresent(URL.self, forKey: .sessionURL)
        part = try container.decodeIfPresent(HandoffPart.self, forKey: .part)
        firedSummaries =
            try container.decodeIfPresent([String].self, forKey: .firedSummaries) ?? []
        summaryMarkers =
            try container.decodeIfPresent([String].self, forKey: .summaryMarkers) ?? []
    }

    // The summary routines of the pages this record sent itself, each once, in page order; a
    // page already sent in a part is summarized in that part's record.
    private var distinctSummaryRoutines: [SummaryRoutine] {
        var seen = Set<String>()
        return pages.filter { $0.earlierPart == nil }.flatMap { $0.summaryRoutines ?? [] }
            .filter { seen.insert($0.id).inserted }
    }

    /// The distinct summary routine IDs of the pages this record sent itself, in page order.
    public var summaryRoutineIDs: [String] {
        distinctSummaryRoutines.map(\.id)
    }

    /// The summary routines among `summaryRoutineIDs` not yet started, in that order.
    public var unsentSummaryRoutines: [SummaryRoutine] {
        distinctSummaryRoutines.filter { !firedSummaries.contains($0.id) }
    }

    /// Whether every summary routine asked for by a page this record sent itself has written
    /// its marker for that page; true when none was asked for.
    public var summariesWritten: Bool {
        let written = Set(summaryMarkers)
        return pages.filter { $0.earlierPart == nil }.allSatisfy { page in
            (page.summaryRoutines ?? []).allSatisfy { written.contains("\($0.id) \(page.page)") }
        }
    }

    /// What the Review list shows.
    public var phase: HandoffPhase {
        if let closedOn {
            return part == nil
                ? .closed(deleteOn: closedOn.adding(days: Self.purgeDelayDays), purged: purged)
                : .meetingClosed
        }
        switch (stage, docStatus) {
        case (.queued, _): return .waitingToUpload
        case (.uploaded, _): return .waitingToSend
        case (.notesRequested, .notesReady): return .notesReady
        case (.notesRequested, _): return .writingNotes
        case (.summariesPending, _):
            return unsentSummaryRoutines.isEmpty ? summariesPhase : .summariesWaitingToSend
        case (.summariesRequested, _): return summariesPhase
        case (.closing, _): return .closing
        }
    }

    private var summariesPhase: HandoffPhase {
        summariesWritten ? .summaryReady : .writingSummaries
    }

    /// What the end-of-day routine receives for `step` (`notes` or `close`): one JSON object with
    /// sorted keys. When it would be over 65,536 characters it leaves out `tasks` and `delegated` and sets `truncated`; when
    /// that is still too long it also leaves out every page's `title`, `summaryRoutines` and `source`.
    /// A meeting run has no `tasks` and no `delegated`.
    public func payload(step: RoutineStep) -> String {
        let full = Payload(self, step: step)
        var text = encode(full)
        if text.count <= Self.maxPayloadLength { return text }
        var shortened = full
        shortened.tasks = nil
        shortened.delegated = nil
        shortened.truncated = true
        text = encode(shortened)
        if text.count <= Self.maxPayloadLength { return text }
        shortened.pages = shortened.pages.map(\.bare)
        return encode(shortened)
    }

    private func encode(_ payload: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Encoding plain strings, numbers and arrays cannot fail; `compactMap` keeps that
        // impossible failure from needing a branch of its own.
        return [try? encoder.encode(payload)].compactMap { $0 }
            .map { String(decoding: $0, as: UTF8.self) }.joined()
    }

    /// The JSON the routine receives.
    private struct Payload: Encodable {
        let schema = "magenda.end-of-day/3"
        let scope: String
        let part: Int?
        let step: String
        let date: CalendarDay
        let checksum: String
        let driveFileID: String?
        let folderID: String?
        let docID: String?
        let pageCount: Int
        var pages: [HandoffPage]
        var tasks: [HandoffTask]?
        var delegated: [HandoffDelegated]?
        var truncated: Bool?

        init(_ handoff: DayHandoff, step: RoutineStep) {
            self.step = step.rawValue
            date = handoff.date
            checksum = handoff.checksum
            driveFileID = handoff.driveFileID
            folderID = handoff.folderID
            docID = handoff.docID
            pageCount = handoff.pages.count
            pages = handoff.pages
            scope = handoff.part == nil ? "day" : "meeting"
            part = handoff.part?.number
            tasks = handoff.part == nil ? handoff.tasks : nil
            delegated = handoff.part == nil ? handoff.delegated : nil
        }
    }

    /// What summary routine `routine` receives: one JSON object with sorted keys, naming the
    /// meetings of this record that ask for it. Titles are cut to 200 characters.
    public func summaryPayload(for routine: SummaryRoutine) -> String {
        encode(SummaryPayload(self, routine: routine))
    }

    /// The JSON a summary routine receives.
    private struct SummaryPayload: Encodable {
        struct Meeting: Encodable {
            let page: Int
            let key: String
            let calendarID: String?
            let eventID: String?
            let title: String?
            let extraPages: [Int]?
        }

        let schema = "magenda.summary/1"
        let scope: String
        let part: Int?
        let routineID: String
        let routineName: String
        let date: CalendarDay
        let checksum: String
        let driveFileID: String?
        let folderID: String?
        let docID: String?
        let pageCount: Int
        let meetings: [Meeting]

        init(_ handoff: DayHandoff, routine: SummaryRoutine) {
            routineID = routine.id
            routineName = routine.name
            date = handoff.date
            checksum = handoff.checksum
            driveFileID = handoff.driveFileID
            folderID = handoff.folderID
            docID = handoff.docID
            pageCount = handoff.pages.count
            scope = handoff.part == nil ? "day" : "meeting"
            part = handoff.part?.number
            meetings = handoff.pages.filter {
                $0.earlierPart == nil && ($0.summaryRoutines ?? []).contains { $0.id == routine.id }
            }.map { page in
                let extras = handoff.pages.filter { $0.source == page.key }.map(\.page)
                return Meeting(
                    page: page.page, key: page.key, calendarID: page.calendarID,
                    eventID: page.eventID, title: page.title.map { String($0.prefix(200)) },
                    extraPages: extras.isEmpty ? nil : extras)
            }
        }
    }

    /// The meeting that page `key` belongs to and that meeting's pages in `plan`'s order: the
    /// meeting page and the pages added as copies of it. nil when `key` is not a meeting page with
    /// an event, or a copy of one, or the meeting page is not in `plan`.
    public static func meetingPages(
        containing key: PageKey, day: BinderDay, plan: RenderPlan
    ) -> (meeting: PageKey, keys: [PageKey])? {
        func origin(of page: PageKey) -> PageKey? {
            guard case .extra = page else { return page }
            return day.extras.first { PageKey.extra($0.id) == page }?.source
        }
        guard case .meeting(let id)? = origin(of: key), !id.isEmpty else { return nil }
        let meeting = PageKey.meeting(id)
        let keys = plan.pages.map(\.key).filter { origin(of: $0) == meeting }
        return keys.contains(meeting) ? (meeting, keys) : nil
    }

    /// The entry for `page`, which is page `number` of the PDF.
    private static func handoffPage(
        number: Int, page: PagePlan, in day: BinderDay, inkedKeys: Set<PageKey> = []
    ) -> HandoffPage {
        let key = page.key.storageString
        switch page.key {
        case .meeting(let id):
            let ids = id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let parts = ids.count == 2 ? (String(ids[0]), String(ids[1])) : nil
            let found = meeting(id, for: page.key, in: day)
            return HandoffPage(
                page: number, key: key, calendarID: parts?.0, eventID: parts?.1,
                title: found?.title, summaryRoutines: found?.routines)
        case .extra:
            let source = day.extras.first { PageKey.extra($0.id) == page.key }?.source
            return HandoffPage(page: number, key: key, source: source?.storageString)
        case .routine(let id):
            let written =
                inkedKeys.contains(page.key)
                || day.extras.contains {
                    $0.source == page.key && inkedKeys.contains(.extra($0.id))
                }
            // The content the page was laid out from: the day's, else the one retained with it.
            let routine =
                ([day.content] + day.retained.filter { $0.key == page.key }.map(\.content))
                .lazy.compactMap { $0.routinePages.first { $0.id == id } }.first
            return HandoffPage(
                page: number, key: key, title: routine?.name,
                summaryRoutines: written ? routine.map { [$0] } : nil)
        default:
            return HandoffPage(page: number, key: key)
        }
    }

    /// The title and summary routines of the meeting page `id`, from the content the page was laid
    /// out from: the day's, else the one retained with the page.
    private static func meeting(
        _ id: String, for key: PageKey, in day: BinderDay
    ) -> (title: String, routines: [SummaryRoutine]?)? {
        let contents = [day.content] + day.retained.filter { $0.key == key }.map(\.content)
        for content in contents {
            guard
                let index = content.meetings.indices.first(where: {
                    $0 < content.meetingIDs.count ? content.meetingIDs[$0] == id : id == "#\($0)"
                })
            else { continue }
            let routines =
                content.meetingSummaryRoutines.indices.contains(index)
                ? content.meetingSummaryRoutines[index] : []
            return (content.meetings[index], routines.isEmpty ? nil : routines)
        }
        return nil
    }
}
