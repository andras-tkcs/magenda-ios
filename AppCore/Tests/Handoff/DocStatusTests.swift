// AppCore's `DocStatus`: reading the Doc's first line, and the line a new Doc starts with.

import Testing

@testable import AppCore

@Suite("Doc status")
struct DocStatusTests {
    @Test(
        "The first non-empty line decides the status",
        arguments: [
            ("Status: Waiting for notes\n", DocStatus.waitingForNotes),
            ("Status: Notes ready for review\nThe notes.", .notesReady),
            ("Status: Summary ready for review", .summaryReady),
            ("Status: Closed", .closed),
            ("\u{FEFF}Status: Closed\n", .closed),
            ("\n\n  \r\n  Status: Notes ready for review\n", .notesReady),
            ("status: closed", .closed),
            ("STATUS: SUMMARY READY FOR REVIEW", .summaryReady),
            ("  Status:    Waiting for notes   \r\nbody", .waitingForNotes),
            ("Status:Closed", .closed),
            ("Status: Done", .unknown),
            ("Status:", .unknown),
            ("Status: Closed soon", .unknown),
            ("Status: Waiting  for notes", .unknown),
            ("Notes\nStatus: Closed", .unknown),
            ("Statu: Closed", .unknown),
            ("", .unknown),
            ("\n \n", .unknown),
        ])
    func parse(text: String, expected: DocStatus) {
        #expect(DocStatus.parse(text) == expected)
    }

    @Test("The text a new Doc starts with reads as waiting for notes")
    func initialText() {
        #expect(DocStatus.initialDocText == "Status: Waiting for notes\n")
        #expect(DocStatus.parse(DocStatus.initialDocText) == .waitingForNotes)
    }

    @Test("Routine steps use the names the routine knows")
    func stepNames() {
        #expect(RoutineStep.notes.rawValue == "notes")
        #expect(RoutineStep.approveNotes.rawValue == "approve-notes")
        #expect(RoutineStep.approveSummary.rawValue == "approve-summary")
    }
}
