# ADR 0027: Finished days are uploaded to the person's Google Drive as one PDF, with the drive.file scope

## Status

Accepted — 2026-10-24. Implemented.
Amends [ADR 0013](0013-google-sign-in-uses-pkce-with-aswebauthenticationsession.md): the scopes, and "the app never writes to Google".
Amends [ADR 0014](0014-agenda-inputs-come-live-from-google-calendar-and-google-tasks.md): "No Drive upload".
Amended by [ADR 0033](0033-a-meeting-can-be-sent-before-the-day-ends.md): a meeting sent early is its own PDF.
Amended by [ADR 0036](0036-finished-days-upload-to-a-drive-folder-named-in-settings.md): the folder is named in Settings.
Amended by [ADR 0051](0051-drive-folders-are-picked-with-the-full-drive-scope.md): the scope is `drive`.

## Context

Getting a finished day to the end-of-day Claude routine meant Share PDF, saving the file to Drive
by hand and starting the routine by hand. Magenda only read Google Calendar and Google Tasks, with
exactly `calendar.readonly` and `tasks.readonly`, and wrote nothing to Google. Writing to Drive
needs a third scope, and tokens issued with two scopes cannot be upgraded without the person
agreeing again.

## Decision

1. Finishing a day renders its pages once (printed content kept as text, handwriting composited on
   top) and uploads that single PDF to a folder named `Magenda` in the person's Drive, next to a
   Google Doc named `Magenda <YYYY-MM-DD> notes` that Magenda creates with one status line. The PDF
   is named `Magenda <YYYY-MM-DD>.pdf`.
2. The app asks for `https://www.googleapis.com/auth/drive.file` besides the two read-only
   scopes. `drive.file` reaches only the files the app itself created, which is all it needs.
3. `GoogleOAuth.tokens` throws `.missingScopes` unless the granted scopes, from the response or
   else from the previously stored ones, include all three. `OAuthTokens` records them, and
   `GoogleSession` refreshes before sending when the stored scopes are unknown or incomplete.
   A refresh that returns the old grant deletes the stored tokens, so an existing person is sent to
   the sign-in screen with a message to sign in again and allow all three.
4. Uploads are a resumable session started with a POST (or a PATCH to replace a file the app
   already made) and finished with one `PUT` of the whole file. The Doc is created with a
   multipart upload that Drive converts from text. The Doc's status line is read with Drive's
   export to plain text.
5. The Drive client sits behind the `DriveFiling` protocol, so the hand-off controller and the
   UI-test fixtures use fakes.

## Alternatives considered

- **One PNG per page** — ten to twenty files can partly fail, need a manifest, and turn the printed
  text into pixels.
- **The full `drive` scope or `drive.readonly`** — `drive.file` reaches only what Magenda created,
  which is all it needs. Asking for the Tasks write scope at the same time, to spare a later
  re-consent, was declined.
- **A chunked resumable upload with resume on a 308 answer** — it needs a non-2xx success path
  through `GoogleSession` for files of a few megabytes. A whole-file `PUT` restarts cleanly with a
  new upload URL.
- **The Docs API for the status line** — Drive's export to `text/plain` reads it with the same
  scope and client.
- **Background upload with `BGTaskScheduler`** — it needs a capability and Info.plist changes, and
  complete-unless-open protection ([ADR 0022](0022-binder-files-and-agenda-pdfs-are-written-with-complete-unless-open-protection.md))
  keeps the files unreadable while the device is locked. A day finished offline waits and is
  uploaded when the app becomes active.

## Consequences

- Day content now leaves the device, to the person's own Drive, when they tap Finish Day.
- Everyone signs in again after updating, and the Google Cloud project needs the Drive API enabled
  and the third scope on its consent screen.
- A later stage that writes to Google Tasks will need another re-consent.
- Magenda cannot see or touch files it did not create.

## Verification

`AppCore/Sources/Google/GoogleOAuth.swift`, `AppCore/Sources/Google/GoogleSession.swift`,
`AppCore/Sources/Google/GoogleDriveClient.swift`, `AppCore/Sources/Google/HTTP.swift`,
`AppCore/Tests/Google/GoogleOAuthTests.swift`, `AppCore/Tests/Google/GoogleSessionTests.swift`,
`AppCore/Tests/Google/GoogleDriveClientTests.swift`, `AppCore/Tests/Controller/AgendaControllerTests.swift`
(a missing scope reaches the sign-in screen), and the 100 % file floor for `GoogleDriveClient.swift`
in `scripts/check_coverage_floor.py`.

## Related

ADR 0013, ADR 0014, ADR 0022, [ADR 0028](0028-the-end-of-day-routine-is-started-through-its-api-trigger.md),
[`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
