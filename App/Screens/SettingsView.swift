import AppCore
import SwiftUI
import UIKit

/// The settings sheet: which task lists feed the agenda, the Google client and account, and the
/// app's version. The calendars and the look of the PDF are a row each that opens a screen of its
/// own.
struct SettingsView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let todoListPicker = "todoListPicker"
        static let delegatedListPicker = "delegatedListPicker"
        static let calendarsLink = "calendarsLink"
        static let lookLink = "lookLink"
        static let rulesLink = "rulesLink"
        static let clientIDLabel = "clientIDLabel"
        static let changeClientButton = "changeClientButton"
        static let forgetClientButton = "forgetClientButton"
        static let driveFolderField = "driveFolderField"
        static let driveFolderError = "driveFolderError"
        static let driveFolderLinkField = "driveFolderLinkField"
        static let driveFolderFooter = "driveFolderFooter"
        static let routineURLField = "routineURLField"
        static let routineTokenField = "routineTokenField"
        static let saveRoutineButton = "saveRoutineButton"
        static let routineError = "routineError"
        static let routineStatusLabel = "routineStatusLabel"
        static let forgetRoutineButton = "forgetRoutineButton"
        static let summaryRoutineNameField = "summaryRoutineNameField"
        static let summaryRoutineURLField = "summaryRoutineURLField"
        static let summaryRoutineTokenField = "summaryRoutineTokenField"
        static let saveSummaryRoutineButton = "saveSummaryRoutineButton"
        static let summaryRoutineError = "summaryRoutineError"
        static let signOutButton = "signOutButton"
        static let version = "version"
        static let settingsDone = "settingsDone"
        static let form = "settingsForm"

        static func summaryRoutineRow(_ n: Int) -> String { "summaryRoutineRow.\(n)" }
        static func summaryRoutinePageToggle(_ n: Int) -> String {
            "summaryRoutinePageToggle.\(n)"
        }
        static func forgetSummaryRoutineButton(_ n: Int) -> String {
            "forgetSummaryRoutineButton.\(n)"
        }
    }

    /// A screen pushed inside the settings sheet.
    enum Route: Hashable {
        case rules
        case calendars
        case look
    }

    let appInfo: AppInfo

    @Environment(AgendaController.self) private var controller
    @Environment(HandoffController.self) private var handoff
    @Environment(\.dismiss) private var dismiss

    @State private var showsClientSheet = false
    @State private var confirmsForget = false
    @State private var routineToForget: SummaryRoutine?
    @State private var folderDraft = ""
    @State private var folderInvalid = false
    @State private var folderLinkDraft = ""
    @State private var folderLinkInvalid = false
    @State private var routineURL = ""
    @State private var routineToken = ""
    @State private var routineSaveFailed = false
    @State private var summaryRoutineName = ""
    @State private var summaryRoutineURL = ""
    @State private var summaryRoutineToken = ""
    @State private var summaryRoutineError: String?
    @State private var path: [Route]

    /// Settings, optionally opened with the binder rules already pushed.
    init(appInfo: AppInfo, opensRules: Bool = false) {
        self.appInfo = appInfo
        _path = State(initialValue: opensRules ? [.rules] : [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section { calendarsLink }
                taskListsSection
                Section { lookLink }
                Section {
                    NavigationLink("Binder rules", value: Route.rules)
                        .accessibilityIdentifier(ID.rulesLink)
                }
                clientSection
                driveSection
                routineSection
                summaryRoutinesSection
                accountSection
                aboutSection
            }
            .accessibilityIdentifier(ID.form)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .rules: RulesView()
                case .calendars: CalendarsView()
                case .look: LookView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier(ID.settingsDone)
                }
            }
            .onAppear {
                folderDraft = controller.settings.driveFolderName
                folderLinkDraft = controller.settings.driveFolderID ?? ""
            }
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
            .confirmationDialog(
                "Forget this summary routine? Its token is deleted and every rule drops it.",
                isPresented: Binding(
                    get: { routineToForget != nil },
                    set: { if !$0 { routineToForget = nil } }),
                titleVisibility: .visible
            ) {
                Button("Forget summary routine", role: .destructive) {
                    if let routine = routineToForget { forgetSummaryRoutine(routine.id) }
                    routineToForget = nil
                }
            }
        }
    }

    // MARK: Calendars and look

    private var calendarsLink: some View {
        NavigationLink(value: Route.calendars) {
            LabeledContent(
                "Calendars",
                value: CalendarSelection.summary(
                    selectedIDs: controller.settings.calendarIDs, calendars: controller.calendars)
            )
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier(ID.calendarsLink)
    }

    private var lookLink: some View {
        NavigationLink(value: Route.look) {
            LabeledContent("Look", value: controller.settings.fontPack.displayName)
                .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier(ID.lookLink)
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

    private var driveSection: some View {
        Section {
            TextField("Folder name", text: $folderDraft)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(commitFolder)
                .onChange(of: folderDraft) { folderInvalid = false }
                .accessibilityIdentifier(ID.driveFolderField)
            if folderInvalid {
                Text(DriveFolderName.invalidMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(ID.driveFolderError)
            }
            TextField("Existing folder link (optional)", text: $folderLinkDraft)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit(commitFolderLink)
                .onChange(of: folderLinkDraft) { folderLinkInvalid = false }
                .accessibilityIdentifier(ID.driveFolderLinkField)
            if folderLinkInvalid {
                Text("That isn't a Google Drive folder link.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Google Drive")
        } footer: {
            Text(
                "Finished days upload to the “\(controller.settings.driveFolderName)” folder in your Google Drive, which Magenda creates. A new name makes a new folder; days already uploaded stay where they are. To use a folder that already exists, paste its link; the name is then ignored."
            )
            .accessibilityIdentifier(ID.driveFolderFooter)
        }
    }

    private func commitFolder() {
        guard let name = DriveFolderName.validated(folderDraft) else {
            folderInvalid = true
            return
        }
        folderInvalid = false
        folderDraft = name
        Task { await controller.updateSettings { $0.driveFolderName = name } }
    }

    private func commitFolderLink() {
        let text = folderLinkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            folderLinkInvalid = false
            Task { await controller.updateSettings { $0.driveFolderID = nil } }
            return
        }
        guard let id = DriveFolderName.folderID(from: text) else {
            folderLinkInvalid = true
            return
        }
        folderLinkInvalid = false
        folderLinkDraft = id
        Task { await controller.updateSettings { $0.driveFolderID = id } }
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
                    "Finished days upload to Google Drive (see above). To send them to Claude, add the API trigger of your end-of-day routine from claude.ai/code/routines."
                )
            }
        }
    }

    private func saveRoutine() {
        // A saved routine swaps these fields for its status row. The keyboard goes first, so the
        // focused field is never removed from under it and the form does not shrink while the
        // keyboard's inset is still changing.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if handoff.saveRoutine(fireURL: routineURL, token: routineToken) {
            routineURL = ""
            routineToken = ""
            routineSaveFailed = false
        } else {
            routineSaveFailed = true
        }
    }

    // MARK: Summary routines

    private var summaryRoutinesSection: some View {
        Section {
            let routines = controller.settings.summaryRoutines
            ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                HStack {
                    Text(routine.name)
                        .accessibilityIdentifier(ID.summaryRoutineRow(index))
                    Spacer()
                    Toggle(
                        "Own page",
                        isOn: Binding(
                            get: { routine.hasPage },
                            set: { on in setSummaryRoutinePage(on, id: routine.id) })
                    )
                    .fixedSize()
                    .accessibilityIdentifier(ID.summaryRoutinePageToggle(index))
                    Button("Forget", role: .destructive) { routineToForget = routine }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier(ID.forgetSummaryRoutineButton(index))
                }
            }
            TextField("Name", text: $summaryRoutineName)
                .autocorrectionDisabled()
                .onChange(of: summaryRoutineName) { summaryRoutineError = nil }
                .accessibilityIdentifier(ID.summaryRoutineNameField)
            TextField("Fire URL", text: $summaryRoutineURL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: summaryRoutineURL) { summaryRoutineError = nil }
                .accessibilityIdentifier(ID.summaryRoutineURLField)
            SecureField("Token", text: $summaryRoutineToken)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: summaryRoutineToken) { summaryRoutineError = nil }
                .accessibilityIdentifier(ID.summaryRoutineTokenField)
            if let summaryRoutineError {
                Text(summaryRoutineError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(ID.summaryRoutineError)
            }
            Button("Save", action: saveSummaryRoutine)
                .accessibilityIdentifier(ID.saveSummaryRoutineButton)
        } header: {
            Text("Summary routines")
        } footer: {
            Text(
                "Each summary is written by its own Claude routine with its own API trigger. Create it at claude.ai/code/routines, give it only the access that summary needs, and add its trigger here. Saving a name that already exists replaces that routine's URL and token. A routine with its own page adds a page at the end of every day's binder; the routine is started only on a day when something is written on it."
            )
        }
    }

    private func setSummaryRoutinePage(_ on: Bool, id: String) {
        Task {
            await controller.updateSettings { settings in
                if let index = settings.summaryRoutines.firstIndex(where: { $0.id == id }) {
                    settings.summaryRoutines[index].hasPage = on
                }
            }
        }
    }

    private func forgetSummaryRoutine(_ id: String) {
        handoff.forgetSummaryRoutine(id: id)
        Task { await controller.updateSettings { $0.removeSummaryRoutine(id: id) } }
    }

    private func saveSummaryRoutine() {
        guard let name = SummaryRoutine.validatedName(summaryRoutineName) else {
            summaryRoutineError = SummaryRoutine.invalidNameMessage
            return
        }
        let existing = controller.settings.summaryRoutine(named: name)
        guard
            let routine = handoff.saveSummaryRoutine(
                name: existing?.name ?? name, fireURL: summaryRoutineURL,
                token: summaryRoutineToken, id: existing?.id ?? SummaryRoutine.makeID())
        else {
            summaryRoutineError = handoff.message
            return
        }
        if existing == nil {
            Task { await controller.updateSettings { $0.summaryRoutines.append(routine) } }
        }
        summaryRoutineName = ""
        summaryRoutineURL = ""
        summaryRoutineToken = ""
        summaryRoutineError = nil
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
