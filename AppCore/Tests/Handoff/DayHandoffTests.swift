// AppCore's `DayHandoff`: building it from a binder day, its phase, its payload and its format.

import Foundation
import Testing

@testable import AppCore

@Suite("Day hand-off")
struct DayHandoffTests {
    private static let checksum = "sha256:" + String(repeating: "ab", count: 32)

    private static func day(_ dayOfMonth: Int = 26) throws -> CalendarDay {
        try #require(CalendarDay(year: 2026, month: 10, day: dayOfMonth))
    }

    private static func page(_ key: PageKey) -> PagePlan {
        PagePlan(key: key, chrome: .overview, operations: [])
    }

    private static func plan(_ keys: [PageKey], omitted: [TodoItem] = []) -> RenderPlan {
        RenderPlan(
            pageWidth: 612, pageHeight: 792, pages: keys.map(page), omittedTodoItems: omitted)
    }

    private static func content(
        todo: [TodoItem] = [], meetings: [String] = [], ids: [String] = [],
        skills: [String] = [], delegated: [DelegatedItem] = []
    ) throws -> AgendaContent {
        AgendaContent(
            date: try day(), todoItems: todo, schedule: [], meetings: meetings, meetingIDs: ids,
            delegated: delegated, meetingSummarySkills: skills)
    }

    private static func handoff(
        stage: HandoffStage = .queued, docStatus: DocStatus = .waitingForNotes,
        closedOn: CalendarDay? = nil, purged: Bool = false
    ) throws -> DayHandoff {
        var handoff = DayHandoff(
            date: try day(), checksum: checksum, pages: [], tasks: [], delegated: [])
        handoff.stage = stage
        handoff.docStatus = docStatus
        handoff.closedOn = closedOn
        handoff.purged = purged
        return handoff
    }

    @Test("A queued hand-off starts out waiting for notes, unpurged, with nothing uploaded")
    func initialState() throws {
        let handoff = try Self.handoff()
        #expect(handoff.version == DayHandoff.formatVersion)
        #expect(handoff.stage == .queued)
        #expect(handoff.docStatus == .waitingForNotes)
        #expect(!handoff.purged)
        #expect(handoff.driveFileID == nil && handoff.docID == nil && handoff.closedOn == nil)
        #expect(handoff.lastError == nil && handoff.sessionURL == nil)
    }

    @Test("The builder describes meeting pages, added pages and the printed rows")
    func builder() throws {
        let retainedContent = try Self.content(
            meetings: ["Old"], ids: ["cal|old"], skills: ["old-skill"])
        var binder = BinderDay(
            content: try Self.content(
                todo: [
                    TodoItem(text: "A", notes: "", due: "10/27", taskID: "t1"),
                    TodoItem(text: "B", notes: "", due: "", taskID: "t2"),
                    TodoItem(text: "A", notes: "n", due: "10/27", taskID: "t3"),
                ],
                meetings: ["Sync", "Plain", "Lone", "Odd"],
                ids: ["work@x.com|ev1|part", "bare", "cal|ev3"],
                skills: ["notes-skill", ""],
                delegated: [
                    DelegatedItem(
                        text: "Weekly", owner: "Sam", cadence: .weekly, marked: false,
                        status: [], taskID: "d1"),
                    DelegatedItem(
                        text: "Daily", owner: "Ann", cadence: .daily, marked: false, status: []),
                ]),
            theme: Theme(),
            retained: [RetainedPage(key: .meeting("cal|old"), content: retainedContent)])
        binder.addPage(after: .meeting("bare"), id: "x")
        let plan = Self.plan(
            [
                .overview, .meeting("work@x.com|ev1|part"), .meeting("bare"), .extra("x"),
                .meeting("cal|old"), .meeting("#\(3)"), .meeting("cal|gone"), .notes,
            ],
            omitted: [TodoItem(text: "A", notes: "", due: "10/27")])

        let handoff = DayHandoff(
            date: try Self.day(), checksum: Self.checksum, day: binder, plan: plan)

        #expect(
            handoff.pages == [
                HandoffPage(page: 1, key: "overview"),
                HandoffPage(
                    page: 2, key: "meeting:work@x.com|ev1|part", calendarID: "work@x.com",
                    eventID: "ev1|part", title: "Sync", summarySkill: "notes-skill"),
                HandoffPage(page: 3, key: "meeting:bare", title: "Plain"),
                HandoffPage(page: 4, key: "extra:x", source: "meeting:bare"),
                HandoffPage(
                    page: 5, key: "meeting:cal|old", calendarID: "cal", eventID: "old",
                    title: "Old", summarySkill: "old-skill"),
                HandoffPage(page: 6, key: "meeting:#\(3)", title: "Odd"),
                HandoffPage(page: 7, key: "meeting:cal|gone", calendarID: "cal", eventID: "gone"),
                HandoffPage(page: 8, key: "notes"),
            ])
        #expect(
            handoff.tasks == [
                HandoffTask(taskID: "t1", text: "A", due: "10/27"),
                HandoffTask(taskID: "t2", text: "B", due: ""),
            ])
        #expect(
            handoff.delegated == [
                HandoffDelegated(taskID: nil, text: "Daily", owner: "Ann"),
                HandoffDelegated(taskID: "d1", text: "Weekly", owner: "Sam"),
            ])
        #expect(handoff.stage == .queued)
    }

    @Test("A day without meetings has one blank meeting page without a title")
    func blankMeetingPage() throws {
        let binder = BinderDay(content: try Self.content(), theme: Theme())
        let handoff = DayHandoff(
            date: try Self.day(), checksum: Self.checksum, day: binder,
            plan: Self.plan([.meeting("")]))
        #expect(handoff.pages == [HandoffPage(page: 1, key: "meeting:")])
    }

    @Test("An added page whose record is gone has no source")
    func extraWithoutRecord() throws {
        let binder = BinderDay(content: try Self.content(), theme: Theme())
        let handoff = DayHandoff(
            date: try Self.day(), checksum: Self.checksum, day: binder,
            plan: Self.plan([.extra("lost")]))
        #expect(handoff.pages == [HandoffPage(page: 1, key: "extra:lost")])
    }

    /// One row of the phase table: a state and what it shows.
    struct PhaseRow: Sendable {
        let stage: HandoffStage
        let status: DocStatus
        let closedOn: String?
        let purged: Bool
        /// The phase, or nil for a closed day, whose `deleteOn` is `deleteOn`.
        let phase: HandoffPhase?
        let deleteOn: String?
        let title: String
        let action: HandoffAction?
    }

    static let rows: [PhaseRow] = [
        PhaseRow(
            stage: .summaryApproved, status: .closed, closedOn: "2026-10-20", purged: false,
            phase: nil, deleteOn: "2026-10-25",
            title: "Closed. Handwriting is deleted on 2026-10-25.", action: nil),
        PhaseRow(
            stage: .queued, status: .closed, closedOn: "2026-12-30", purged: true,
            phase: nil, deleteOn: "2027-01-04",
            title: "Closed. Handwriting deleted.", action: nil),
        PhaseRow(
            stage: .queued, status: .waitingForNotes, closedOn: nil, purged: false,
            phase: .waitingToUpload, deleteOn: nil, title: "Waiting to upload",
            action: .retry),
        PhaseRow(
            stage: .uploaded, status: .notesReady, closedOn: nil, purged: false,
            phase: .waitingToSend, deleteOn: nil, title: "Uploaded, not yet sent to Claude",
            action: .retry),
        PhaseRow(
            stage: .notesRequested, status: .notesReady, closedOn: nil, purged: false,
            phase: .notesReady, deleteOn: nil, title: "Notes ready for review",
            action: .approve(.approveNotes)),
        PhaseRow(
            stage: .notesRequested, status: .waitingForNotes, closedOn: nil, purged: false,
            phase: .writingNotes, deleteOn: nil, title: "Claude is writing the notes",
            action: nil),
        PhaseRow(
            stage: .notesRequested, status: .summaryReady, closedOn: nil, purged: false,
            phase: .writingNotes, deleteOn: nil, title: "Claude is writing the notes",
            action: nil),
        PhaseRow(
            stage: .notesApproved, status: .summaryReady, closedOn: nil, purged: false,
            phase: .summaryReady, deleteOn: nil, title: "Summary ready for review",
            action: .approve(.approveSummary)),
        PhaseRow(
            stage: .notesApproved, status: .notesReady, closedOn: nil, purged: false,
            phase: .working, deleteOn: nil, title: "Claude is working on the next step",
            action: nil),
        PhaseRow(
            stage: .summaryApproved, status: .summaryReady, closedOn: nil, purged: false,
            phase: .closing, deleteOn: nil, title: "Claude is closing the day", action: nil),
    ]

    @Test("The phase and its title and action follow the table, row by row", arguments: rows)
    func phases(row: PhaseRow) throws {
        let handoff = try Self.handoff(
            stage: row.stage, docStatus: row.status,
            closedOn: row.closedOn.flatMap(CalendarDay.init(isoString:)), purged: row.purged)
        let expected: HandoffPhase
        if let phase = row.phase {
            expected = phase
        } else {
            let deleteOn = try #require(row.deleteOn.flatMap(CalendarDay.init(isoString:)))
            expected = .closed(deleteOn: deleteOn, purged: row.purged)
        }
        #expect(handoff.phase == expected)
        #expect(handoff.phase.title == row.title)
        #expect(handoff.phase.action == row.action)
    }

    @Test("The payload decodes back to the documented keys, with nil fields left out")
    func payloadKeys() throws {
        var handoff = try Self.handoff()
        handoff.pages = [
            HandoffPage(page: 1, key: "overview"),
            HandoffPage(
                page: 2, key: "meeting:c|e", calendarID: "c", eventID: "e", title: "T",
                summarySkill: "s"),
        ]
        handoff.tasks = [HandoffTask(taskID: nil, text: "Do", due: "10/27")]
        handoff.delegated = [HandoffDelegated(taskID: "d", text: "Ask", owner: "Sam")]
        handoff.driveFileID = "file"
        let text = handoff.payload(step: .approveNotes)

        let object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(
            Set(object.keys) == [
                "schema", "step", "date", "checksum", "driveFileID", "pageCount", "pages", "tasks",
                "delegated",
            ])
        #expect(object["schema"] as? String == "magenda.end-of-day/1")
        #expect(object["step"] as? String == "approve-notes")
        #expect(object["date"] as? String == "2026-10-26")
        #expect(object["checksum"] as? String == Self.checksum)
        #expect(object["driveFileID"] as? String == "file")
        #expect(object["pageCount"] as? Int == 2)
        let pages = try #require(object["pages"] as? [[String: Any]])
        #expect(Set(pages[0].keys) == ["page", "key"])
        #expect(
            Set(pages[1].keys) == ["page", "key", "calendarID", "eventID", "title", "summarySkill"])
        let tasks = try #require(object["tasks"] as? [[String: Any]])
        #expect(Set(tasks[0].keys) == ["text", "due"])
        #expect(text.hasPrefix(#"{"checksum":"#))
    }

    @Test("A payload of a long day is cut down: tasks first, then the page details")
    func truncation() throws {
        var handoff = try Self.handoff()
        handoff.pages = [HandoffPage(page: 1, key: "overview")]
        handoff.tasks = (0..<3_000).map {
            HandoffTask(taskID: "t\($0)", text: String(repeating: "x", count: 100), due: "")
        }
        var text = handoff.payload(step: .notes)
        #expect(text.count <= 65_536)
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["truncated"] as? Bool == true)
        #expect(object["tasks"] == nil && object["delegated"] == nil)
        #expect(object["pageCount"] as? Int == 1)

        handoff.tasks = []
        handoff.pages = (1...400).map {
            HandoffPage(
                page: $0, key: "meeting:c|e\($0)", calendarID: "c", eventID: "e\($0)",
                title: String(repeating: "t", count: 200), summarySkill: "s", source: "notes")
        }
        text = handoff.payload(step: .notes)
        #expect(text.count <= 65_536)
        object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["truncated"] as? Bool == true)
        #expect(object["pageCount"] as? Int == 400)
        let pages = try #require(object["pages"] as? [[String: Any]])
        #expect(pages.count == 400)
        #expect(Set(pages[0].keys) == ["page", "key", "calendarID", "eventID"])

        handoff.pages = [HandoffPage(page: 1, key: "overview")]
        text = handoff.payload(step: .notes)
        object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["truncated"] == nil)
    }

    @Test("A hand-off round-trips, and another format version fails to decode")
    func codable() throws {
        var handoff = try Self.handoff(stage: .notesRequested, docStatus: .notesReady)
        handoff.docID = "doc"
        handoff.driveFileID = "file"
        handoff.closedOn = try Self.day(27)
        handoff.lastError = "Oops"
        handoff.sessionURL = URL(string: "https://claude.ai/code/session_1")
        handoff.pages = [HandoffPage(page: 1, key: "overview")]
        let data = try JSONEncoder().encode(handoff)
        #expect(try JSONDecoder().decode(DayHandoff.self, from: data) == handoff)

        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 2
        let other = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DayHandoff.self, from: other)
        }
    }
}
