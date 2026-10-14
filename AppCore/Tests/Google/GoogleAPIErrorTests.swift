// AppCore's `GoogleAPIError`: the sentence each failure shows, which must never carry a secret.

import AppCore
import Testing

@Suite("Google API error messages")
struct GoogleAPIErrorTests {
    @Test(
        "Every error has its fixed user message",
        arguments: [
            (GoogleAPIError.notConfigured, "Enter your Google client ID first."),
            (.authorizationCancelled, "Google sign-in was cancelled."),
            (.authorizationFailed, "Google sign-in didn't complete. Try again."),
            (
                .missingScopes,
                "Magenda needs to see your calendars and tasks. Sign in again and allow both."
            ),
            (.signedOut, "Your Google sign-in expired. Sign in again."),
            (
                .forbidden,
                "Google refused the request. Check that the Calendar and Tasks APIs are enabled for this app."
            ),
            (.rateLimited, "Google is limiting requests right now. Try again in a minute."),
            (.network, "Couldn't reach Google. Check your connection and try again."),
            (.unexpectedResponse, "Google sent an unexpected response. Try again later."),
        ])
    func userMessage(error: GoogleAPIError, message: String) {
        #expect(error.userMessage == message)
    }
}
