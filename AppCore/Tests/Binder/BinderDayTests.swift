// AppCore's `BinderDay`: adding and removing pages, the saved format and its version check.

import Foundation
import Testing

@testable import AppCore

@Suite("Binder day")
struct BinderDayTests {
    private func day() throws -> BinderDay {
        BinderDay(
            content: AgendaContent(
                date: try #require(CalendarDay(year: 2026, month: 9, day: 30)), todoItems: [],
                schedule: [], meetings: ["A"], meetingIDs: ["a"], delegated: []),
            theme: Theme())
    }

    @Test("A page added after a base page copies that page and follows it")
    func addAfterBasePage() throws {
        var day = try day()
        day.addPage(after: .meeting("a"), id: "x")
        #expect(day.extras == [ExtraPage(id: "x", after: .meeting("a"), source: .meeting("a"))])
    }

    @Test("A page added after an added page inherits its source and follows it directly")
    func addAfterExtra() throws {
        var day = try day()
        day.addPage(after: .meeting("a"), id: "x")
        day.addPage(after: .overview, id: "o")
        day.addPage(after: .extra("x"), id: "y")
        #expect(
            day.extras == [
                ExtraPage(id: "x", after: .meeting("a"), source: .meeting("a")),
                ExtraPage(id: "o", after: .overview, source: .overview),
                ExtraPage(id: "y", after: .extra("x"), source: .meeting("a")),
            ])
    }

    @Test("A page added after an unknown added page is its own source")
    func addAfterUnknownExtra() throws {
        var day = try day()
        day.addPage(after: .extra("ghost"), id: "y")
        #expect(day.extras == [ExtraPage(id: "y", after: .extra("ghost"), source: .extra("ghost"))])
    }

    @Test("Adding twice after one page puts the second right after it and the first behind")
    func addTwice() throws {
        var day = try day()
        day.addPage(after: .meeting("a"), id: "x")
        day.addPage(after: .meeting("a"), id: "y")
        #expect(
            day.extras == [
                ExtraPage(id: "x", after: .extra("y"), source: .meeting("a")),
                ExtraPage(id: "y", after: .meeting("a"), source: .meeting("a")),
            ])
    }

    @Test("A day survives encoding and decoding")
    func codableRoundTrip() throws {
        var day = try day()
        day.addPage(after: .meeting("a"), id: "x")
        day.retained = [RetainedPage(key: .meeting("old"), content: day.content)]
        let decoded = try JSONDecoder().decode(BinderDay.self, from: JSONEncoder().encode(day))
        #expect(decoded == day)
        #expect(decoded.version == BinderDay.formatVersion)
        #expect(decoded.date == day.content.date)
    }

    @Test("A day saved with another version does not decode")
    func otherVersionThrows() throws {
        let data = try JSONEncoder().encode(try day())
        let text = try #require(String(data: data, encoding: .utf8))
        let changed = text.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
        #expect(changed != text)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BinderDay.self, from: Data(changed.utf8))
        }
    }

    @Test("Removing an added page makes the pages after it follow the page it followed")
    func removePage() throws {
        var day = try day()
        day.addPage(after: .meeting("a"), id: "x")
        day.addPage(after: .extra("x"), id: "y")
        day.removePage(id: "x")
        #expect(day.extras == [ExtraPage(id: "y", after: .meeting("a"), source: .meeting("a"))])
    }

    @Test("Removing an unknown page changes nothing")
    func removeUnknownPage() throws {
        var day = try day()
        day.addPage(after: .meeting("a"), id: "x")
        let before = day.extras
        day.removePage(id: "zz")
        #expect(day.extras == before)
    }

    @Test("A day written without task IDs or summary skills still decodes")
    func decodesWithoutNewKeys() throws {
        var day = try day()
        day.content.todoItems = [TodoItem(text: "a", notes: "", due: "", taskID: "t")]
        day.content.meetingSummarySkills = ["s"]
        let data = try JSONEncoder().encode(day)
        func strip(_ value: Any) -> Any {
            if let object = value as? [String: Any] {
                return object.filter { $0.key != "meetingSummarySkills" && $0.key != "taskID" }
                    .mapValues(strip)
            }
            if let array = value as? [Any] {
                return array.map(strip)
            }
            return value
        }
        let legacy = strip(try JSONSerialization.jsonObject(with: data))
        let decoded = try JSONDecoder().decode(
            BinderDay.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.content.meetingSummarySkills.isEmpty)
        #expect(decoded.content.todoItems.first?.taskID == nil)
        #expect(decoded.content.todoItems.first?.text == "a")
        #expect(decoded.version == BinderDay.formatVersion)
    }

    @Test("Locked pages survive encoding and decoding")
    func lockedRoundTrip() throws {
        var day = try day()
        day.locked = [.meeting("a"), .extra("x")]
        let decoded = try JSONDecoder().decode(BinderDay.self, from: JSONEncoder().encode(day))
        #expect(decoded.locked == [.meeting("a"), .extra("x")])
        #expect(decoded == day)
    }

    @Test("A day written without locked pages decodes with none")
    func decodesWithoutLocked() throws {
        var day = try day()
        day.locked = [.meeting("a")]
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(day)) as? [String: Any])
        object["locked"] = nil
        let decoded = try JSONDecoder().decode(
            BinderDay.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.locked.isEmpty)
    }
}
