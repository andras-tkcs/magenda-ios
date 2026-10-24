import AppCore
import SwiftUI

/// Where the person enters their own Google Cloud OAuth client. Full screen before the first
/// sign-in; a sheet from Settings when `isSheet` is true.
struct SetupView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let clientIDField = "clientIDField"
        static let clientSecretField = "clientSecretField"
        static let saveClientButton = "saveClientButton"
        static let setupMessage = "setupMessage"
        static let setupHelpLink = "setupHelpLink"
        static let setupCancel = "setupCancel"
    }

    private static let helpURL = URL(
        string: "https://github.com/andras-tkcs/magenda-ios#google-cloud-setup")

    let isSheet: Bool

    @Environment(AgendaController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var didPrefill = false

    private var canSave: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connect Google")
                    .font(.largeTitle.bold())
                Text(
                    "Magenda reads your calendar and tasks and saves finished days to your Google Drive through your own Google Cloud OAuth client. Create an iOS client for the bundle ID name.tkcs.magenda, then enter it here."
                )
                if let help = Self.helpURL {
                    Link("How to create a client", destination: help)
                        .accessibilityIdentifier(ID.setupHelpLink)
                }
                TextField("Client ID", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .accessibilityIdentifier(ID.clientIDField)
                SecureField("Client secret (optional)", text: $clientSecret)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                    .accessibilityIdentifier(ID.clientSecretField)
                Text(
                    "Leave the secret empty for an iOS client. Both stay in this device's Keychain and are never sent anywhere but Google."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                HStack {
                    if isSheet {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier(ID.setupCancel)
                    }
                    Spacer()
                    Button("Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                        .accessibilityIdentifier(ID.saveClientButton)
                }
                if let message = controller.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(ID.setupMessage)
                }
            }
            .frame(maxWidth: 480)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            guard isSheet, !didPrefill else { return }
            didPrefill = true
            clientID = controller.clientID ?? ""
        }
    }

    private func save() {
        guard canSave else { return }
        Task {
            let saved = await controller.saveClientCredentials(
                clientID: clientID, clientSecret: clientSecret)
            if saved && isSheet { dismiss() }
        }
    }
}

#Preview {
    if let controller = AppEnvironment.previewController(["-MagendaNeedsSetup"]) {
        SetupView(isSheet: false)
            .environment(controller)
    }
}
