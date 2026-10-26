// AppCore's `DocStatus`: reading the Doc's first line, and the line a new Doc starts with.

import Foundation
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

    @Test("The close step uses the name the routine knows")
    func closeStepName() {
        #expect(RoutineStep.close.rawValue == "close")
    }

    @Test("An unknown raw status decodes to unknown, a known one to itself")
    func decodesUnknownRaw() throws {
        func decode(_ raw: String) throws -> DocStatus {
            try JSONDecoder().decode(DocStatus.self, from: Data(#""\#(raw)""#.utf8))
        }
        #expect(try decode("somethingNew") == .unknown)
        #expect(try decode("summaryReady") == .summaryReady)
        #expect(try decode("closed") == .closed)
        let encoded = try JSONEncoder().encode(DocStatus.notesReady)
        #expect(String(decoding: encoded, as: UTF8.self) == #""notesReady""#)
    }

    private static let idA = "11111111-1111-4111-8111-111111111111"
    private static let idB = "22222222-2222-4222-8222-222222222222"
    private static let status = "Status: Notes ready for review\n"

    struct MarkerCase: Sendable {
        let text: String
        let expected: [String]

        init(_ text: String, _ expected: [String]) {
            self.text = text
            self.expected = expected
        }
    }

    private static let markerCases: [MarkerCase] = [
        MarkerCase("Status: Closed\nSummary ready: \(idA) 2", ["\(idA) 2"]),
        MarkerCase("Status: Closed\nsummary READY: \(idA.uppercased()) 12", ["\(idA) 12"]),
        MarkerCase("Status: Closed\n\t Summary ready: \(idA) 3 \t\n", ["\(idA) 3"]),
        MarkerCase("Status: Closed\r\nSummary ready: \(idA) 3\r\n", ["\(idA) 3"]),
        MarkerCase("Status: Closed\nSummary ready:  \(idA) 2", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA)  2", []),
        MarkerCase("Status: Closed\nSummary ready:\(idA) 2", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA)\t2", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA) 0", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA) 01", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA) 10000", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA) 9999", ["\(idA) 9999"]),
        MarkerCase("Status: Closed\nSummary ready: \(idA) 1000", ["\(idA) 1000"]),
        MarkerCase("Status: Closed\nSummary ready: \(idA) ", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA)", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA) 1x", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA) -1", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA) 1 2", []),
        MarkerCase("Status: Closed\nSummary ready: not-an-id 2", []),
        MarkerCase(
            "Status: Closed\nSummary ready: 11111111-1111-4111-8111-11111111111g 2", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA)x 2", []),
        MarkerCase("Status: Closed\nSummary ready \(idA) 2", []),
        MarkerCase("Status: Closed\nSummary ready: \(idA) 2 done", []),
        MarkerCase("Status: Closed\n- Summary ready: \(idA) 2", []),
        MarkerCase(
            "Status: Closed\nSummary ready: \(idA) 2\nSummary ready: \(idA) 2", ["\(idA) 2"]),
        MarkerCase(
            "Status: Closed\nSummary ready: \(idB) 4\nText\nSummary ready: \(idA) 2\n"
                + "Summary ready: \(idA) 4\nSummary ready: \(idB) 4",
            ["\(idB) 4", "\(idA) 2", "\(idA) 4"]
        ),
        MarkerCase("\u{FEFF}Status: Closed\nSummary ready: \(idA) 2", ["\(idA) 2"]),
        MarkerCase(
            "\n \n\u{FEFF}Summary ready: \(idA) 1\nSummary ready: \(idB) 1", ["\(idB) 1"]),
        MarkerCase("Summary ready: \(idA) 2", []),
        MarkerCase("", []),
        MarkerCase("\n \n", []),
    ]

    @Test("Summary markers follow the grammar", arguments: markerCases)
    func markers(_ item: MarkerCase) {
        #expect(DocStatus.summaryMarkers(in: item.text) == item.expected)
    }

    @Test("A marker does not change the status read from the first line")
    func markerBelowStatus() {
        let text = Self.status + "Summary ready: \(Self.idA) 2\nFixture summary.\n"
        #expect(DocStatus.parse(text) == .notesReady)
        #expect(DocStatus.summaryMarkers(in: text) == ["\(Self.idA) 2"])
    }
}
