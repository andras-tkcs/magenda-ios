import AppCore
import SwiftUI

/// The accessibility identifiers of the review rows; `n` is the 0-based position in its list.
enum RowID {
    static func eventRow(_ n: Int) -> String { "eventRow.\(n)" }
    static func eventToggle(_ n: Int) -> String { "eventToggle.\(n)" }
    static func eventPageToggle(_ n: Int) -> String { "eventPageToggle.\(n)" }
    static func eventReason(_ n: Int) -> String { "eventReason.\(n)" }
    static func taskRow(_ n: Int) -> String { "taskRow.\(n)" }
    static func taskToggle(_ n: Int) -> String { "taskToggle.\(n)" }
    static func taskReason(_ n: Int) -> String { "taskReason.\(n)" }
    static func delegatedRow(_ n: Int) -> String { "delegatedRow.\(n)" }
    static func delegatedToggle(_ n: Int) -> String { "delegatedToggle.\(n)" }
    static func delegatedMarked(_ n: Int) -> String { "delegatedMarked.\(n)" }
}

/// A calendar event with its include and notes-page switches.
struct EventRow: View {
    let event: DraftEvent
    let index: Int
    let onEdit: () -> Void

    @Environment(AgendaController.self) private var controller

    private var included: Binding<Bool> {
        Binding(
            get: { event.isIncluded },
            set: { on in controller.updateDraft { $0.setIncluded(on, forEvent: event.id) } })
    }

    private var page: Binding<Bool> {
        Binding(
            get: { event.includesMeetingPage },
            set: { on in controller.updateDraft { $0.setMeetingPage(on, forEvent: event.id) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.originalTitle)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .foregroundStyle(event.isIncluded ? .primary : .secondary)
                        Text(event.timeText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .probeHover()
                .accessibilityLabel(event.originalTitle)
                .accessibilityIdentifier(RowID.eventRow(index))
                Toggle("Include", isOn: included)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Include \(event.originalTitle)")
                    .accessibilityIdentifier(RowID.eventToggle(index))
            }
            if !event.reasons.isEmpty {
                Text(event.reasons.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(RowID.eventReason(index))
            }
            if event.isIncluded {
                Toggle("Notes page", isOn: page)
                    .font(.subheadline)
                    .accessibilityLabel("Notes page for \(event.originalTitle)")
                    .accessibilityIdentifier(RowID.eventPageToggle(index))
            }
        }
        .probeContextMenu {
            Button("Edit…", action: onEdit)
            Button(event.isIncluded ? "Leave out" : "Include") {
                included.wrappedValue.toggle()
            }
        }
    }
}

/// A personal task with its include switch.
struct TaskRow: View {
    let task: DraftTask
    let index: Int
    let onEdit: () -> Void

    @Environment(AgendaController.self) private var controller

    private var included: Binding<Bool> {
        Binding(
            get: { task.isIncluded },
            set: { on in controller.updateDraft { $0.setIncluded(on, forTask: task.id) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.text)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .foregroundStyle(task.isIncluded ? .primary : .secondary)
                        if !task.notes.isEmpty {
                            Text(task.notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text("\(task.bucket.label) · \(task.dueText)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .accessibilityLabel(task.text)
                .accessibilityIdentifier(RowID.taskRow(index))
                Toggle("Include", isOn: included)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Include \(task.text)")
                    .accessibilityIdentifier(RowID.taskToggle(index))
            }
            if let reason = task.reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(RowID.taskReason(index))
            }
        }
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button(task.isIncluded ? "Leave out" : "Include") {
                included.wrappedValue.toggle()
            }
        }
    }
}

/// A delegated task with its include switch.
struct DelegatedRow: View {
    let task: DraftDelegated
    let index: Int
    let onEdit: () -> Void

    @Environment(AgendaController.self) private var controller

    private var included: Binding<Bool> {
        Binding(
            get: { task.isIncluded },
            set: { on in controller.updateDraft { $0.setIncluded(on, forDelegated: task.id) } })
    }

    private var detail: String {
        task.owner.isEmpty ? task.cadence.label : "\(task.owner) · \(task.cadence.label)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.text)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .foregroundStyle(task.isIncluded ? .primary : .secondary)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .accessibilityLabel(task.text)
                .accessibilityIdentifier(RowID.delegatedRow(index))
                Toggle("Include", isOn: included)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Include \(task.text)")
                    .accessibilityIdentifier(RowID.delegatedToggle(index))
            }
            if task.marked {
                Text("Check-in due")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    .accessibilityIdentifier(RowID.delegatedMarked(index))
            }
            ForEach(Array(task.status.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let warning = task.warning {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button(task.isIncluded ? "Leave out" : "Include") {
                included.wrappedValue.toggle()
            }
        }
    }
}

// PROBE: temporary switches for diagnosing iPad toggle taps; removed before the phase ends.
private let probeArguments = ProcessInfo.processInfo.arguments

extension View {
    @ViewBuilder
    fileprivate func probeHover() -> some View {
        if probeArguments.contains("-ProbeNoHover") { self } else { self.hoverEffect() }
    }

    @ViewBuilder
    fileprivate func probeContextMenu<M: View>(@ViewBuilder _ items: () -> M) -> some View {
        if probeArguments.contains("-ProbeNoContextMenu") {
            self
        } else {
            self.contextMenu(menuItems: items)
        }
    }
}

#Preview {
    if let controller = AppEnvironment.previewController() {
        List {
            if let draft = controller.draft {
                ForEach(Array(draft.events.enumerated()), id: \.element.id) { index, event in
                    EventRow(event: event, index: index, onEdit: {})
                }
                ForEach(Array(draft.tasks.enumerated()), id: \.element.id) { index, task in
                    TaskRow(task: task, index: index, onEdit: {})
                }
                ForEach(Array(draft.delegated.enumerated()), id: \.element.id) { index, task in
                    DelegatedRow(task: task, index: index, onEdit: {})
                }
            }
        }
        .environment(controller)
        .task { await controller.start() }
    }
}
