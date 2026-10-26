import AppCore
import SwiftUI

/// The binder rules: which events stay off the agenda, how meeting titles are tidied, the short
/// meeting names, the people tasks are matched to, and how far ahead tasks are looked up.
struct RulesView: View {
    /// The lists of plain strings, which share one editor.
    enum ListSection: String, CaseIterable {
        case personalBlocks, titlePrefixes, outOfOfficeWords

        var title: String {
            switch self {
            case .personalBlocks: "Personal blocks"
            case .titlePrefixes: "Title prefixes"
            case .outOfOfficeWords: "Out-of-office words"
            }
        }

        var footnote: String {
            switch self {
            case .personalBlocks:
                "Events whose title starts with one of these are left off the agenda."
            case .titlePrefixes:
                "Removed from the start of meeting-page titles."
            case .outOfOfficeWords:
                "An all-day event with one of these in its title shows a notice."
            }
        }

        var keyPath: WritableKeyPath<BinderRules, [String]> {
            switch self {
            case .personalBlocks: \.personalBlocks
            case .titlePrefixes: \.titlePrefixes
            case .outOfOfficeWords: \.outOfOfficeWords
            }
        }
    }

    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let peopleName = "peopleName"
        static let peopleEmail = "peopleEmail"
        static let peopleAdd = "peopleAdd"
        static let peopleFromContacts = "peopleFromContacts"
        static let summaryTitleField = "summaryTitleField"
        static let summaryAdd = "summaryAdd"
        static let summaryError = "summaryError"
        static let summaryNoRoutines = "summaryNoRoutines"
        static let lookAheadStepper = "lookAheadStepper"
        static let resetRulesButton = "resetRulesButton"
        static let editButton = "rulesEditButton"
        static let deleteAction = "rulesDeleteAction"

        static func row(_ section: String, _ n: Int) -> String { "rulesRow.\(section).\(n)" }
        static func summaryChoice(_ n: Int) -> String { "summaryChoice.\(n)" }
        static func add(_ section: ListSection) -> String { "rulesAdd.\(section.rawValue)" }
    }

    @Environment(AgendaController.self) private var controller
    @Environment(\.contactPicker) private var contactPicker

    @State private var drafts: [ListSection: String] = [:]
    @State private var personName = ""
    @State private var personEmail = ""
    @State private var summaryTitle = ""
    @State private var summaryChoices: Set<String> = []
    @State private var summaryError: String?

    private var rules: BinderRules { controller.settings.rules }

    var body: some View {
        Form {
            ForEach(ListSection.allCases, id: \.self) { section in
                listSection(section)
            }
            shortNamesSection
            summariesSection
            peopleSection
            Section("Look-ahead") {
                Stepper(
                    "Upcoming tasks: \(rules.lookAheadDays) days",
                    value: lookAheadDays, in: 0...14
                )
                .accessibilityIdentifier(ID.lookAheadStepper)
            }
            Section {
                Button("Reset rules") {
                    Task {
                        await controller.updateSettings { settings in
                            var restored = BinderRules.default
                            restored.shortNames = settings.rules.shortNames
                            restored.personAliases = settings.rules.personAliases
                            restored.summaryRoutines = settings.rules.summaryRoutines
                            settings.rules = restored
                        }
                    }
                }
                .accessibilityIdentifier(ID.resetRulesButton)
            }
        }
        .navigationTitle("Binder rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton().accessibilityIdentifier(ID.editButton)
            }
        }
    }

    // MARK: String lists

    private func listSection(_ section: ListSection) -> some View {
        Section {
            let items = rules[keyPath: section.keyPath]
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text(item)
                    .contextMenu {
                        deleteMenu { delete(IndexSet(integer: index), from: section) }
                    }
                    .accessibilityIdentifier(ID.row(section.rawValue, index))
            }
            .onDelete { delete($0, from: section) }
            TextField("Add…", text: draft(section))
                .submitLabel(.done)
                .onSubmit { add(section) }
                .accessibilityIdentifier(ID.add(section))
        } header: {
            Text(section.title)
        } footer: {
            Text(section.footnote)
        }
    }

    private func delete(_ offsets: IndexSet, from section: ListSection) {
        Task {
            await controller.updateSettings {
                $0.rules[keyPath: section.keyPath].remove(atOffsets: offsets)
            }
        }
    }

    /// A long-press menu with Delete, the same as swiping the row away.
    private func deleteMenu(_ delete: @escaping () -> Void) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            .accessibilityIdentifier(ID.deleteAction)
    }

    private func draft(_ section: ListSection) -> Binding<String> {
        Binding(
            get: { drafts[section] ?? "" },
            set: { drafts[section] = $0 })
    }

    /// Appends the draft, trimmed, unless it is blank or already listed once folded.
    private func add(_ section: ListSection) {
        let text = (drafts[section] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        drafts[section] = ""
        let folded = BinderText.fold(text)
        guard !folded.isEmpty else { return }
        Task {
            await controller.updateSettings { settings in
                let existing = settings.rules[keyPath: section.keyPath].map(BinderText.fold)
                if !existing.contains(folded) {
                    settings.rules[keyPath: section.keyPath].append(text)
                }
            }
        }
    }

    // MARK: Short meeting names

    /// The saved short names in a stable order.
    private var shortNameEntries: [(key: String, name: String)] {
        rules.shortNames.map { (key: $0.key, name: $0.value) }
            .sorted { ($0.name, $0.key) < ($1.name, $1.key) }
    }

    private var shortNamesSection: some View {
        let entries = shortNameEntries
        return Section {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                VStack(alignment: .leading) {
                    Text(entry.name)
                    Text(Self.caption(forKey: entry.key))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .contextMenu {
                    deleteMenu { deleteShortNames(IndexSet(integer: index), in: entries) }
                }
                .accessibilityIdentifier(ID.row("shortNames", index))
            }
            .onDelete { deleteShortNames($0, in: entries) }
        } header: {
            Text("Short meeting names")
        } footer: {
            Text("Set from a meeting's Edit sheet.")
        }
    }

    private func deleteShortNames(_ offsets: IndexSet, in entries: [(key: String, name: String)]) {
        let keys = offsets.map { entries[$0].key }
        Task {
            await controller.updateSettings { settings in
                for key in keys { settings.rules.shortNames[key] = nil }
            }
        }
    }

    private static func caption(forKey key: String) -> String {
        key.hasPrefix("r:") ? "Recurring meeting" : String(key.dropFirst(2))
    }

    // MARK: Meeting summaries

    /// The summary rules, sorted by meeting title.
    private var summaryEntries: [(title: String, ids: [String])] {
        rules.summaryRoutines.map { (title: $0.key, ids: $0.value) }
            .sorted { $0.title < $1.title }
    }

    /// The names of the routines `ids` name, in the settings list's order; an ID naming no routine
    /// is left out.
    private func routineNames(_ ids: [String]) -> String {
        let names = controller.settings.summaryRoutines.filter { ids.contains($0.id) }.map(\.name)
        return names.isEmpty ? "(none)" : names.joined(separator: ", ")
    }

    private var summariesSection: some View {
        let entries = summaryEntries
        let routines = controller.settings.summaryRoutines
        return Section {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                Text("\(entry.title) → \(routineNames(entry.ids))")
                    .contextMenu {
                        deleteMenu { deleteSummaries(IndexSet(integer: index), in: entries) }
                    }
                    .accessibilityIdentifier(ID.row("summaries", index))
            }
            .onDelete { deleteSummaries($0, in: entries) }
            TextField("Meeting title", text: $summaryTitle)
                .accessibilityIdentifier(ID.summaryTitleField)
            if routines.isEmpty {
                Text("Add summary routines in Settings first.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(ID.summaryNoRoutines)
            } else {
                ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                    Toggle(routine.name, isOn: summaryChoice(routine.id))
                        .accessibilityIdentifier(ID.summaryChoice(index))
                }
            }
            Button("Add", action: addSummary)
                .accessibilityIdentifier(ID.summaryAdd)
            if let summaryError {
                Text(summaryError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(ID.summaryError)
            }
        } header: {
            Text("Meeting summaries")
        } footer: {
            Text(
                "A meeting whose title matches gets these summary routines. For one meeting, change them on its Edit sheet."
            )
        }
    }

    private func summaryChoice(_ id: String) -> Binding<Bool> {
        Binding(
            get: { summaryChoices.contains(id) },
            set: { isOn in
                if isOn { summaryChoices.insert(id) } else { summaryChoices.remove(id) }
            })
    }

    private func deleteSummaries(
        _ offsets: IndexSet, in entries: [(title: String, ids: [String])]
    ) {
        let titles = offsets.map { entries[$0].title }
        Task {
            await controller.updateSettings { settings in
                for title in titles { settings.rules.summaryRoutines[title] = nil }
            }
        }
    }

    private func addSummary() {
        let routines = controller.settings.summaryRoutines
        guard !routines.isEmpty else { return }
        let title = TextFitter.normalized(summaryTitle)
        guard !title.isEmpty else { return }
        let ids = routines.map(\.id).filter { summaryChoices.contains($0) }
        guard !ids.isEmpty else {
            summaryError = "Choose at least one summary routine."
            return
        }
        let folded = BinderText.fold(title)
        guard !rules.summaryRoutines.keys.contains(where: { BinderText.fold($0) == folded }) else {
            summaryError = "There is already a summary rule for that meeting title."
            return
        }
        summaryError = nil
        summaryTitle = ""
        summaryChoices = []
        Task { await controller.updateSettings { $0.rules.summaryRoutines[title] = ids } }
    }

    // MARK: People

    /// The person aliases in a stable order.
    private var peopleEntries: [(key: String, email: String)] {
        rules.personAliases.map { (key: $0.key, email: $0.value) }.sorted { $0.key < $1.key }
    }

    private var peopleSection: some View {
        let entries = peopleEntries
        return Section {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                Text("\(entry.key) → \(entry.email)")
                    .contextMenu {
                        deleteMenu { deletePeople(IndexSet(integer: index), in: entries) }
                    }
                    .accessibilityIdentifier(ID.row("people", index))
            }
            .onDelete { deletePeople($0, in: entries) }
            TextField("Name in tasks", text: $personName)
                .accessibilityIdentifier(ID.peopleName)
            TextField("Email", text: $personEmail)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier(ID.peopleEmail)
            if let contactPicker {
                Button("Choose from Contacts…") {
                    Task {
                        guard let picked = await contactPicker.pickContact() else { return }
                        personName = picked.suggestedName
                        personEmail = picked.email
                    }
                }
                .accessibilityIdentifier(ID.peopleFromContacts)
            }
            Button("Add", action: addPerson)
                .accessibilityIdentifier(ID.peopleAdd)
        } header: {
            Text("People")
        } footer: {
            Text(
                "Matches “Name – to be discussed” tasks to meeting attendees whose first name differs. Choose from Contacts fills in a name and email you can still change."
            )
        }
    }

    private func deletePeople(_ offsets: IndexSet, in entries: [(key: String, email: String)]) {
        let keys = offsets.map { entries[$0].key }
        Task {
            await controller.updateSettings { settings in
                for key in keys { settings.rules.personAliases[key] = nil }
            }
        }
    }

    private func addPerson() {
        guard let alias = PersonAlias(name: personName, email: personEmail) else { return }
        personName = ""
        personEmail = ""
        Task { await controller.updateSettings { $0.rules.personAliases[alias.key] = alias.email } }
    }

    // MARK: Look-ahead

    private var lookAheadDays: Binding<Int> {
        Binding(
            get: { min(max(rules.lookAheadDays, 0), 14) },
            set: { days in
                Task { await controller.updateSettings { $0.rules.lookAheadDays = days } }
            })
    }
}

#Preview {
    if let controller = AppEnvironment.previewController() {
        NavigationStack { RulesView() }
            .environment(controller)
            .environment(\.contactPicker, FixtureContactPicker())
            .task { await controller.start() }
    }
}
