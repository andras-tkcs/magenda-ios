import AppCore
import SwiftUI

/// The finished days and how far each hand-off to Claude has come, with the button that moves a
/// day on.
struct ReviewView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let reviewDone = "reviewDone"
        static let reviewEmpty = "reviewEmpty"

        static func reviewRow(_ n: Int) -> String { "reviewRow.\(n)" }
        static func reviewStatus(_ n: Int) -> String { "reviewStatus.\(n)" }
        static func reviewError(_ n: Int) -> String { "reviewError.\(n)" }
        static func reviewOpenDoc(_ n: Int) -> String { "reviewOpenDoc.\(n)" }
        static func reviewAction(_ n: Int) -> String { "reviewAction.\(n)" }
    }

    @Environment(AgendaController.self) private var controller
    @Environment(HandoffController.self) private var handoff
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if handoff.days.isEmpty {
                    ContentUnavailableView(
                        "No finished days", systemImage: "tray",
                        description: Text("Finish a day in the binder to send it to Claude.")
                    )
                    .accessibilityIdentifier(ID.reviewEmpty)
                } else {
                    List {
                        ForEach(Array(handoff.days.enumerated()), id: \.element.id) {
                            index, day in
                            row(day, index: index)
                        }
                    }
                }
            }
            .navigationTitle("Finished days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close the finished days")
                        .accessibilityIdentifier(ID.reviewDone)
                }
            }
        }
        .task { await handoff.refresh(excluding: controller.day) }
        .refreshable { await handoff.refresh(excluding: controller.day) }
    }

    private func row(_ day: DayHandoff, index: Int) -> some View {
        let phase = day.phase
        return VStack(alignment: .leading, spacing: 6) {
            Text(day.displayTitle)
                .font(.headline)
            Text(phase.title)
                .accessibilityIdentifier(ID.reviewStatus(index))
            if let error = day.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(ID.reviewError(index))
            }
            HStack {
                if let url = handoff.docURL(for: day.id) {
                    Button("Open Doc") { openURL(url) }
                        .accessibilityLabel("Open the Google Doc for \(day.displayTitle)")
                        .accessibilityIdentifier(ID.reviewOpenDoc(index))
                }
                if let action = phase.action {
                    Button(Self.title(of: action)) {
                        Task { await handoff.perform(action, on: day.id) }
                    }
                    .disabled(handoff.isBusy)
                    .accessibilityLabel(Self.spokenTitle(of: action, on: day.displayTitle))
                    .accessibilityIdentifier(ID.reviewAction(index))
                }
            }
            .buttonStyle(.bordered)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ID.reviewRow(index))
    }

    private static func title(of action: HandoffAction) -> String {
        switch action {
        case .retry: "Try again"
        case .approve(.approveNotes): "Approve notes"
        case .approve: "Approve"
        }
    }

    private static func spokenTitle(of action: HandoffAction, on day: String) -> String {
        switch action {
        case .retry: return "Try again for \(day)"
        case .approve(.approveNotes): return "Approve the notes for \(day)"
        case .approve: return "Approve the summary for \(day)"
        }
    }
}

#Preview {
    if let services = AppEnvironment.previewServices() {
        ReviewView()
            .environment(services.controller)
            .environment(services.handoff)
            .task { services.handoff.start() }
    }
}
