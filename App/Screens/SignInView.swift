import AppCore
import AuthenticationServices
import SwiftUI

/// The first screen once a Google client is set: one button that opens Google's sign-in.
struct SignInView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let signInButton = "signInButton"
        static let signInMessage = "signInMessage"
    }

    @Environment(AgendaController.self) private var controller
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(spacing: 16) {
            Text("Magenda")
                .font(.largeTitle.bold())
            Text("Make a printable agenda from your Google Calendar and Google Tasks.")
                .multilineTextAlignment(.center)
            Button("Sign in with Google") {
                let session = webAuthenticationSession
                Task {
                    await controller.signIn { @MainActor url, scheme in
                        do {
                            return try await session.authenticate(
                                using: url, callback: .customScheme(scheme),
                                preferredBrowserSession: .shared, additionalHeaderFields: [:])
                        } catch let error as ASWebAuthenticationSessionError
                            where error.code == .canceledLogin
                        {
                            throw GoogleAPIError.authorizationCancelled
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(controller.status == .signingIn)
            .accessibilityIdentifier(ID.signInButton)
            if let message = controller.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(ID.signInMessage)
            }
        }
        .frame(maxWidth: 480)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    if let controller = AppEnvironment.previewController(["-MagendaSignedOut"]) {
        SignInView()
            .environment(controller)
    }
}
