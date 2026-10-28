import AppCore
import SwiftUI

/// The agenda screen: the review list beside the binder, with the controller's state
/// behind both.
struct AgendaView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let agendaScreen = "agendaScreen"
        static let previousDayButton = "previousDayButton"
        static let datePicker = "datePicker"
        static let dayLabel = "dayLabel"
        static let nextDayButton = "nextDayButton"
        static let settingsButton = "settingsButton"
        static let reviewButton = "reviewButton"
        static let renderButton = "renderButton"
        static let startOverButton = "startOverButton"
        static let confirmStartOverButton = "confirmStartOverButton"
        static let cancelStartOverButton = "cancelStartOverButton"
        static let nextWorkingDayButton = "nextWorkingDayButton"
        static let loadingIndicator = "loadingIndicator"
        static let errorMessage = "errorMessage"
        static let retryButton = "retryButton"
        static let previewPlaceholder = "previewPlaceholder"

        static func notice(_ n: Int) -> String { "notice.\(n)" }
    }

    /// What the settings sheet opens on.
    private enum SettingsSheet: Identifiable {
        case settings, rules

        var id: Self { self }
    }

    let appInfo: AppInfo

    @Environment(AgendaController.self) private var controller

    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    @State private var settingsSheet: SettingsSheet?
    @Environment(\.launchRequest) private var launchRequest
    @State private var showsReview = false
    @State private var editing: EditTarget?
    @State private var confirmsStartOver = false

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

    /// The selected day as "Wed, 2026 10 29", led by "Today" or "Tomorrow" when it is one.
    private var dayLabel: String {
        let calendar = Calendar.current
        let date = pickedDate.wrappedValue
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, yyyy MM dd"
        let text = formatter.string(from: date)
        if calendar.isDateInToday(date) { return "Today · \(text)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow · \(text)" }
        return text
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
        .task {
            guard let screen = launchRequest?.take() else { return }
            settingsSheet = screen == .rules ? .rules : .settings
        }
        // The sheet is an item, not a flag beside a second state, so its content gets the screen
        // to open on as an argument instead of reading state the body never read.
        .sheet(item: $settingsSheet) { sheet in
            SettingsView(appInfo: appInfo, opensRules: sheet == .rules)
        }
        .sheet(isPresented: $showsReview) {
            ReviewView()
        }
        .sheet(item: $editing) { target in
            editSheet(for: target)
        }
        .alert("Start this day over?", isPresented: $confirmsStartOver) {
            Button("Start Over", role: .destructive) {
                Task { await controller.startOver() }
            }
            .accessibilityIdentifier(ID.confirmStartOverButton)
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier(ID.cancelStartOverButton)
        } message: {
            Text(
                "All your notes on this day will be deleted: the handwriting and the pages you added. The binder is then rendered again from your calendar and tasks. This can't be undone."
            )
        }
        .onChange(of: controller.rendered) { _, rendered in
            if rendered != nil {
                preferredColumn = .detail
            }
        }
        // A second render of an unchanged day yields an equal `rendered`, so the change above does
        // not fire; the end of the render itself brings the binder forward in a compact layout.
        .onChange(of: controller.status) { old, new in
            if old == .rendering, new == .ready, controller.rendered != nil {
                preferredColumn = .detail
            }
        }
        // The draft is replaced when the day changes, so an open sheet would have nothing to edit.
        .onChange(of: controller.day) {
            editing = nil
        }
    }

    @ViewBuilder
    private func editSheet(for target: EditTarget) -> some View {
        switch target {
        case .event(let id):
            if let event = controller.draft?.events.first(where: { $0.id == id }) {
                EditTextSheet(
                    target: target, text: event.title, originalTitle: event.originalTitle,
                    summaryRoutines: controller.settings.summaryRoutines,
                    selectedRoutineIDs: event.summaryRoutineIDs)
            }
        case .task(let id):
            if let task = controller.draft?.tasks.first(where: { $0.id == id }) {
                EditTextSheet(target: target, text: task.text, originalTitle: nil)
            }
        case .delegated(let id):
            if let task = controller.draft?.delegated.first(where: { $0.id == id }) {
                EditTextSheet(target: target, text: task.text, originalTitle: nil)
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
                            Text(notice)
                                .accessibilityIdentifier(ID.notice(index))
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
                        EventRow(
                            event: event, index: index, onEdit: { editing = .event(event.id) })
                    }
                }
                Section("To-do list") {
                    ForEach(Array(draft.tasks.enumerated()), id: \.element.id) { index, task in
                        TaskRow(task: task, index: index, onEdit: { editing = .task(task.id) })
                    }
                }
                if !draft.delegated.isEmpty {
                    Section("Delegated") {
                        ForEach(Array(draft.delegated.enumerated()), id: \.element.id) {
                            index, task in
                            DelegatedRow(
                                task: task, index: index, onEdit: { editing = .delegated(task.id) })
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
        if let binder = controller.binder {
            BinderView(binder: binder)
                .id(ObjectIdentifier(binder))
        } else {
            ContentUnavailableView(
                "No binder yet", systemImage: "doc.richtext",
                description: Text("Tap Render to start the day's binder.")
            )
            .accessibilityIdentifier(ID.previewPlaceholder)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if controller.binder != nil {
            ToolbarItem(placement: .primaryAction) {
                Button("Start Over", systemImage: "arrow.counterclockwise") {
                    confirmsStartOver = true
                }
                .disabled(!canRender || !controller.canStartOver)
                .accessibilityLabel("Start this day over")
                .accessibilityIdentifier(ID.startOverButton)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Render") {
                Task { await controller.render() }
            }
            .disabled(!canRender)
            .accessibilityIdentifier(ID.renderButton)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                settingsSheet = .settings
            } label: {
                Image(systemName: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier(ID.settingsButton)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showsReview = true
            } label: {
                Image(systemName: "tray.full")
            }
            .accessibilityLabel("Review")
            .accessibilityIdentifier(ID.reviewButton)
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
            // The compact picker can't show a weekday or "Today", so it sits invisibly over a
            // label of our own and still opens the calendar when tapped.
            ZStack {
                Text(dayLabel)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
                    .accessibilityIdentifier(ID.dayLabel)
                DatePicker("Date", selection: pickedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .opacity(0.015)
                    .accessibilityLabel("Choose date")
                    .accessibilityIdentifier(ID.datePicker)
            }
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
    if let services = AppEnvironment.previewServices() {
        AgendaView(appInfo: AppInfo(name: "Preview", version: "1.0.0", build: "1"))
            .environment(services.controller)
            .environment(services.handoff)
            .task { await services.controller.start() }
    }
}
