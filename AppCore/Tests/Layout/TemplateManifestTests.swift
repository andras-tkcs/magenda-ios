// AppCore's `TemplateManifest`, decoded from the bundled `slots.json` and from small documents.

import AppCore
import Foundation
import Testing

@Suite("Template manifest")
struct TemplateManifestTests {
    private func document(role: String) -> Data {
        Data(
            """
            {
              "page_width": 100, "page_height": 200,
              "header_slots": [
                {"id": "h", "rect": [1, 2, 3, 4], "role": "\(role)", "weight": "thin",
                 "size_half_points": 20, "align": "left", "text": null}
              ],
              "page_slots": {"overview": []},
              "delegated": {"table_top_left": [5, 6], "row_overhead_twips": 100}
            }
            """.utf8)
    }

    @Test("The bundled manifest decodes with the template's geometry")
    func bundled() throws {
        let manifest = try TemplateManifest.bundled()
        #expect(abs(manifest.pageWidth - 595.304) < 0.001)
        #expect(abs(manifest.pageHeight - 841.890) < 0.001)
        #expect(manifest.headerSlots.count == 20)
        #expect(manifest.pageSlots["overview"]?.count == 101)
        #expect(manifest.pageSlots["delegated_shell"]?.count == 4)
        #expect(manifest.pageSlots["meeting_unit"]?.count == 2)
        #expect(manifest.pageSlots["further_notes"]?.count == 1)
        #expect(abs(manifest.delegatedRowOverhead - 49.8) < 0.001)
        #expect(abs(manifest.delegatedTableTopLeft.x - 56.796) < 0.001)
        #expect(abs(manifest.delegatedTableTopLeft.y - 129.5008) < 0.001)
    }

    @Test("Slots are found by identifier in the header and on pages")
    func slotLookup() throws {
        let manifest = try TemplateManifest.bundled()
        #expect(manifest.slot("todo.label")?.text == "TO-DO LIST")
        #expect(manifest.slot("todo.label")?.points == 18)
        #expect(manifest.slot("header.cw")?.text == nil)
        #expect(manifest.slot("header.cw")?.role == .heading)
        #expect(manifest.slot("no.such.slot") == nil)
    }

    @Test("A small document decodes into its parts")
    func smallDocument() throws {
        let manifest = try TemplateManifest(data: document(role: "notes"))
        #expect(manifest.pageWidth == 100)
        #expect(manifest.pageHeight == 200)
        #expect(manifest.delegatedRowOverhead == 5)
        #expect(manifest.delegatedTableTopLeft == PlanPoint(x: 5, y: 6))
        #expect(
            manifest.slot("h")
                == TemplateSlot(
                    id: "h", rect: PlanRect(x0: 1, y0: 2, x1: 3, y1: 4), role: .notes,
                    weight: .thin, sizeHalfPoints: 20, align: "left", text: nil))
    }

    @Test("An empty object and an unknown role are malformed")
    func malformed() {
        #expect(throws: TemplateError.malformed) { try TemplateManifest(data: Data("{}".utf8)) }
        #expect(throws: TemplateError.malformed) {
            try TemplateManifest(data: document(role: "purple"))
        }
    }

    @Test("A nil or unreadable URL is missing")
    func missing() {
        #expect(throws: TemplateError.missing) { try TemplateManifest(contentsOf: nil) }
        let absent = URL(fileURLWithPath: "/nonexistent/magenda/slots.json")
        #expect(throws: TemplateError.missing) { try TemplateManifest(contentsOf: absent) }
    }

    @Test("A readable file decodes")
    func readsFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifest-\(UUID().uuidString).json")
        try document(role: "body").write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try TemplateManifest(contentsOf: url).headerSlots.count == 1)
    }
}
