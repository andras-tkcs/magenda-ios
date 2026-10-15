# ADR 0014: The agenda's inputs are read live from Google Calendar and Google Tasks, with task lists found by title

## Status

Accepted — 2026-10-15. Implemented.

## Context

The agenda needs the day's events, the personal to-do list and the delegated tasks. The user keeps
them in Google Calendar and in two Google Tasks lists, "Claude" and "Claude Delegations", and the
delegated list already uses a format of its own.

## Decision

1. Events and tasks are read from the Google Calendar and Google Tasks REST APIs on every load
   (`GoogleCalendarClient`, `GoogleTasksClient`, behind the `GoogleDataSource` protocol), not
   from the device's calendar database. No Drive upload: the user shares the PDF from the share
   sheet.
2. Task lists are identified by their title (settings store "Claude" and "Claude Delegations" by
   default), looked up on each load, because a list's ID can change. A missing list shows a notice
   and the agenda is built without it.
3. Delegated tasks keep the format already in the list, read unchanged: the title is
   `Owner: Task`, the first line of the notes is `#daily`, `#weekly` or `#monthly`, and the dated
   log follows, oldest first (`DelegatedTask.parse`).
4. Only tasks that are not completed and have a due date reach the to-do list; undated tasks have
   no place in its order.

## Alternatives considered

- **EventKit (the iOS Calendar).** It syncs late, has no Google Tasks, and needs a calendar
  permission prompt.
- **Delegated tasks stored in the app, or a new notes format.** The user already maintains them in
  Google Tasks; the app reads that format as written.
- **Task lists chosen by ID.** IDs can change; the title is what the user sees.
- **Uploading the PDF to Google Drive.** It would add a write scope for nothing; the PDF goes to
  Noteshelf or anywhere else through the share sheet.
- **Undated tasks on the to-do list.** There is no position for them in the overdue, today,
  upcoming order.

## Consequences

- The agenda needs a network connection to load; a rendered PDF can be shared offline.
- Renaming a list in Google Tasks means choosing it again in Settings.
- The Google JSON shapes are replayed from recorded responses in tests; no live contract check runs.

## Verification

`AppCore/Sources/Google/GoogleCalendarClient.swift`, `GoogleTasksClient.swift`;
`AppCore/Tests/Google/Fixtures/`; `AppCore/Sources/Settings/DelegatedTask.swift` (100% floor).

## Related

ADR 0013; ADR 0016.
