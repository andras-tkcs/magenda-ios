import AppCore
import SwiftUI

/// The settings sheet: which calendars and task lists feed the agenda, how the PDF looks, the
/// Google client and account, and the app's version.
struct SettingsView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let todoListPicker = "todoListPicker"
        static let delegatedListPicker = "delegatedListPicker"
        static let colorError = "colorError"
        static let resetColorsButton = "resetColorsButton"
        static let rulesLink = "rulesLink"
        static let clientIDLabel = "clientIDLabel"
        static let changeClientButton = "changeClientButton"
        static let forgetClientButton = "forgetClientButton"
        static let routineURLField = "routineURLField"
        static let routineTokenField = "routineTokenField"
        static let saveRoutineButton = "saveRoutineButton"
        static let routineError = "routineError"
        static let routineStatusLabel = "routineStatusLabel"
        static let forgetRoutineButton = "forgetRoutineButton"
        static let signOutButton = "signOutButton"
        static let version = "version"
        static let settingsDone = "settingsDone"

        static func calendarRow(_ n: Int) -> String { "calendarRow.\(n)" }
        static func fontOption(_ pack: FontPack) -> String { "fontOption.\(pack.rawValue)" }
        static func colorField(_ role: ColorRole) -> String { "colorField.\(role.rawValue)" }
    }

    /// The five colors the person can change.
    enum ColorRole: String, CaseIterable, Identifiable {
        case weekend, heading, label, accent, notes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .weekend: "Weekend"
            case .heading: "Date heading"
            case .label: "Section labels"
            case .accent: "Accent"
            case .notes: "Notes heading"
            }
        }

        var keyPath: WritableKeyPath<ThemeColors, RGBColor> {
            switch self {
            case .weekend: \.weekend
            case .heading: \.heading
            case .label: \.label
            case .accent: \.accent
            case .notes: \.notes
            }
        }
    }

    let appInfo: AppInfo

    @Environment(AgendaController.self) private var controller
    @Environment(HandoffController.self) private var handoff
    @Environment(\.dismiss) private var dismiss

    @State private var hexDrafts: [ColorRole: String] = [:]
    @State private var invalidRoles: Set<ColorRole> = []
    @State private var showsClientSheet = false
    @State private var confirmsForget = false
    @State private var routineURL = ""
    @State private var routineToken = ""
    @State private var routineSaveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                calendarsSection
                taskListsSection
                lookSection
                Section {
                    NavigationLink("Binder rules") {
                        RulesView()
                    }
                    .accessibilityIdentifier(ID.rulesLink)
                }
                clientSection
                routineSection
                accountSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier(ID.settingsDone)
                }
            }
            .onAppear(perform: resetHexDrafts)
            .sheet(isPresented: $showsClientSheet) {
                SetupView(isSheet: true)
            }
            .confirmationDialog(
                "Forget this Google client? You'll need to enter a client ID again.",
                isPresented: $confirmsForget, titleVisibility: .visible
            ) {
                Button("Forget", role: .destructive) {
                    Task { await controller.forgetClientCredentials() }
                }
            }
        }
    }

    // MARK: Calendars

    private var calendarsSection: some View {
        Section {
            ForEach(Array(controller.calendars.enumerated()), id: \.element.id) { index, calendar in
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
        } header: {
            Text("Calendars")
        } footer: {
            Text("None selected uses your primary calendar.")
        }
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

    // MARK: Task lists

    private var taskListsSection: some View {
        Section {
            Picker("To-do list", selection: todoTitle) {
                ForEach(titles(including: controller.settings.todoListTitle), id: \.self) {
                    Text($0).tag($0)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(ID.todoListPicker)
            Picker("Delegated tasks", selection: delegatedTitle) {
                Text("None").tag("")
                let others = titles(including: controller.settings.delegatedListTitle)
                    .filter { $0 != controller.settings.todoListTitle }
                ForEach(others, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(ID.delegatedListPicker)
        } header: {
            Text("Task lists")
        } footer: {
            Text(
                "Lists are found by name, so renaming one in Google Tasks means picking it again here."
            )
        }
    }

    /// The task list titles, plus `current` when it names no list, so the picker can show it.
    private func titles(including current: String) -> [String] {
        var result = controller.taskLists.map(\.title)
        if !current.isEmpty && !result.contains(current) {
            result.append(current)
        }
        return result
    }

    private var todoTitle: Binding<String> {
        Binding(
            get: { controller.settings.todoListTitle },
            set: { title in
                Task { await controller.updateSettings { $0.todoListTitle = title } }
            })
    }

    private var delegatedTitle: Binding<String> {
        Binding(
            get: { controller.settings.delegatedListTitle },
            set: { title in
                Task { await controller.updateSettings { $0.delegatedListTitle = title } }
            })
    }

    // MARK: Look

    private var lookSection: some View {
        Section("Look") {
            ForEach(FontPack.allCases, id: \.self) { pack in
                Button {
                    Task { await controller.updateSettings { $0.fontPack = pack } }
                } label: {
                    HStack {
                        Text(pack.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if controller.settings.fontPack == pack {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityAddTraits(controller.settings.fontPack == pack ? .isSelected : [])
                .accessibilityIdentifier(ID.fontOption(pack))
            }
            ForEach(ColorRole.allCases) { role in
                colorRow(role)
            }
            Button("Reset colors") {
                invalidRoles = []
                Task {
                    await controller.updateSettings { $0.colors = .default }
                    resetHexDrafts()
                }
            }
            .accessibilityIdentifier(ID.resetColorsButton)
        }
    }

    private func colorRow(_ role: ColorRole) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                let color = controller.settings.colors[keyPath: role.keyPath]
                RoundedRectangle(cornerRadius: 4)
                    .fill(Self.swatch(color))
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(role.title)
                Spacer()
                TextField("215E99", text: hexBinding(role))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .frame(maxWidth: 120)
                    .onSubmit { commitHex(role) }
                    .accessibilityIdentifier(ID.colorField(role))
            }
            if invalidRoles.contains(role) {
                Text("Use six hex digits, like 215E99.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(ID.colorError)
            }
        }
    }

    private static func swatch(_ color: RGBColor) -> Color {
        Color(
            red: Double(color.red) / 255, green: Double(color.green) / 255,
            blue: Double(color.blue) / 255)
    }

    private func hexBinding(_ role: ColorRole) -> Binding<String> {
        Binding(
            get: { hexDrafts[role] ?? controller.settings.colors[keyPath: role.keyPath].hex },
            set: { hexDrafts[role] = $0 })
    }

    private func commitHex(_ role: ColorRole) {
        let text = hexDrafts[role] ?? ""
        guard let color = RGBColor(hex: text) else {
            invalidRoles.insert(role)
            return
        }
        invalidRoles.remove(role)
        hexDrafts[role] = color.hex
        Task { await controller.updateSettings { $0.colors[keyPath: role.keyPath] = color } }
    }

    private func resetHexDrafts() {
        var drafts: [ColorRole: String] = [:]
        for role in ColorRole.allCases {
            drafts[role] = controller.settings.colors[keyPath: role.keyPath].hex
        }
        hexDrafts = drafts
    }

    // MARK: Client, account, about

    private var clientSection: some View {
        Section("Google client") {
            Text(controller.clientID ?? "Not set")
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .accessibilityIdentifier(ID.clientIDLabel)
            Button("Change client…") { showsClientSheet = true }
                .accessibilityIdentifier(ID.changeClientButton)
            Button("Forget client", role: .destructive) { confirmsForget = true }
                .accessibilityIdentifier(ID.forgetClientButton)
        }
    }

    @ViewBuilder
    private var routineSection: some View {
        if let triggerID = handoff.routineTriggerID {
            Section("End-of-day routine") {
                Text("Sends finished days to \(triggerID)")
                    .accessibilityIdentifier(ID.routineStatusLabel)
                Button("Forget routine", role: .destructive) { handoff.forgetRoutine() }
                    .accessibilityIdentifier(ID.forgetRoutineButton)
            }
        } else {
            Section {
                TextField("Fire URL", text: $routineURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: routineURL) { routineSaveFailed = false }
                    .accessibilityIdentifier(ID.routineURLField)
                SecureField("Token", text: $routineToken)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: routineToken) { routineSaveFailed = false }
                    .accessibilityIdentifier(ID.routineTokenField)
                if routineSaveFailed, let message = handoff.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(ID.routineError)
                }
                Button("Save", action: saveRoutine)
                    .accessibilityIdentifier(ID.saveRoutineButton)
            } header: {
                Text("End-of-day routine")
            } footer: {
                Text(
                    "Finished days upload to Google Drive. To send them to Claude, add the API trigger of your end-of-day routine from claude.ai/code/routines."
                )
            }
        }
    }

    private func saveRoutine() {
        if handoff.saveRoutine(fireURL: routineURL, token: routineToken) {
            routineURL = ""
            routineToken = ""
            routineSaveFailed = false
        } else {
            routineSaveFailed = true
        }
    }

    private var accountSection: some View {
        Section("Account") {
            Button("Sign out") {
                Task { await controller.signOut() }
            }
            .accessibilityIdentifier(ID.signOutButton)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appInfo.displayVersion)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(ID.version)
        } header: {
            Text("About")
        } footer: {
            Text("Fonts: Outfit, Roboto and JetBrains Mono, under the SIL Open Font License 1.1.")
        }
    }
}

#Preview {
    if let services = AppEnvironment.previewServices() {
        SettingsView(appInfo: AppInfo(name: "Preview", version: "1.0.0", build: "1"))
            .environment(services.controller)
            .environment(services.handoff)
            .task {
                await services.controller.start()
                services.handoff.start()
            }
    }
}
