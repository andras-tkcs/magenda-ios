import AppCore
import SwiftUI

/// The calendars that feed the agenda: a checklist, pushed from the settings form.
struct CalendarsView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let form = "calendarsForm"

        static func calendarRow(_ n: Int) -> String { "calendarRow.\(n)" }
    }

    @Environment(AgendaController.self) private var controller

    var body: some View {
        Form {
            Section {
                ForEach(Array(controller.calendars.enumerated()), id: \.element.id) {
                    index, calendar in
                    Button {
                        toggleCalendar(calendar.id)
                    } label: {
                        HStack {
                            Text(calendar.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected(calendar) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityAddTraits(isSelected(calendar) ? .isSelected : [])
                    .accessibilityIdentifier(ID.calendarRow(index))
                }
            } footer: {
                Text("None selected uses your primary calendar.")
            }
        }
        .accessibilityIdentifier(ID.form)
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isSelected(_ calendar: GoogleCalendar) -> Bool {
        controller.settings.calendarIDs.contains(calendar.id)
    }

    private func toggleCalendar(_ id: String) {
        Task {
            await controller.updateSettings { settings in
                if let index = settings.calendarIDs.firstIndex(of: id) {
                    settings.calendarIDs.remove(at: index)
                } else {
                    settings.calendarIDs.append(id)
                }
            }
        }
    }
}

#Preview {
    if let services = AppEnvironment.previewServices() {
        NavigationStack { CalendarsView() }
            .environment(services.controller)
            .environment(services.handoff)
            .task {
                await services.controller.start()
                services.handoff.start()
            }
    }
}
