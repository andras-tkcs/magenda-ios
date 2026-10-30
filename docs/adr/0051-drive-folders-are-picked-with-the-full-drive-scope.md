# ADR 0051: Drive folders are picked from the person's Drive with the full drive scope

## Status

Accepted — 2026-10-30. Implemented.
Amends [ADR 0027](0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md): the `drive.file` scope.
Amends [ADR 0036](0036-finished-days-upload-to-a-drive-folder-named-in-settings.md): the folder is picked, not named.

## Context

Under `drive.file`, Magenda sees only the files and folders it created. A Drive folder the person
had made themselves was invisible to it, so a pasted folder link failed at upload, and typing a
folder name or link was error-prone. The person wanted to choose the folder from their Drive.

## Decision

1. The app asks for the `https://www.googleapis.com/auth/drive` scope next to `calendar.readonly`
   and `tasks.readonly`. A stored grant that lacks it takes the existing `.missingScopes` path, so
   everyone signs in again once.
2. Settings → Google Drive → Folder opens a browser of the person's Drive
   (`DriveFolderBrowsing`, implemented by `GoogleDriveClient`). They open folders, pick one with
   "Use …", or create a new one inside the folder they are in. My Drive itself cannot be picked.
3. A picked folder is stored as `driveFolderID` with its name in `driveFolderName`. When none is
   picked, finished days go to a folder called `Magenda`, found or created by name as before.
4. The by-name lookup is limited to folders the person owns (`'me' in owners`), so a `Magenda`
   folder someone shared with them is never used.
5. `HandoffController` is unchanged: a picked folder arrives through `existingFolderID`, the
   default through `folderName`.

## Alternatives considered

- **`drive.metadata.readonly` next to `drive.file`** — it lists folders, but Drive refuses to file
  into a folder the app cannot write, so a picked folder Magenda did not create would fail at
  upload. The maintainer chose the full scope.
- **The Google Picker** — it has no iOS SDK; a web view of it is a second sign-in surface (ADR 0036
  already rejected it).
- **A flat, searchable list of all folders** — same-named folders cannot be told apart, and
  creating one has no natural parent. The maintainer chose the tree.

## Consequences

- Everyone signs in again once after updating.
- Magenda can now read the whole Drive, though it only lists folders and writes its own files.
- The by-name lookup can find a `Magenda` folder the person made, and only one they own.
- `drive` is a restricted scope: an External OAuth client in production would need Google's
  verification. Clients in Testing, and Internal clients, do not.

## Verification

`AppCore/Sources/Google/GoogleOAuth.swift`, `AppCore/Sources/Google/DriveFolder.swift`,
`AppCore/Sources/Google/GoogleDriveClient.swift`, `AppCore/Sources/Google/DriveFolderFixtures.swift`,
`AppCore/Sources/Controller/DriveFolderListing.swift`, `AppCore/Sources/Settings/AgendaSettings.swift`,
`App/Screens/DriveFolderPickerView.swift`, `App/Screens/SettingsView.swift`, and their tests under
`AppCore/Tests/` and `AppUITests/`.

## Related

[ADR 0027](0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md),
[ADR 0036](0036-finished-days-upload-to-a-drive-folder-named-in-settings.md),
[`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
