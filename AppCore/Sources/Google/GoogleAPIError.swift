/// Everything that can go wrong talking to Google, phrased for the person using the app.
public enum GoogleAPIError: Error, Equatable, Sendable {
    /// No Google client ID has been entered.
    case notConfigured
    /// The person closed the sign-in sheet or declined access.
    case authorizationCancelled
    /// Sign-in failed for any other reason.
    case authorizationFailed
    /// Google granted access without both read-only scopes.
    case missingScopes
    /// The stored sign-in is no longer valid.
    case signedOut
    /// Google answered 403.
    case forbidden
    /// Google answered 429.
    case rateLimited
    /// Google could not be reached.
    case network
    /// Google answered with something the app cannot read.
    case unexpectedResponse

    /// A sentence saying what happened and what the person can do about it. It never contains a
    /// token or anything from the person's calendar or tasks.
    public var userMessage: String {
        switch self {
        case .notConfigured:
            "Enter your Google client ID first."
        case .authorizationCancelled:
            "Google sign-in was cancelled."
        case .authorizationFailed:
            "Google sign-in didn't complete. Try again."
        case .missingScopes:
            "Magenda needs to see your calendars and tasks. Sign in again and allow both."
        case .signedOut:
            "Your Google sign-in expired. Sign in again."
        case .forbidden:
            "Google refused the request. Check that the Calendar and Tasks APIs are enabled for this app."
        case .rateLimited:
            "Google is limiting requests right now. Try again in a minute."
        case .network:
            "Couldn't reach Google. Check your connection and try again."
        case .unexpectedResponse:
            "Google sent an unexpected response. Try again later."
        }
    }
}
