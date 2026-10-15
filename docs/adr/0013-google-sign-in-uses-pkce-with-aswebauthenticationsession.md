# ADR 0013: Google sign-in is OAuth 2.0 with PKCE presented by ASWebAuthenticationSession, with the user's own client

## Status

Accepted — 2026-10-15. Implemented.

## Context

The app reads the user's Google Calendar and Google Tasks. That needs an OAuth client, and the
repository is public: a client ID (or secret) committed to it would tie the project to one Google
Cloud project, and a build-time injected one would make builds from the same source differ per
person.

## Decision

1. Sign-in is the OAuth 2.0 authorization-code flow with PKCE (S256), implemented in AppCore
   (`GoogleOAuth`, `GoogleSession`) and presented by `ASWebAuthenticationSession` in `App/`. No
   third-party sign-in SDK.
2. The scopes are exactly `https://www.googleapis.com/auth/calendar.readonly` and
   `https://www.googleapis.com/auth/tasks.readonly`. The app never writes to Google.
3. Tokens live only in the Keychain (`KeychainTokenStore`), accessible after first unlock and not
   migrating to other devices. The access token is refreshed on demand, one refresh shared by
   concurrent callers.
4. No Google client ships with the app. The user creates an iOS OAuth client in their own Google
   Cloud project and enters its client ID (and a client secret only for a client type that has one)
   on first launch; both are stored in the Keychain (`KeychainClientCredentialsStore`) and can be
   changed or forgotten in Settings. No client ID, secret or project number is ever committed,
   bundled or read from the bundle. Tests and fixtures use made-up client IDs.

## Alternatives considered

- **The GoogleSignIn SDK.** A third-party dependency for what `ASWebAuthenticationSession` and a
  small PKCE implementation do; new packages need an ADR (CONTRIBUTING.md).
- **A client ID committed to the repository** (a bundled text file, `project.yml` or an Info.plist
  key). The repository is public and no organization's Google project belongs in it; every user
  brings their own client.
- **A client ID injected at build time** (an `.xcconfig` filled from a CI secret). Builds from the
  same source would differ per person, and release archives would carry one person's client.
- **Narrower `calendar.calendarlist.readonly` and `calendar.events.readonly` scopes.** Two scopes
  for the same read access; one well-known read-only scope is enough.
- **EventKit.** See ADR 0014.

## Consequences

- First launch needs the setup in the README's "Google Cloud setup" section before anything works.
- With an "External" consent screen in Testing mode Google expires refresh tokens after 7 days; the
  app then shows that the sign-in expired and asks to sign in again. An "Internal" consent screen
  has no such limit.
- A Google Workspace whose admin restricts third-party apps blocks sign-in until the admin trusts
  the client; that is an admin setting, not something the app can fix.
- App Store Connect's privacy answer is "Data Not Collected": Google data is read on the device and
  sent nowhere else.

## Verification

`AppCore/Sources/Google/GoogleOAuth.swift` and `GoogleSession.swift` (100% floors);
`AppCore/Tests/Google/`; `App/Platform/`; `AppUITests/SetupUITests.swift`.

## Related

ADR 0014; ADR 0007 (the Keychain sits behind AppCore's `TokenStore` and `ClientCredentialsStore`
protocols).
