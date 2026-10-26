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

    private static func routine(_ name: String) -> SummaryRoutine {
        SummaryRoutine(id: "id-" + name, name: name)
    }

    private static func content(
        todo: [TodoItem] = [], meetings: [String] = [], ids: [String] = [],
        routines: [[SummaryRoutine]] = [], delegated: [DelegatedItem] = []
    ) throws -> AgendaContent {
        AgendaContent(
            date: try day(), todoItems: todo, schedule: [], meetings: meetings, meetingIDs: ids,
            delegated: delegated, meetingSummaryRoutines: routines)
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
            meetings: ["Old"], ids: ["cal|old"], routines: [[Self.routine("old")]])
        var binder = BinderDay(
            content: try Self.content(
                todo: [
                    TodoItem(text: "A", notes: "", due: "10/27", taskID: "t1"),
                    TodoItem(text: "B", notes: "", due: "", taskID: "t2"),
                    TodoItem(text: "A", notes: "n", due: "10/27", taskID: "t3"),
                ],
                meetings: ["Sync", "Plain", "Lone", "Odd"],
                ids: ["work@x.com|ev1|part", "bare", "cal|ev3"],
                routines: [[Self.routine("notes")], []],
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
                    eventID: "ev1|part", title: "Sync",
                    summaryRoutines: [Self.routine("notes")]),
                HandoffPage(page: 3, key: "meeting:bare", title: "Plain"),
                HandoffPage(page: 4, key: "extra:x", source: "meeting:bare"),
                HandoffPage(
                    page: 5, key: "meeting:cal|old", calendarID: "cal", eventID: "old",
                    title: "Old",
                    summaryRoutines: [Self.routine("old")]),
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

    @Test("A page entry's summary routines round-trip, and a meeting without them has nil")
    func summaryRoutinesRoundTrip() throws {
        let routines = [Self.routine("a"), Self.routine("b")]
        let page = HandoffPage(
            page: 2, key: "meeting:c|e", calendarID: "c", eventID: "e", title: "T",
            summaryRoutines: routines)
        let decoded = try JSONDecoder().decode(
            HandoffPage.self, from: JSONEncoder().encode(page))
        #expect(decoded == page)
        #expect(decoded.summaryRoutines == routines)
        let binder = BinderDay(
            content: try Self.content(
                meetings: ["Sync", "Plain"], ids: ["c|e", "c|f"], routines: [routines, []]),
            theme: Theme())
        let handoff = DayHandoff(
            date: try Self.day(), checksum: Self.checksum, day: binder,
            plan: Self.plan([.meeting("c|e"), .meeting("c|f")]))
        #expect(handoff.pages.map(\.summaryRoutines) == [routines, nil])
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
        /// Whether the single page asks for the routine named `s`.
        var asksForSummary = false
        var fired: [String] = []
        var markers: [String] = []
    }

    static let rows: [PhaseRow] = [
        PhaseRow(
            stage: .closing, status: .closed, closedOn: "2026-10-20", purged: false,
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
            action: .approveNotes),
        PhaseRow(
            stage: .notesRequested, status: .waitingForNotes, closedOn: nil, purged: false,
            phase: .writingNotes, deleteOn: nil, title: "Claude is writing the notes",
            action: nil),
        PhaseRow(
            stage: .notesRequested, status: .unknown, closedOn: nil, purged: false,
            phase: .writingNotes, deleteOn: nil, title: "Claude is writing the notes",
            action: nil),
        PhaseRow(
            stage: .summariesPending, status: .notesReady, closedOn: nil, purged: false,
            phase: .summariesWaitingToSend, deleteOn: nil,
            title: "Notes approved. Summaries not yet sent to Claude", action: .retry,
            asksForSummary: true),
        PhaseRow(
            stage: .summariesPending, status: .notesReady, closedOn: nil, purged: false,
            phase: .writingSummaries, deleteOn: nil, title: "Claude is writing the summaries",
            action: nil, asksForSummary: true, fired: ["id-s"]),
        PhaseRow(
            stage: .summariesPending, status: .notesReady, closedOn: nil, purged: false,
            phase: .summaryReady, deleteOn: nil, title: "Summaries ready for review",
            action: .approveSummaries, asksForSummary: true, fired: ["id-s"],
            markers: ["id-s 1"]),
        PhaseRow(
            stage: .summariesRequested, status: .notesReady, closedOn: nil, purged: false,
            phase: .writingSummaries, deleteOn: nil, title: "Claude is writing the summaries",
            action: nil, asksForSummary: true, fired: ["id-s"]),
        PhaseRow(
            stage: .summariesRequested, status: .notesReady, closedOn: nil, purged: false,
            phase: .summaryReady, deleteOn: nil, title: "Summaries ready for review",
            action: .approveSummaries, asksForSummary: true, fired: ["id-s"],
            markers: ["id-s 1"]),
        PhaseRow(
            stage: .closing, status: .notesReady, closedOn: nil, purged: false,
            phase: .closing, deleteOn: nil, title: "Claude is closing the day", action: nil),
    ]

    @Test("The phase and its title and action follow the table, row by row", arguments: rows)
    func phases(row: PhaseRow) throws {
        var handoff = try Self.handoff(
            stage: row.stage, docStatus: row.status,
            closedOn: row.closedOn.flatMap(CalendarDay.init(isoString:)), purged: row.purged)
        if row.asksForSummary {
            handoff.pages = [
                HandoffPage(
                    page: 1, key: "meeting:c|e", calendarID: "c", eventID: "e", title: "T",
                    summaryRoutines: [Self.routine("s")])
            ]
        }
        handoff.firedSummaries = row.fired
        handoff.summaryMarkers = row.markers
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

    @Test("A stage an earlier build saved after approving decodes as closing")
    func legacyStages() throws {
        func decode(_ raw: String) throws -> HandoffStage {
            try JSONDecoder().decode(HandoffStage.self, from: Data(#""\#(raw)""#.utf8))
        }
        #expect(try decode("notesApproved") == .closing)
        #expect(try decode("summaryApproved") == .closing)
        for stage in [
            HandoffStage.queued, .uploaded, .notesRequested, .summariesPending,
            .summariesRequested, .closing,
        ] {
            #expect(try decode(stage.rawValue) == stage)
        }
        #expect(throws: DecodingError.self) { try decode("somethingNew") }
        let encoded = try JSONEncoder().encode(HandoffStage.summariesPending)
        #expect(String(decoding: encoded, as: UTF8.self) == #""summariesPending""#)
    }

    @Test("The Drive folder round-trips, is optional on disk and is in the payload only when set")
    func folderID() throws {
        var handoff = try Self.handoff()
        #expect(handoff.folderID == nil)
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(handoff)) as? [String: Any])
        #expect(object["folderID"] == nil)
        object["pages"] = []
        let old = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(DayHandoff.self, from: old).folderID == nil)
        #expect(!handoff.payload(step: .notes).contains("folderID"))

        handoff.folderID = "folder-9"
        let data = try JSONEncoder().encode(handoff)
        #expect(try JSONDecoder().decode(DayHandoff.self, from: data).folderID == "folder-9")
        #expect(handoff.payload(step: .notes).contains(#""folderID":"folder-9""#))
    }

    @Test("The payload decodes back to the documented keys, with nil fields left out")
    func payloadKeys() throws {
        var handoff = try Self.handoff()
        handoff.pages = [
            HandoffPage(page: 1, key: "overview"),
            HandoffPage(
                page: 2, key: "meeting:c|e", calendarID: "c", eventID: "e", title: "T",
                summaryRoutines: [Self.routine("s")]),
        ]
        handoff.tasks = [HandoffTask(taskID: nil, text: "Do", due: "10/27")]
        handoff.delegated = [HandoffDelegated(taskID: "d", text: "Ask", owner: "Sam")]
        handoff.driveFileID = "file"
        let text = handoff.payload(step: .close)

        let object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(
            Set(object.keys) == [
                "schema", "scope", "step", "date", "checksum", "driveFileID", "pageCount", "pages",
                "tasks", "delegated",
            ])
        #expect(object["schema"] as? String == "magenda.end-of-day/3")
        #expect(object["scope"] as? String == "day")
        #expect(object["part"] == nil)
        #expect(object["step"] as? String == "close")
        #expect(object["date"] as? String == "2026-10-26")
        #expect(object["checksum"] as? String == Self.checksum)
        #expect(object["driveFileID"] as? String == "file")
        #expect(object["pageCount"] as? Int == 2)
        let pages = try #require(object["pages"] as? [[String: Any]])
        #expect(Set(pages[0].keys) == ["page", "key"])
        #expect(
            Set(pages[1].keys) == [
                "page", "key", "calendarID", "eventID", "title", "summaryRoutines",
            ])
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
                title: String(repeating: "t", count: 200), summaryRoutines: [Self.routine("s")],
                source: "notes")
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

    private static let part = HandoffPart(
        number: 2, meetingKey: "meeting:c|e", title: "Weekly sync")

    private static func partHandoff(closedOn: CalendarDay? = nil) throws -> DayHandoff {
        var handoff = DayHandoff(
            date: try day(), checksum: checksum,
            pages: [
                HandoffPage(
                    page: 1, key: "meeting:c|e", calendarID: "c", eventID: "e",
                    title: "Weekly sync",
                    summaryRoutines: [Self.routine("s")]),
                HandoffPage(page: 2, key: "extra:x", source: "meeting:c|e"),
            ],
            tasks: [HandoffTask(taskID: nil, text: "Do", due: "")],
            delegated: [HandoffDelegated(taskID: nil, text: "Ask", owner: "Sam")],
            part: part)
        handoff.closedOn = closedOn
        return handoff
    }

    @Test("A day payload says scope day and carries a page's earlierPart")
    func dayPayloadScope() throws {
        var handoff = try Self.handoff()
        handoff.pages = [
            HandoffPage(page: 1, key: "overview"),
            HandoffPage(
                page: 2, key: "meeting:c|e", calendarID: "c", eventID: "e", title: "T",
                earlierPart: 1),
        ]
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(handoff.payload(step: .notes).utf8))
                as? [String: Any])
        #expect(object["scope"] as? String == "day")
        #expect(object["part"] == nil)
        #expect(object["tasks"] != nil && object["delegated"] != nil)
        let pages = try #require(object["pages"] as? [[String: Any]])
        #expect(Set(pages[0].keys) == ["page", "key"])
        #expect(
            Set(pages[1].keys) == ["page", "key", "calendarID", "eventID", "title", "earlierPart"])
        #expect(pages[1]["earlierPart"] as? Int == 1)
    }

    @Test("A part payload says scope meeting and its number, and has no tasks or delegated")
    func partPayload() throws {
        var handoff = try Self.partHandoff()
        handoff.driveFileID = "file"
        let text = handoff.payload(step: .notes)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(
            Set(object.keys) == [
                "schema", "scope", "part", "step", "date", "checksum", "driveFileID", "pageCount",
                "pages",
            ])
        #expect(object["schema"] as? String == "magenda.end-of-day/3")
        #expect(object["scope"] as? String == "meeting")
        #expect(object["part"] as? Int == 2)
        #expect(object["pageCount"] as? Int == 2)
        #expect(object["tasks"] == nil && object["delegated"] == nil)
        let pages = try #require(object["pages"] as? [[String: Any]])
        #expect(pages.map { $0["page"] as? Int } == [1, 2])
    }

    @Test("Truncating a payload keeps every page's earlierPart")
    func truncationKeepsEarlierPart() throws {
        var handoff = try Self.handoff()
        handoff.pages = (1...400).map {
            HandoffPage(
                page: $0, key: "meeting:c|e\($0)", calendarID: "c", eventID: "e\($0)",
                title: String(repeating: "t", count: 200), summaryRoutines: [Self.routine("s")],
                source: "notes", earlierPart: $0 % 2 == 0 ? 3 : nil)
        }
        let text = handoff.payload(step: .notes)
        #expect(text.count <= 65_536)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["truncated"] as? Bool == true)
        let pages = try #require(object["pages"] as? [[String: Any]])
        #expect(Set(pages[0].keys) == ["page", "key", "calendarID", "eventID"])
        #expect(Set(pages[1].keys) == ["page", "key", "calendarID", "eventID", "earlierPart"])
        #expect(pages[1]["earlierPart"] as? Int == 3)
    }

    @Test("The day initializer marks the pages of earlier parts")
    func earlierParts() throws {
        let binder = BinderDay(
            content: try Self.content(
                meetings: ["Sync"], ids: ["c|e"], routines: [[Self.routine("s")]]),
            theme: Theme(),
            extras: [ExtraPage(id: "x", after: .meeting("c|e"), source: .meeting("c|e"))])
        let handoff = DayHandoff(
            date: try Self.day(), checksum: Self.checksum, day: binder,
            plan: Self.plan([.overview, .meeting("c|e"), .extra("x")]),
            earlierParts: [.meeting("c|e"): 1, .extra("x"): 1])
        #expect(handoff.part == nil)
        #expect(handoff.pages.map(\.earlierPart) == [nil, 1, 1])
        #expect(
            handoff.pages[1]
                == HandoffPage(
                    page: 2, key: "meeting:c|e", calendarID: "c", eventID: "e", title: "Sync",
                    summaryRoutines: [Self.routine("s")], earlierPart: 1))
        #expect(handoff.pages[2].source == "meeting:c|e")
    }

    @Test("The meeting initializer takes the meeting's pages, no rows, and a part")
    func meetingInitializer() throws {
        let binder = BinderDay(
            content: try Self.content(
                todo: [TodoItem(text: "A", notes: "", due: "", taskID: "t1")],
                meetings: ["Weekly sync"], ids: ["c|e"], routines: [[Self.routine("s")]],
                delegated: [
                    DelegatedItem(
                        text: "W", owner: "Sam", cadence: .weekly, marked: false, status: [])
                ]),
            theme: Theme(),
            extras: [ExtraPage(id: "x", after: .meeting("c|e"), source: .meeting("c|e"))])
        let handoff = DayHandoff(
            date: try Self.day(), part: 2, meeting: .meeting("c|e"), checksum: Self.checksum,
            day: binder, plan: Self.plan([.meeting("c|e"), .extra("x")]))
        #expect(handoff.part == Self.part)
        #expect(handoff.tasks.isEmpty && handoff.delegated.isEmpty)
        #expect(handoff.stage == .queued)
        #expect(handoff.pages.map(\.page) == [1, 2])
        #expect(handoff.pages.map(\.key) == ["meeting:c|e", "extra:x"])
        #expect(handoff.pages.allSatisfy { $0.earlierPart == nil })
        #expect(handoff.pageKeys == [.meeting("c|e"), .extra("x")])

        let untitled = DayHandoff(
            date: try Self.day(), part: 1, meeting: .meeting("c|missing"),
            checksum: Self.checksum, day: binder, plan: Self.plan([.overview]))
        #expect(
            untitled.part == HandoffPart(number: 1, meetingKey: "meeting:c|missing", title: nil))
    }

    @Test("Page keys skip entries that name no page")
    func pageKeys() throws {
        var handoff = try Self.handoff()
        handoff.pages = [
            HandoffPage(page: 1, key: "overview"), HandoffPage(page: 2, key: "bogus"),
            HandoffPage(page: 3, key: "delegated:0"),
        ]
        #expect(handoff.pageKeys == [.overview, .delegated(0)])
    }

    /// A binder day with two meetings, an added copy of the first, one of the overview, and a
    /// plan with every page.
    private static func meetingRig() throws -> (BinderDay, RenderPlan) {
        let binder = BinderDay(
            content: try content(meetings: ["One", "Two"], ids: ["c|1", "c|2"]),
            theme: Theme(),
            extras: [
                ExtraPage(id: "x1", after: .meeting("c|1"), source: .meeting("c|1")),
                ExtraPage(id: "xo", after: .overview, source: .overview),
                ExtraPage(id: "xb", after: .meeting(""), source: .meeting("")),
                ExtraPage(id: "x2", after: .meeting("c|2"), source: .meeting("c|2")),
            ])
        let plan = plan([
            .overview, .extra("xo"), .meeting("c|1"), .extra("x1"), .meeting("c|2"),
            .extra("x2"), .meeting(""), .extra("xb"), .notes,
        ])
        return (binder, plan)
    }

    @Test("A meeting page and its added copies belong to one meeting, in plan order")
    func meetingPagesOfAMeeting() throws {
        let (binder, plan) = try Self.meetingRig()
        for key in [PageKey.meeting("c|1"), .extra("x1")] {
            let found = try #require(
                DayHandoff.meetingPages(containing: key, day: binder, plan: plan))
            #expect(found.meeting == .meeting("c|1"))
            #expect(found.keys == [.meeting("c|1"), .extra("x1")])
        }
        let second = try #require(
            DayHandoff.meetingPages(containing: .extra("x2"), day: binder, plan: plan))
        #expect(second.meeting == .meeting("c|2"))
        #expect(second.keys == [.meeting("c|2"), .extra("x2")])
    }

    @Test("Pages that are no meeting with an event have no meeting")
    func meetingPagesOfOtherPages() throws {
        let (binder, plan) = try Self.meetingRig()
        for key in [
            PageKey.overview, .extra("xo"), .meeting(""), .extra("xb"), .notes, .delegated(0),
            .extra("unknown"),
        ] {
            #expect(DayHandoff.meetingPages(containing: key, day: binder, plan: plan) == nil)
        }
    }

    @Test("A meeting page missing from the plan has no meeting")
    func meetingPagesNotInPlan() throws {
        let (binder, _) = try Self.meetingRig()
        let plan = Self.plan([.overview, .extra("x1")])
        #expect(
            DayHandoff.meetingPages(containing: .extra("x1"), day: binder, plan: plan) == nil)
    }

    @Test("Titles and Drive names of a day and of a part")
    func names() throws {
        let day = try Self.handoff()
        #expect(day.displayTitle == "2026-10-26")
        #expect(day.pdfName == "Magenda 2026-10-26.pdf")
        #expect(day.docName == "Magenda 2026-10-26 notes")

        let part = try Self.partHandoff()
        #expect(part.displayTitle == "2026-10-26 \u{B7} Weekly sync")
        #expect(part.pdfName == "Magenda 2026-10-26 part 2.pdf")
        #expect(part.docName == "Magenda 2026-10-26 part 2 notes")

        let untitled = DayHandoff(
            date: try Self.day(), checksum: Self.checksum, pages: [], tasks: [], delegated: [],
            part: HandoffPart(number: 1, meetingKey: "meeting:c|e", title: nil))
        #expect(untitled.displayTitle == "2026-10-26 \u{B7} Meeting")
    }

    @Test("The ID is the date and the part's number")
    func identity() throws {
        #expect(try Self.handoff().id == HandoffID(date: try Self.day(), part: nil))
        #expect(try Self.partHandoff().id == HandoffID(date: try Self.day(), part: 2))
    }

    @Test("The list order is newest date first, the day before its parts, parts by number")
    func listOrder() throws {
        let ids = [
            HandoffID(date: try Self.day(25), part: nil),
            HandoffID(date: try Self.day(26), part: 2),
            HandoffID(date: try Self.day(26), part: nil),
            HandoffID(date: try Self.day(27), part: 1),
            HandoffID(date: try Self.day(26), part: 1),
        ]
        #expect(
            ids.sorted(by: HandoffID.listOrder) == [
                HandoffID(date: try Self.day(27), part: 1),
                HandoffID(date: try Self.day(26), part: nil),
                HandoffID(date: try Self.day(26), part: 1),
                HandoffID(date: try Self.day(26), part: 2),
                HandoffID(date: try Self.day(25), part: nil),
            ])
        #expect(!HandoffID.listOrder(ids[0], ids[0]))
    }

    @Test("A closed part is .meetingClosed, whatever the purge state; a closed day is not")
    func meetingClosed() throws {
        let closed = try Self.partHandoff(closedOn: try Self.day(27))
        #expect(closed.phase == .meetingClosed)
        #expect(closed.phase.title == "Closed")
        #expect(closed.phase.action == nil)
        #expect(try Self.partHandoff().phase == .waitingToUpload)
    }

    @Test("A part round-trips, and a record saved without a part decodes as a day")
    func partCodable() throws {
        let part = try Self.partHandoff()
        let data = try JSONEncoder().encode(part)
        #expect(try JSONDecoder().decode(DayHandoff.self, from: data) == part)

        var object = try #require(
            JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(try Self.handoff())) as? [String: Any])
        #expect(object["part"] == nil)
        object["pages"] = [["page": 1, "key": "overview"]]
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(DayHandoff.self, from: old)
        #expect(decoded.part == nil)
        #expect(decoded.id == HandoffID(date: try Self.day(), part: nil))
        #expect(decoded.pages == [HandoffPage(page: 1, key: "overview")])
    }

    private static func summaryHandoff(part: HandoffPart? = nil) throws -> DayHandoff {
        let memo = routine("memo")
        let log = routine("log")
        var handoff = DayHandoff(
            date: try day(), checksum: checksum,
            pages: [
                HandoffPage(page: 1, key: "overview"),
                HandoffPage(
                    page: 2, key: "meeting:c|e1", calendarID: "c", eventID: "e1",
                    title: "Weekly sync", summaryRoutines: [memo, log]),
                HandoffPage(page: 3, key: "extra:x", source: "meeting:c|e1"),
                HandoffPage(
                    page: 4, key: "meeting:c|e2", calendarID: "c", eventID: "e2",
                    title: "Review", summaryRoutines: [log], earlierPart: 1),
                HandoffPage(
                    page: 5, key: "meeting:c|e3", calendarID: "c", eventID: "e3",
                    title: "Planning", summaryRoutines: [log, memo]),
                HandoffPage(page: 6, key: "extra:y", source: "meeting:c|e1"),
            ],
            tasks: [HandoffTask(taskID: nil, text: "Do", due: "")], delegated: [], part: part)
        handoff.driveFileID = "file"
        handoff.docID = "doc"
        handoff.folderID = "folder"
        return handoff
    }

    @Test("The summary routine IDs are distinct, in page order, and skip earlierPart pages")
    func summaryRoutineIDs() throws {
        var handoff = try Self.summaryHandoff()
        #expect(handoff.summaryRoutineIDs == ["id-memo", "id-log"])
        handoff.pages = handoff.pages.filter { $0.earlierPart != nil || $0.summaryRoutines == nil }
        #expect(handoff.summaryRoutineIDs.isEmpty)
        #expect(handoff.unsentSummaryRoutines.isEmpty)
        #expect(handoff.summariesWritten)
    }

    @Test("The unsent summary routines are those not fired yet, in order")
    func unsentSummaryRoutines() throws {
        var handoff = try Self.summaryHandoff()
        #expect(handoff.unsentSummaryRoutines == [Self.routine("memo"), Self.routine("log")])
        handoff.firedSummaries = ["id-memo"]
        #expect(handoff.unsentSummaryRoutines == [Self.routine("log")])
        handoff.firedSummaries = ["id-log", "id-memo", "id-gone"]
        #expect(handoff.unsentSummaryRoutines.isEmpty)
    }

    @Test("Summaries are written once every page's every routine has its marker")
    func summariesWritten() throws {
        var handoff = try Self.summaryHandoff()
        #expect(!handoff.summariesWritten)
        handoff.summaryMarkers = ["id-memo 2", "id-log 2", "id-log 5"]
        #expect(!handoff.summariesWritten)
        handoff.summaryMarkers.append("id-memo 5")
        #expect(handoff.summariesWritten)
        handoff.summaryMarkers = ["id-memo 5", "id-log 5", "id-memo 2", "id-log 2", "id-log 4"]
        #expect(handoff.summariesWritten)
        handoff.summaryMarkers = ["id-memo 2", "id-log 2", "id-memo 5", "id-log 3"]
        #expect(!handoff.summariesWritten)
    }

    @Test("A record without the summary keys decodes with them empty, and they round-trip")
    func summaryFieldsCodable() throws {
        var handoff = try Self.summaryHandoff()
        let plain = try JSONEncoder().encode(handoff)
        var object = try #require(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        object["firedSummaries"] = nil
        object["summaryMarkers"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(DayHandoff.self, from: legacy)
        #expect(decoded.firedSummaries.isEmpty && decoded.summaryMarkers.isEmpty)

        handoff.firedSummaries = ["id-memo"]
        handoff.summaryMarkers = ["id-memo 2"]
        let data = try JSONEncoder().encode(handoff)
        let back = try JSONDecoder().decode(DayHandoff.self, from: data)
        #expect(back == handoff)
        #expect(back.firedSummaries == ["id-memo"] && back.summaryMarkers == ["id-memo 2"])
    }

    @Test("The summary payload of a meeting record names part, extra pages and its own meetings")
    func summaryPayloadMeeting() throws {
        let handoff = try Self.summaryHandoff(
            part: HandoffPart(number: 2, meetingKey: "meeting:c|e1", title: "Weekly sync"))
        let expected =
            #"{"checksum":"\#(Self.checksum)","date":"2026-10-26","docID":"doc","#
            + #""driveFileID":"file","folderID":"folder","meetings":[{"calendarID":"c","#
            + #""eventID":"e1","extraPages":[3,6],"#
            + #""key":"meeting:c|e1","page":2,"title":"Weekly sync"},{"calendarID":"c","#
            + #""eventID":"e3","key":"meeting:c|e3","page":5,"title":"Planning"}],"pageCount":6,"#
            + #""part":2,"routineID":"id-memo","routineName":"memo","schema":"magenda.summary\/1","#
            + #""scope":"meeting"}"#
        #expect(handoff.summaryPayload(for: Self.routine("memo")) == expected)
    }

    @Test("The summary payload of a day record has scope day and leaves out what is nil")
    func summaryPayloadDay() throws {
        var handoff = try Self.summaryHandoff()
        handoff.driveFileID = nil
        handoff.docID = nil
        handoff.folderID = nil
        handoff.pages = [
            HandoffPage(page: 1, key: "meeting:bare", summaryRoutines: [Self.routine("log")])
        ]
        let expected =
            #"{"checksum":"\#(Self.checksum)","date":"2026-10-26","meetings":[{"key":"meeting:bare","#
            + #""page":1}],"pageCount":1,"routineID":"id-log","routineName":"log","#
            + #""schema":"magenda.summary\/1","scope":"day"}"#
        #expect(handoff.summaryPayload(for: Self.routine("log")) == expected)
        #expect(handoff.summaryPayload(for: Self.routine("other")).contains(#""meetings":[]"#))
    }

    @Test("A summary payload cuts a title to 200 characters")
    func summaryPayloadTitle() throws {
        var handoff = try Self.summaryHandoff()
        handoff.pages = [
            HandoffPage(
                page: 1, key: "meeting:c|e", calendarID: "c", eventID: "e",
                title: String(repeating: "é", count: 300), summaryRoutines: [Self.routine("memo")])
        ]
        let text = handoff.summaryPayload(for: Self.routine("memo"))
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let meetings = try #require(object["meetings"] as? [[String: Any]])
        #expect(meetings[0]["title"] as? String == String(repeating: "é", count: 200))
    }
}
