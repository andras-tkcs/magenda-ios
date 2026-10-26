import AppCore
import SwiftUI

/// What the edit sheet is changing: one row of the review list, by its draft id.
enum EditTarget: Identifiable, Equatable {
    case event(String)
    case task(String)
    case delegated(String)

    var id: String {
        switch self {
        case .event(let id): "event.\(id)"
        case .task(let id): "task.\(id)"
        case .delegated(let id): "delegated.\(id)"
        }
    }
}

/// Edits the text of one event's meeting-page title, task or delegated task. Changes only affect
/// the agenda being made; nothing is written to Google.
struct EditTextSheet: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let field = "editField"
        static let remember = "editRemember"
        static let done = "editDone"
        static let cancel = "editCancel"

        static func summaryToggle(_ n: Int) -> String { "editSummary.\(n)" }
    }

    let target: EditTarget
    /// The calendar title, for an event.
    let originalTitle: String?
    /// The summary routines the person set up, offered as checkboxes for an event.
    let summaryRoutines: [SummaryRoutine]

    @Environment(AgendaController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var remember = false
    @State private var chosen: Set<String>

    init(
        target: EditTarget, text: String, originalTitle: String?,
        summaryRoutines: [SummaryRoutine] = [], selectedRoutineIDs: [String] = []
    ) {
        self.target = target
        self.originalTitle = originalTitle
        self.summaryRoutines = summaryRoutines
        _text = State(initialValue: text)
        _chosen = State(initialValue: Set(selectedRoutineIDs))
    }

    private var footer: String {
        remember
            ? "Saved in Settings → Short meeting names. Nothing is changed in Google."
            : "Changes only affect this agenda. Nothing is changed in Google."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Text", text: $text, axis: .vertical)
                        .lineLimit(1...5)
                        .accessibilityIdentifier(ID.field)
                    if let originalTitle {
                        Text("Calendar title: \(originalTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Use this name for this meeting every time", isOn: $remember)
                            .accessibilityIdentifier(ID.remember)
                    }
                } footer: {
                    Text(footer)
                }
                if originalTitle != nil, !summaryRoutines.isEmpty {
                    Section {
                        ForEach(Array(summaryRoutines.enumerated()), id: \.element.id) {
                            index, routine in
                            Toggle(routine.name, isOn: binding(for: routine.id))
                                .accessibilityIdentifier(ID.summaryToggle(index))
                        }
                    } header: {
                        Text("Summaries")
                    } footer: {
                        Text(
                            "Asked for this meeting only. To set them for every meeting with this title, use Settings → Binder rules."
                        )
                    }
                }
            }
            .navigationTitle("Edit text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier(ID.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier(ID.done)
                }
            }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(id) },
            set: { isOn in
                if isOn { chosen.insert(id) } else { chosen.remove(id) }
            })
    }

    private func save() {
        switch target {
        case .event(let id):
            if remember {
                controller.saveShortName(text, forEvent: id)
            } else {
                controller.updateDraft { $0.setTitle(text, forEvent: id) }
            }
            if !summaryRoutines.isEmpty {
                let ids = summaryRoutines.map(\.id).filter { chosen.contains($0) }
                controller.updateDraft { $0.setSummaryRoutineIDs(ids, forEvent: id) }
            }
        case .task(let id):
            controller.updateDraft { $0.setText(text, forTask: id) }
        case .delegated(let id):
            controller.updateDraft { $0.setText(text, forDelegated: id) }
        }
        dismiss()
    }
}
