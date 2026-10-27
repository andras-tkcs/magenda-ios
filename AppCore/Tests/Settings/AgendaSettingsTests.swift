// AppCore's agenda settings, binder rule defaults and settings store.

import AppCore
import Foundation
import Testing

@Suite("Agenda settings")
struct AgendaSettingsTests {
    private func decode(_ json: String) throws -> AgendaSettings {
        try JSONDecoder().decode(AgendaSettings.self, from: Data(json.utf8))
    }

    @Test("A fresh install uses the skill's list titles and the default rules")
    func defaults() {
        let settings = AgendaSettings()
        #expect(settings.fontPack == .outfit)
        #expect(settings.colors == .default)
        #expect(settings.calendarIDs.isEmpty)
        #expect(settings.todoListTitle == "Claude")
        #expect(settings.delegatedListTitle == "Claude Delegations")
        #expect(settings.rules == BinderRules.default)
        #expect(settings.driveFolderName == "Magenda")
    }

    @Test("The default rules")
    func defaultRules() {
        let rules = BinderRules.default
        #expect(rules.personalBlocks == ["Lunch", "Start the day"])
        let prefixes: [String] = [
            "REMINDER //", "REMINDER:", "(temp)", "FW:", "Fwd:", "CONDITIONAL", "weekly",
        ]
        #expect(rules.titlePrefixes == prefixes)
        #expect(rules.outOfOfficeWords == ["OOO", "Out of Office", "Vacation", "PTO"])
        #expect(rules.shortNames.isEmpty)
        #expect(rules.personAliases.isEmpty)
        #expect(rules.lookAheadDays == 5)
    }

    @Test("Settings survive a JSON round trip")
    func roundTrip() throws {
        var settings = AgendaSettings()
        settings.fontPack = .jetbrainsMono
        settings.colors.heading = RGBColor(red: 1, green: 2, blue: 3)
        settings.calendarIDs = ["a@example.com", "b@example.com"]
        settings.todoListTitle = "Mine"
        settings.delegatedListTitle = ""
        settings.driveFolderName = "Work notes"
        settings.rules = BinderRules(
            personalBlocks: ["Gym"], titlePrefixes: ["RE:"], outOfOfficeWords: ["Leave"],
            shortNames: ["r:abc": "Weekly sync"], personAliases: ["peter": "peter@example.com"],
            lookAheadDays: 3)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AgendaSettings.self, from: data) == settings)
    }

    @Test("A missing or invalid Drive folder name decodes as Magenda")
    func driveFolderNameDecoding() throws {
        #expect(try decode("{}").driveFolderName == "Magenda")
        #expect(try decode(#"{"driveFolderName":"Work notes"}"#).driveFolderName == "Work notes")
        #expect(try decode(#"{"driveFolderName":"a/b"}"#).driveFolderName == "Magenda")
    }

    @Test("An unknown font pack decodes as Outfit")
    func unknownFontPack() throws {
        #expect(try decode(#"{"fontPack":"comic_sans"}"#).fontPack == .outfit)
    }

    @Test("A single field decodes with every other default")
    func partialSettings() throws {
        var expected = AgendaSettings()
        expected.todoListTitle = "x"
        #expect(try decode(#"{"todoListTitle":"x"}"#) == expected)
        #expect(try decode("{}") == AgendaSettings())
    }

    @Test("A rules object with one field keeps the other rule defaults")
    func partialRules() throws {
        let settings = try decode(#"{"rules":{"lookAheadDays":3}}"#)
        var expected = BinderRules.default
        expected.lookAheadDays = 3
        #expect(settings.rules == expected)
        #expect(try decode(#"{"rules":{}}"#).rules == BinderRules.default)
    }

    @Test("The theme mirrors the font pack and colors")
    func theme() {
        var settings = AgendaSettings()
        settings.fontPack = .roboto
        settings.colors.notes = RGBColor(red: 9, green: 8, blue: 7)
        #expect(settings.theme == Theme(fontPack: .roboto, colors: settings.colors))
    }

    @Test("The in-memory store returns what was saved")
    func inMemoryStore() {
        let store = InMemorySettingsStore()
        #expect(store.load() == AgendaSettings())
        var changed = AgendaSettings()
        changed.todoListTitle = "Other"
        store.save(changed)
        #expect(store.load() == changed)
        #expect(InMemorySettingsStore(changed).load() == changed)
    }

    @Test("An old summarySkills key is ignored and summaryRoutines decodes")
    func oldSummarySkillsIgnored() throws {
        let old = try decode(#"{"rules":{"summarySkills":{"Sync":"s"}}}"#)
        #expect(old.rules.summaryRoutines == [:])
        let settings = try decode(
            #"{"rules":{"summarySkills":{"Sync":"s"},"summaryRoutines":{"Sync":["a"]}}}"#)
        #expect(settings.rules.summaryRoutines == ["Sync": ["a"]])
    }

    @Test("A fresh install has no summary routines and no routine rules")
    func summaryRoutinesDefault() {
        #expect(AgendaSettings().summaryRoutines.isEmpty)
        #expect(BinderRules.default.summaryRoutines == [:])
    }

    @Test("Settings and rules without summary routines decode with none")
    func summaryRoutinesDecoding() throws {
        #expect(try decode("{}").summaryRoutines.isEmpty)
        #expect(try decode(#"{"rules":{"lookAheadDays":3}}"#).rules.summaryRoutines == [:])
        let settings = try decode(
            #"{"summaryRoutines":[{"id":"a","name":"Recap"}],"rules":{"summaryRoutines":{"Sync":["a"]}}}"#
        )
        #expect(settings.summaryRoutines == [SummaryRoutine(id: "a", name: "Recap")])
        #expect(settings.rules.summaryRoutines == ["Sync": ["a"]])
    }

    @Test("A routine is found by its folded name")
    func summaryRoutineNamed() {
        let recap = SummaryRoutine(id: "a", name: "Weekly Récap")
        let settings = AgendaSettings(summaryRoutines: [recap])
        #expect(settings.summaryRoutine(named: "weekly recap") == recap)
        #expect(settings.summaryRoutine(named: "other") == nil)
    }

    @Test("Removing a routine prunes the rules and drops an emptied entry")
    func removeSummaryRoutine() {
        var settings = AgendaSettings(
            rules: BinderRules(
                personalBlocks: [], titlePrefixes: [], outOfOfficeWords: [], shortNames: [:],
                personAliases: [:], lookAheadDays: 5,
                summaryRoutines: ["Sync": ["a", "b"], "Retro": ["a"]]),
            summaryRoutines: [
                SummaryRoutine(id: "a", name: "A"), SummaryRoutine(id: "b", name: "B"),
            ])
        settings.removeSummaryRoutine(id: "a")
        #expect(settings.summaryRoutines == [SummaryRoutine(id: "b", name: "B")])
        #expect(settings.rules.summaryRoutines == ["Sync": ["b"]])
    }
}
