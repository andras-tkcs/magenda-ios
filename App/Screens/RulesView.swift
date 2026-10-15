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
        static let lookAheadStepper = "lookAheadStepper"
        static let resetRulesButton = "resetRulesButton"

        static func row(_ section: String, _ n: Int) -> String { "rulesRow.\(section).\(n)" }
        static func add(_ section: ListSection) -> String { "rulesAdd.\(section.rawValue)" }
    }

    @Environment(AgendaController.self) private var controller

    @State private var drafts: [ListSection: String] = [:]
    @State private var personName = ""
    @State private var personEmail = ""

    private var rules: BinderRules { controller.settings.rules }

    var body: some View {
        Form {
            ForEach(ListSection.allCases, id: \.self) { section in
                listSection(section)
            }
            shortNamesSection
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
                            settings.rules = restored
                        }
                    }
                }
                .accessibilityIdentifier(ID.resetRulesButton)
            }
        }
        .navigationTitle("Binder rules")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: String lists

    private func listSection(_ section: ListSection) -> some View {
        Section {
            let items = rules[keyPath: section.keyPath]
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text(item)
                    .accessibilityIdentifier(ID.row(section.rawValue, index))
            }
            .onDelete { offsets in
                Task {
                    await controller.updateSettings {
                        $0.rules[keyPath: section.keyPath].remove(atOffsets: offsets)
                    }
                }
            }
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
                .accessibilityIdentifier(ID.row("shortNames", index))
            }
            .onDelete { offsets in
                let keys = offsets.map { entries[$0].key }
                Task {
                    await controller.updateSettings { settings in
                        for key in keys { settings.rules.shortNames[key] = nil }
                    }
                }
            }
        } header: {
            Text("Short meeting names")
        } footer: {
            Text("Set from a meeting's Edit sheet.")
        }
    }

    private static func caption(forKey key: String) -> String {
        key.hasPrefix("r:") ? "Recurring meeting" : String(key.dropFirst(2))
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
                    .accessibilityIdentifier(ID.row("people", index))
            }
            .onDelete { offsets in
                let keys = offsets.map { entries[$0].key }
                Task {
                    await controller.updateSettings { settings in
                        for key in keys { settings.rules.personAliases[key] = nil }
                    }
                }
            }
            TextField("Name in tasks", text: $personName)
                .accessibilityIdentifier(ID.peopleName)
            TextField("Email", text: $personEmail)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier(ID.peopleEmail)
            Button("Add", action: addPerson)
                .accessibilityIdentifier(ID.peopleAdd)
        } header: {
            Text("People")
        } footer: {
            Text(
                "Matches “Name – to be discussed” tasks to meeting attendees whose first name differs."
            )
        }
    }

    private func addPerson() {
        let key = BinderText.fold(personName.trimmingCharacters(in: .whitespacesAndNewlines))
        let email = personEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, !email.isEmpty else { return }
        personName = ""
        personEmail = ""
        Task { await controller.updateSettings { $0.rules.personAliases[key] = email } }
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
            .task { await controller.start() }
    }
}
