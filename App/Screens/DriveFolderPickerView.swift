import AppCore
import SwiftUI

extension EnvironmentValues {
    /// Lists and creates the person's Drive folders; nil in previews that have none.
    @Entry var driveFolders: (any DriveFolderBrowsing)?
}

/// One level of the Drive folder picker, pushed inside the settings sheet.
struct DriveFolderPickerView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let form = "driveFolderForm"
        static let loading = "driveFolderLoading"
        static let error = "driveFolderError"
        static let retry = "driveFolderRetry"
        static let empty = "driveFolderEmpty"
        static let useButton = "driveFolderUseButton"
        static let newButton = "driveFolderNewButton"
        static let newName = "driveFolderNewName"
        static let createError = "driveFolderCreateError"

        static func row(_ n: Int) -> String { "driveFolderRow.\(n)" }
    }

    let parent: DriveFolder?
    let choose: (DriveFolder) -> Void

    @State private var listing: DriveFolderListing
    @State private var asksForName = false
    @State private var newName = ""

    /// The level inside `parent` (My Drive when nil); `choose` is called with the folder picked.
    init(
        parent: DriveFolder?, browser: any DriveFolderBrowsing,
        choose: @escaping (DriveFolder) -> Void
    ) {
        self.parent = parent
        self.choose = choose
        _listing = State(initialValue: DriveFolderListing(parent: parent, browser: browser))
    }

    var body: some View {
        Form {
            Section { folders }
            Section {
                if let parent {
                    Button("Use “\(parent.name)”") { choose(parent) }
                        .accessibilityIdentifier(ID.useButton)
                }
                Button("New folder…") {
                    newName = ""
                    asksForName = true
                }
                .accessibilityIdentifier(ID.newButton)
                if let message = listing.createError {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(ID.createError)
                }
            }
        }
        .accessibilityIdentifier(ID.form)
        .navigationTitle(parent?.name ?? "My Drive")
        .navigationBarTitleDisplayMode(.inline)
        .task { await listing.load() }
        .alert("New folder", isPresented: $asksForName) {
            TextField("Name", text: $newName)
                .accessibilityIdentifier(ID.newName)
            Button("Create") {
                Task {
                    if let folder = await listing.createFolder(named: newName) {
                        choose(folder)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var folders: some View {
        switch listing.state {
        case .loading:
            ProgressView()
                .accessibilityIdentifier(ID.loading)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .accessibilityIdentifier(ID.error)
            Button("Try again") { Task { await listing.load() } }
                .accessibilityIdentifier(ID.retry)
        case .loaded(let folders) where folders.isEmpty:
            Text("No folders here.")
                .accessibilityIdentifier(ID.empty)
        case .loaded(let folders):
            ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                NavigationLink(value: SettingsView.Route.driveFolder(folder)) {
                    Label(folder.name, systemImage: "folder")
                }
                .accessibilityIdentifier(ID.row(index))
            }
        }
    }
}

#Preview {
    NavigationStack {
        DriveFolderPickerView(parent: nil, browser: FixtureDriveFolders(), choose: { _ in })
    }
}
