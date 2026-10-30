# ADR 0036: Finished days upload to a Drive folder named in Settings

## Status

Accepted — 2026-10-26. Implemented.
Amends [ADR 0027](0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md): the fixed folder name.
Amended by [ADR 0051](0051-drive-folders-are-picked-with-the-full-drive-scope.md): the folder is picked from the person's Drive, not named.

## Context

Every finished day and every meeting sent early went to a folder called `Magenda`, a name fixed in
code. The person wanted to choose it. The end-of-day routine checks where the PDF sits, so a
renamed folder would also stop a routine that looks for a folder named `Magenda`.

## Decision

1. Settings → Google Drive shows the folder name and lets the person change it. The default is
   `Magenda`. A name is 1 to 100 characters after trimming, without `/`, `\` or a control
   character; anything else is refused with a message and the old name stays.
2. The name is read at the first upload of a day or a meeting. Magenda finds a folder of that name
   among the files it created, or creates one in the root of the Drive.
3. One date stays in the folder its first upload used. Every later upload of that date, a
   meeting sent early and the day's Finish Day alike, reuses that folder even if the name has
   changed since. Only a new date uses a new name. A file uploaded before folders were recorded
   stays in `Magenda`.
4. The folder's ID is recorded on the hand-off record as an optional `folderID` and sent in the
   payload next to `driveFileID`. The schema stays `magenda.end-of-day/2`: that schema is not
   released yet and the key is optional. The routine checks that the PDF's parent is `folderID`,
   and on a payload without it a folder named `Magenda`.
5. Changing only the folder name does not discard a rendered PDF, since the PDF does not show it.

## Alternatives considered

- **Picking an existing folder** — needs the full `drive` scope or the Google Picker, which has no
  iOS SDK, and moves the trust boundary of ADR 0027.
- **A fixed name with a Settings row only showing it** — the person asked to change it.
- **A path with `/` creating nested folders** — more Drive calls for little gain; the folder can
  be moved anywhere in Drive and the lookup by name still finds it there.
- **Moving earlier days when the name changes** — the routine has already checked them in place.
- **A new schema version** — schema 2 is not released yet, and the key is optional.

## Consequences

- Renaming the folder starts a new folder for the next new date; earlier days stay where they are.
- The routine's skill, which lives outside this repository, must check the parent against
  `folderID`; until it does, a renamed folder fails its check.
- A record uploaded before `folderID` existed decodes with none, so older records keep working.

## Verification

`AppCore/Sources/Settings/DriveFolderName.swift`, `AppCore/Sources/Settings/AgendaSettings.swift`,
`AppCore/Sources/Handoff/DayHandoff.swift`, `AppCore/Sources/Handoff/HandoffController.swift`,
`AppCore/Sources/Controller/AgendaController.swift`, `App/AppEnvironment.swift`,
`App/Screens/SettingsView.swift`, `AppCore/Tests/Settings/DriveFolderNameTests.swift`,
`AppCore/Tests/Settings/AgendaSettingsTests.swift`, `AppCore/Tests/Handoff/DayHandoffTests.swift`,
`AppCore/Tests/Handoff/HandoffControllerTests.swift`,
`AppCore/Tests/Controller/AgendaControllerTests.swift`, `AppUITests/SettingsUITests.swift`.

## Related

ADR 0027, ADR 0033, ADR 0034.
