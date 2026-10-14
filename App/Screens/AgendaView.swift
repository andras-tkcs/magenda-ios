import AppCore
import SwiftUI

/// The agenda screen: the review list beside the PDF preview, with the controller's state behind
/// both.
struct AgendaView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let agendaScreen = "agendaScreen"
        static let previousDayButton = "previousDayButton"
        static let datePicker = "datePicker"
        static let nextDayButton = "nextDayButton"
        static let settingsButton = "settingsButton"
        static let renderButton = "renderButton"
        static let nextWorkingDayButton = "nextWorkingDayButton"
        static let loadingIndicator = "loadingIndicator"
        static let errorMessage = "errorMessage"
        static let retryButton = "retryButton"
        static let previewPlaceholder = "previewPlaceholder"
        static let pdfPreview = "pdfPreview"

        static func notice(_ n: Int) -> String { "notice.\(n)" }
    }

    let appInfo: AppInfo

    @Environment(AgendaController.self) private var controller

    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    @State private var showsSettings = false

    private var canRender: Bool {
        controller.status == .ready && controller.draft != nil
    }

    /// The day as a `Date` at local noon, for the date picker.
    private var pickedDate: Binding<Date> {
        Binding(
            get: { controller.day.startDate(in: .current).addingTimeInterval(12 * 3600) },
            set: { date in
                let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
                if let year = parts.year, let month = parts.month, let day = parts.day,
                    let picked = CalendarDay(year: year, month: month, day: day)
                {
                    Task { await controller.setDay(picked) }
                }
            })
    }

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility, preferredCompactColumn: $preferredColumn
        ) {
            sidebar
                .navigationTitle("Agenda")
                .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 560)
                .toolbar { toolbar }
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showsSettings) {
            Text("Settings")
        }
        .onChange(of: controller.rendered) { _, rendered in
            if rendered != nil {
                preferredColumn = .detail
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        switch controller.status {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier(ID.loadingIndicator)
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(ID.errorMessage)
                Button("Try again") {
                    Task { await controller.load() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(ID.retryButton)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .rendering:
            ProgressView("Rendering…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            reviewList
        }
    }

    private var reviewList: some View {
        List {
            if let draft = controller.draft {
                if !draft.notices.isEmpty {
                    Section("Notices") {
                        ForEach(Array(draft.notices.enumerated()), id: \.offset) { index, notice in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                                Text(notice)
                                    .accessibilityIdentifier(ID.notice(index))
                            }
                        }
                        if controller.showsNextWorkingDay {
                            Button("Go to next working day") {
                                Task { await controller.goToNextWorkingDay() }
                            }
                            .accessibilityIdentifier(ID.nextWorkingDayButton)
                        }
                    }
                }
                Section("Schedule and meetings") {
                    ForEach(Array(draft.events.enumerated()), id: \.element.id) { index, event in
                        EventRow(event: event, index: index, onEdit: {})
                    }
                }
                Section("To-do list") {
                    ForEach(Array(draft.tasks.enumerated()), id: \.element.id) { index, task in
                        TaskRow(task: task, index: index, onEdit: {})
                    }
                }
                if !draft.delegated.isEmpty {
                    Section("Delegated") {
                        ForEach(Array(draft.delegated.enumerated()), id: \.element.id) {
                            index, task in
                            DelegatedRow(task: task, index: index, onEdit: {})
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await controller.load() }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = controller.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        }
        .accessibilityIdentifier(ID.agendaScreen)
    }

    @ViewBuilder
    private var detail: some View {
        if let rendered = controller.rendered {
            Text(rendered.url.lastPathComponent)
                .accessibilityIdentifier(ID.pdfPreview)
        } else {
            ContentUnavailableView(
                "No PDF yet", systemImage: "doc.richtext",
                description: Text("Tap Render to see the agenda.")
            )
            .accessibilityIdentifier(ID.previewPlaceholder)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Render") {
                Task { await controller.render() }
            }
            .disabled(!canRender)
            .accessibilityIdentifier(ID.renderButton)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier(ID.settingsButton)
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                Task { await controller.setDay(controller.day.adding(days: -1)) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")
            .accessibilityIdentifier(ID.previousDayButton)
            Spacer()
            DatePicker("Date", selection: pickedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .accessibilityIdentifier(ID.datePicker)
            Spacer()
            Button {
                Task { await controller.setDay(controller.day.adding(days: 1)) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next day")
            .accessibilityIdentifier(ID.nextDayButton)
        }
    }
}

#Preview {
    if let controller = AppEnvironment.previewController() {
        AgendaView(appInfo: AppInfo(name: "Preview", version: "1.0.0", build: "1"))
            .environment(controller)
            .task { await controller.start() }
    }
}
