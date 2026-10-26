// AppCore's fixture Drive and routine trigger: the Doc status each fired step leaves behind.

import Foundation
import Testing

@testable import AppCore

private let goodURL = "https://api.anthropic.com/v1/claude_code/routines/trig_abc123/fire"
private let goodToken = "sk-ant-oat01-abc_DEF-123"

private func payload(
    step: String, skill: String? = nil, date: String = "2026-03-02", part: Int? = nil,
    earlierPart: Int? = nil
) -> String {
    let skillField = skill.map { #","summarySkill":"\#($0)""# } ?? ""
    let earlierField = earlierPart.map { #","earlierPart":\#($0)"# } ?? ""
    let partField = part.map { #","part":\#($0)"# } ?? ""
    let page = #"{"page":1,"key":"m"\#(skillField)\#(earlierField)}"#
    return #"{"date":"\#(date)","pages":[\#(page)],"step":"\#(step)"\#(partField)}"#
}

private func rig(configured: Bool = true) -> (FixtureDrive, FixtureRoutineTrigger) {
    let state = FixtureEndOfDay()
    let credentials = InMemoryRoutineCredentialsStore(
        configured ? RoutineCredentials(fireURL: goodURL, token: goodToken) : nil)
    return (
        FixtureDrive(state: state),
        FixtureRoutineTrigger(state: state, credentials: credentials)
    )
}

private func status(_ drive: FixtureDrive, date: String = "2026-03-02") async throws -> DocStatus {
    DocStatus.parse(try await drive.exportText(ofDoc: "doc-" + date))
}

private func partStatus(
    _ drive: FixtureDrive, date: String = "2026-03-02", part: Int
) async throws -> DocStatus {
    try await status(drive, date: "\(date)-part-\(part)")
}

@Suite("Handoff fixtures")
struct HandoffFixturesTests {
    @Test("A day without a skill goes waiting, notes ready, closed")
    func withoutSkill() async throws {
        let (drive, trigger) = rig()
        #expect(try await status(drive) == .waitingForNotes)
        _ = try await trigger.fire(text: payload(step: "notes"))
        #expect(try await status(drive) == .notesReady)
        _ = try await trigger.fire(text: payload(step: "approve-notes"))
        #expect(try await status(drive) == .closed)
    }

    @Test("A day with a skill goes through summary ready before closed")
    func withSkill() async throws {
        let (drive, trigger) = rig()
        _ = try await trigger.fire(text: payload(step: "notes", skill: "weekly-sync"))
        #expect(try await status(drive) == .notesReady)
        _ = try await trigger.fire(text: payload(step: "approve-notes", skill: "weekly-sync"))
        #expect(try await status(drive) == .summaryReady)
        _ = try await trigger.fire(text: payload(step: "approve-summary", skill: "weekly-sync"))
        #expect(try await status(drive) == .closed)
    }

    @Test("Days are tracked separately")
    func perDate() async throws {
        let (drive, trigger) = rig()
        _ = try await trigger.fire(text: payload(step: "notes"))
        #expect(try await status(drive, date: "2026-03-03") == .waitingForNotes)
    }

    @Test("The drive returns fixed IDs built from the date")
    func ids() async throws {
        let (drive, _) = rig()
        #expect(try await drive.folderID(named: "Magenda") == "folder-1")
        let file = try await drive.uploadPDF(
            Data(), name: "Magenda 2026-03-02.pdf", folderID: "folder-1", replacing: nil)
        #expect(file == "file-2026-03-02")
        let doc = try await drive.createDoc(
            name: "Magenda 2026-03-02 notes", folderID: "folder-1", text: "x")
        #expect(doc == "doc-2026-03-02")
    }

    @Test("The drive names a part's file and Doc after the date and the part")
    func partIDs() async throws {
        let (drive, _) = rig()
        let file = try await drive.uploadPDF(
            Data(), name: "Magenda 2026-03-02 part 12.pdf", folderID: "folder-1", replacing: nil)
        #expect(file == "file-2026-03-02-part-12")
        let doc = try await drive.createDoc(
            name: "Magenda 2026-03-02 part 1 notes", folderID: "folder-1", text: "x")
        #expect(doc == "doc-2026-03-02-part-1")
    }

    @Test("A meeting run is tracked apart from the day and from other parts")
    func perPart() async throws {
        let (drive, trigger) = rig()
        _ = try await trigger.fire(text: payload(step: "notes", part: 1))
        #expect(try await partStatus(drive, part: 1) == .notesReady)
        #expect(try await partStatus(drive, part: 2) == .waitingForNotes)
        #expect(try await status(drive) == .waitingForNotes)
        _ = try await trigger.fire(text: payload(step: "notes"))
        _ = try await trigger.fire(text: payload(step: "approve-notes", part: 1))
        #expect(try await partStatus(drive, part: 1) == .closed)
        #expect(try await status(drive) == .notesReady)
    }

    @Test("A meeting with a skill goes through summary ready before closed")
    func partWithSkill() async throws {
        let (drive, trigger) = rig()
        _ = try await trigger.fire(
            text: payload(step: "approve-notes", skill: "weekly-sync", part: 1))
        #expect(try await partStatus(drive, part: 1) == .summaryReady)
    }

    @Test("A page that an earlier part sent does not make a day have a summary skill")
    func earlierPartIgnored() async throws {
        let (drive, trigger) = rig()
        _ = try await trigger.fire(
            text: payload(step: "approve-notes", skill: "weekly-sync", earlierPart: 1))
        #expect(try await status(drive) == .closed)
    }

    @Test("The trigger returns the fixture session URL")
    func sessionURL() async throws {
        let (_, trigger) = rig()
        #expect(trigger.isConfigured())
        let url = try await trigger.fire(text: payload(step: "notes"))
        #expect(url.absoluteString == "https://claude.ai/code/session_fixture")
    }

    @Test("Without credentials the trigger is not configured and fire throws")
    func notConfigured() async throws {
        let (drive, trigger) = rig(configured: false)
        #expect(!trigger.isConfigured())
        await #expect(throws: RoutineTriggerError.notConfigured) {
            _ = try await trigger.fire(text: payload(step: "notes"))
        }
        #expect(try await status(drive) == .waitingForNotes)
    }

    @Test("The credentials are read on every call")
    func readsEveryCall() async throws {
        let state = FixtureEndOfDay()
        let credentials = InMemoryRoutineCredentialsStore()
        let trigger = FixtureRoutineTrigger(state: state, credentials: credentials)
        #expect(!trigger.isConfigured())
        credentials.save(try #require(RoutineCredentials(fireURL: goodURL, token: goodToken)))
        #expect(trigger.isConfigured())
    }

    @Test("A store that cannot be read counts as no routine")
    func brokenStore() {
        struct Broken: RoutineCredentialsStore {
            struct Failure: Error {}
            func load() throws -> RoutineCredentials? { throw Failure() }
            func save(_ credentials: RoutineCredentials) throws {}
            func delete() throws {}
        }
        let trigger = FixtureRoutineTrigger(state: FixtureEndOfDay(), credentials: Broken())
        #expect(!trigger.isConfigured())
    }

    @Test("A payload that does not decode leaves the status at waiting")
    func undecodable() async throws {
        let (drive, trigger) = rig()
        _ = try await trigger.fire(text: "not json")
        #expect(try await status(drive) == .waitingForNotes)
    }

    @Test("An unknown step leaves the status at waiting")
    func unknownStep() async throws {
        let (drive, trigger) = rig()
        _ = try await trigger.fire(text: payload(step: "other"))
        #expect(try await status(drive) == .waitingForNotes)
    }
}
