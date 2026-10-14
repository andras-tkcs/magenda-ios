// AppCore's agenda content model: cadence labels, to-do items and the delegated-page order.

import AppCore
import Testing

@Suite("Agenda content")
struct AgendaContentTests {
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
}
