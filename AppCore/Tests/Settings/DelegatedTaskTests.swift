// AppCore's delegated-task parser.

import AppCore
import Foundation
import Testing

@Suite("Delegated tasks")
struct DelegatedTaskTests {
    private let ownerWarning = "No “Owner: Task” title — shown without an owner."
    private let cadenceWarning =
        "No #daily, #weekly or #monthly on the first line — shown as Daily."

    @Test("The example task keeps its last two log lines")
    func example() {
        let notes = """
            #weekly
            2026-08-13 Delegated to Sam.
            2026-08-20 Followed up — waiting on their lawyer.
            2026-08-27 Countersigned copy received, filing pending.
            """
        let task = DelegatedTask.parse(
            title: "Sam: Countersign the supplier agreement", notes: notes)
        #expect(task.owner == "Sam")
        #expect(task.text == "Countersign the supplier agreement")
        #expect(task.cadence == .weekly)
        #expect(
            task.status == [
                "2026-08-20 Followed up — waiting on their lawyer.",
                "2026-08-27 Countersigned copy received, filing pending.",
            ])
        #expect(task.warning == nil)
    }

    @Test("One log line and no log lines")
    func fewLines() {
        #expect(
            DelegatedTask.parse(title: "A: B", notes: "#daily\n\n  one  \n").status == ["one"])
        #expect(DelegatedTask.parse(title: "A: B", notes: "#monthly").status.isEmpty)
        #expect(DelegatedTask.parse(title: "A: B", notes: "#monthly").cadence == .monthly)
    }

    @Test("The cadence tag is case-insensitive")
    func cadenceCase() {
        #expect(DelegatedTask.parse(title: "A: B", notes: "#Weekly\nlog").cadence == .weekly)
    }

    @Test("Without a cadence line the first line counts as log")
    func noCadence() {
        let task = DelegatedTask.parse(title: "A: B", notes: "first\nsecond\nthird")
        #expect(task.cadence == .daily)
        #expect(task.status == ["second", "third"])
        #expect(task.warning == cadenceWarning)
    }

    @Test("A title without an owner and task keeps the whole title")
    func badTitles() {
        for title in ["Fix the printer", ": Task", "Owner:", "Owner:  "] {
            let task = DelegatedTask.parse(title: title, notes: "#daily")
            #expect(task.owner == "")
            #expect(task.text == title.trimmingCharacters(in: .whitespaces))
            #expect(task.warning == ownerWarning)
        }
    }

    @Test("Only the first colon splits the title")
    func twoColons() {
        let task = DelegatedTask.parse(title: "Anna: Fix: the printer", notes: "#daily")
        #expect(task.owner == "Anna")
        #expect(task.text == "Fix: the printer")
    }

    @Test("Both warnings are joined with one space, also for nil input")
    func bothWarnings() {
        let task = DelegatedTask.parse(title: nil, notes: nil)
        #expect(task.owner == "")
        #expect(task.text == "")
        #expect(task.status.isEmpty)
        #expect(task.warning == ownerWarning + " " + cadenceWarning)
    }
}
