// AppCore's agenda content model: cadence labels, to-do items and the delegated-page order.

import AppCore
import Foundation
import Testing

@Suite("Agenda content")
struct AgendaContentTests {
    @Test(
        "Content survives a JSON round trip",
        arguments: [AgendaContentFixtures.typical, AgendaContentFixtures.longText])
    func codable(_ content: AgendaContent) throws {
        let data = try JSONEncoder().encode(content)
        #expect(try JSONDecoder().decode(AgendaContent.self, from: data) == content)
    }

    @Test("Meeting IDs default to none and are kept")
    func meetingIDs() throws {
        let date = try #require(CalendarDay(year: 2026, month: 10, day: 1))
        let plain = AgendaContent(
            date: date, todoItems: [], schedule: [], meetings: ["A"], delegated: [])
        #expect(plain.meetingIDs.isEmpty)
        let keyed = AgendaContent(
            date: date, todoItems: [], schedule: [], meetings: ["A"], meetingIDs: ["x"],
            delegated: [])
        #expect(keyed.meetingIDs == ["x"])
    }

    @Test("Cadences have display labels")
    func cadenceLabels() {
        #expect(Cadence.allCases.map(\.label) == ["Daily", "Weekly", "Monthly"])
        #expect(Cadence(rawValue: "weekly") == .weekly)
    }

    @Test("A to-do item keeps its text, notes and due date")
    func todoItem() {
        let item = TodoItem(text: "Call", notes: "bring files", due: "10/02")
        #expect(item.text == "Call")
        #expect(item.notes == "bring files")
        #expect(item.due == "10/02")
    }

    @Test("Content keeps what it is built from")
    func contentKeepsParts() throws {
        let date = try #require(CalendarDay(year: 2026, month: 10, day: 1))
        let entry = ScheduleEntry(slot: 2, text: "Standup", meetingIndex: 0)
        let content = AgendaContent(
            date: date, todoItems: [], schedule: [entry], meetings: ["Standup"], delegated: [])
        #expect(content.schedule == [entry])
        #expect(content.meetings == ["Standup"])
        #expect(content.date == date)
    }

    private func item(_ text: String, _ cadence: Cadence, marked: Bool) -> DelegatedItem {
        DelegatedItem(text: text, owner: "Ada", cadence: cadence, marked: marked, status: [])
    }

    @Test("Delegated rows sort marked first, then by cadence")
    func sortedForPage() {
        let input = [
            item("a", .monthly, marked: false),
            item("b", .daily, marked: false),
            item("c", .weekly, marked: true),
            item("d", .daily, marked: true),
            item("e", .weekly, marked: false),
        ]
        #expect(input.sortedForPage().map(\.text) == ["d", "c", "b", "e", "a"])
    }

    @Test("Sorting keeps input order inside a group")
    func sortedForPageIsStable() {
        let input = ["z", "y", "x", "w"].map { item($0, .weekly, marked: true) }
        #expect(input.sortedForPage().map(\.text) == ["z", "y", "x", "w"])
    }

    @Test("Content written without task IDs or summary routines still decodes")
    func legacyJSON() throws {
        let data = try JSONEncoder().encode(AgendaContentFixtures.typical)
        var legacy = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy["meetingSummaryRoutines"] = nil
        legacy["meetingSummarySkills"] = ["old-skill"]
        let decoded = try JSONDecoder().decode(
            AgendaContent.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.meetingSummaryRoutines.isEmpty)
        var expected = AgendaContentFixtures.typical
        expected.meetingSummaryRoutines = []
        #expect(decoded == expected)
        let todo = try JSONDecoder().decode(
            TodoItem.self, from: Data(#"{"text":"a","notes":"","due":""}"#.utf8))
        #expect(todo.taskID == nil)
        let delegated = try JSONDecoder().decode(
            DelegatedItem.self,
            from: Data(
                #"{"text":"a","owner":"b","cadence":"daily","marked":false,"status":[]}"#.utf8))
        #expect(delegated.taskID == nil)
    }
}
