import Foundation

/// How far a finished day has come.
public enum HandoffStage: String, Codable, Sendable {
    case queued, uploaded, notesRequested, notesApproved, summaryApproved
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
    /// Meeting pages with a mapped skill: the skill.
    public let summarySkill: String?
    /// Added pages: the `storageString` of the page they copy.
    public let source: String?

    /// Creates a page entry.
    public init(
        page: Int, key: String, calendarID: String? = nil, eventID: String? = nil,
        title: String? = nil, summarySkill: String? = nil, source: String? = nil
    ) {
        self.page = page
        self.key = key
        self.calendarID = calendarID
        self.eventID = eventID
        self.title = title
        self.summarySkill = summarySkill
        self.source = source
    }

    /// The same page without the fields that only describe it.
    fileprivate var bare: HandoffPage {
        HandoffPage(page: page, key: key, calendarID: calendarID, eventID: eventID)
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

/// What the Review list can do with a day.
public enum HandoffAction: Equatable, Sendable {
    case retry
    case approve(RoutineStep)
}

/// What the Review list shows for a day.
public enum HandoffPhase: Equatable, Sendable {
    case closed(deleteOn: CalendarDay, purged: Bool)
    case waitingToUpload
    case waitingToSend
    case notesReady
    case writingNotes
    case summaryReady
    case working
    case closing

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
        case .summaryReady: "Summary ready for review"
        case .working: "Claude is working on the next step"
        case .closing: "Claude is closing the day"
        }
    }

    /// The button the row offers, if any.
    public var action: HandoffAction? {
        switch self {
        case .waitingToUpload, .waitingToSend: .retry
        case .notesReady: .approve(.approveNotes)
        case .summaryReady: .approve(.approveSummary)
        case .closed, .writingNotes, .working, .closing: nil
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

    private enum CodingKeys: String, CodingKey {
        case version, date, checksum, pages, tasks, delegated, driveFileID, docID, stage, docStatus
        case closedOn, purged, lastError, sessionURL
    }

    /// Creates a queued hand-off of `date` with nothing uploaded.
    public init(
        date: CalendarDay, checksum: String, pages: [HandoffPage], tasks: [HandoffTask],
        delegated: [HandoffDelegated]
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
    }

    /// Creates a queued hand-off from the PDF's `checksum`, the binder `day` and its `plan`.
    public init(date: CalendarDay, checksum: String, day: BinderDay, plan: RenderPlan) {
        let pages = plan.pages.enumerated().map { index, page in
            Self.handoffPage(number: index + 1, page: page, in: day)
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
        stage = try container.decode(HandoffStage.self, forKey: .stage)
        docStatus = try container.decode(DocStatus.self, forKey: .docStatus)
        closedOn = try container.decodeIfPresent(CalendarDay.self, forKey: .closedOn)
        purged = try container.decode(Bool.self, forKey: .purged)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        sessionURL = try container.decodeIfPresent(URL.self, forKey: .sessionURL)
    }

    /// What the Review list shows.
    public var phase: HandoffPhase {
        if let closedOn {
            return .closed(deleteOn: closedOn.adding(days: Self.purgeDelayDays), purged: purged)
        }
        switch (stage, docStatus) {
        case (.queued, _): return .waitingToUpload
        case (.uploaded, _): return .waitingToSend
        case (.notesRequested, .notesReady): return .notesReady
        case (.notesRequested, _): return .writingNotes
        case (.notesApproved, .summaryReady): return .summaryReady
        case (.notesApproved, _): return .working
        case (.summaryApproved, _): return .closing
        }
    }

    /// What the routine receives for `step`: one JSON object with sorted keys. When it would be
    /// over 65,536 characters it leaves out `tasks` and `delegated` and sets `truncated`; when
    /// that is still too long it also leaves out every page's `title`, `summarySkill` and `source`.
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

    private func encode(_ payload: Payload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Encoding plain strings, numbers and arrays cannot fail; `compactMap` keeps that
        // impossible failure from needing a branch of its own.
        return [try? encoder.encode(payload)].compactMap { $0 }
            .map { String(decoding: $0, as: UTF8.self) }.joined()
    }

    /// The JSON the routine receives.
    private struct Payload: Encodable {
        let schema = "magenda.end-of-day/1"
        let step: String
        let date: CalendarDay
        let checksum: String
        let driveFileID: String?
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
            docID = handoff.docID
            pageCount = handoff.pages.count
            pages = handoff.pages
            tasks = handoff.tasks
            delegated = handoff.delegated
        }
    }

    /// The entry for `page`, which is page `number` of the PDF.
    private static func handoffPage(number: Int, page: PagePlan, in day: BinderDay) -> HandoffPage {
        let key = page.key.storageString
        switch page.key {
        case .meeting(let id):
            let ids = id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let parts = ids.count == 2 ? (String(ids[0]), String(ids[1])) : nil
            let found = meeting(id, for: page.key, in: day)
            return HandoffPage(
                page: number, key: key, calendarID: parts?.0, eventID: parts?.1,
                title: found?.title, summarySkill: found?.skill)
        case .extra:
            let source = day.extras.first { PageKey.extra($0.id) == page.key }?.source
            return HandoffPage(page: number, key: key, source: source?.storageString)
        default:
            return HandoffPage(page: number, key: key)
        }
    }

    /// The title and summary skill of the meeting page `id`, from the content the page was laid
    /// out from: the day's, else the one retained with the page.
    private static func meeting(
        _ id: String, for key: PageKey, in day: BinderDay
    ) -> (title: String, skill: String?)? {
        let contents = [day.content] + day.retained.filter { $0.key == key }.map(\.content)
        for content in contents {
            guard
                let index = content.meetings.indices.first(where: {
                    $0 < content.meetingIDs.count ? content.meetingIDs[$0] == id : id == "#\($0)"
                })
            else { continue }
            let skill =
                content.meetingSummarySkills.indices.contains(index)
                ? content.meetingSummarySkills[index] : ""
            return (content.meetings[index], skill.isEmpty ? nil : skill)
        }
        return nil
    }
}
