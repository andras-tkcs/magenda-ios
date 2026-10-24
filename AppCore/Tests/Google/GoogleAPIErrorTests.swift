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
                "Magenda needs your calendars, your tasks and the files it creates in Google Drive. Sign in again and allow all three."
            ),
            (.signedOut, "Your Google sign-in expired. Sign in again."),
            (
                .forbidden,
                "Google refused the request. Check that the Calendar, Tasks and Drive APIs are enabled for this app."
            ),
            (.notFound, "Google couldn't find that file. It may have been deleted."),
            (.rateLimited, "Google is limiting requests right now. Try again in a minute."),
            (.network, "Couldn't reach Google. Check your connection and try again."),
            (.unexpectedResponse, "Google sent an unexpected response. Try again later."),
        ])
    func userMessage(error: GoogleAPIError, message: String) {
        #expect(error.userMessage == message)
    }

    @Test(
        "No message mentions a token",
        arguments: [
            GoogleAPIError.notConfigured, .authorizationCancelled, .authorizationFailed,
            .missingScopes, .signedOut, .forbidden, .notFound, .rateLimited, .network,
            .unexpectedResponse,
        ])
    func noTokenInMessage(error: GoogleAPIError) {
        #expect(!error.userMessage.lowercased().contains("token"))
    }
}
