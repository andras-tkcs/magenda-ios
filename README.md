# Magenda

An iPad-first app that builds the daily binder from Google Calendar and Google Tasks. Sign in with
Google, pick a day, review what the app selected and why, untick or edit anything and render the
agenda as a PDF. The day opens as a binder you write in with Apple Pencil. The PDF can be shared
anywhere. The rules are fixed and editable, and no AI is involved (ADR 0016).

## What goes on the agenda

Everything is decided by rules you can see. A left-out item stays on the review screen with its
reason, and nothing is changed in Google.

**Schedule and meeting pages** (from the calendars chosen in Settings; the primary calendar when
none is chosen)

- All-day events, cancelled events, working-location, out-of-office and birthday events are not
  listed.
- A declined event is left out ("Declined").
- An event whose title starts with a personal-block prefix is left out ("Personal block"). The
  defaults are "Lunch" and "Start the day"; edit them under Settings → Binder rules → Personal
  blocks.
- A repeat of an earlier event is left out ("Duplicate of an earlier event"): the same calendar
  event, or the same title starting less than two hours after an earlier one.
- Events starting between 8:00 and 18:59 go on the daily schedule at their start time; others
  have a meeting page only ("Not on the schedule: outside 8:00–18:59").
- An event gets a meeting page only when someone other than you and a room is invited and has not
  declined ("No meeting page: no other attendees"). The "Notes page" switch on each row overrides
  it.
- A meeting page's title drops the prefixes under Settings → Binder rules → Title prefixes
  (defaults "REMINDER //", "REMINDER:", "(temp)", "FW:", "Fwd:", "CONDITIONAL", "weekly"). A short
  name saved from a meeting's Edit sheet replaces the title for every instance of that meeting
  (Settings → Binder rules → Short meeting names). A title that is still too long is cut with
  "…". The schedule always shows the full calendar title, cut with "…" if it does not fit.

**Notices** (shown above the list, never in the PDF)

- A weekend date.
- An all-day event on that date whose title contains an out-of-office word (defaults "OOO", "Out
  of Office", "Vacation", "PTO"; Settings → Binder rules → Out-of-office words), or an
  out-of-office event. "Go to next working day" jumps to the next weekday.

**To-do list** (from the Google Tasks list named in Settings, "Claude" by default)

- Only open tasks with a due date. Overdue first, then due on the day, then due within the
  look-ahead (5 days by default; Settings → Binder rules → Look-ahead, 0 to 14), each by due date.
- A look-ahead task titled "Name – to be discussed" (or "TBD") is kept only when that person is
  invited to an included meeting that day. A name that differs from the attendee's first name is
  matched under Settings → Binder rules → People, where you can type a
  name and email or choose them from Contacts. One entry can hold several names for the same
  person, separated by commas. Otherwise it is listed unticked with the reason.
- A task's notes take one line; a task that does not fit the list is left off the PDF and listed in
  a banner under the preview (on iPad, under the binder's toolbar).

## Binder (iPad)

On iPad, Render opens the day's binder: the same pages as the PDF, drawn in the app, with Apple
Pencil handwriting on each one. Swipe left and right to turn pages, one whole page at a time. The
toolbar has black, blue, red and green pens, an eraser, undo and redo, buttons that jump to the
overview, the delegated tasks and the notes, Add page, which puts a blank copy of the current page
after it, and Delete page, which removes a page you added after asking. A page added after a
meeting page is titled "cont." before the meeting's title. Undo and redo reach every page you wrote
on since the day was opened, and go to the page they change. Double-tapping (or squeezing) the
Apple Pencil switches between the pen and the eraser. Tapping a link on a page follows it. Share PDF
shares the day with your handwriting on its pages.

Handwriting is saved on the device per page. Rendering the day again keeps it on its page, and a
meeting page you wrote on stays even when the meeting has left the agenda. Start over, in the
agenda's toolbar, deletes all of the day's handwriting and added pages after asking, and renders
the day fresh; it is refused while a meeting of the day is sent (ADR 0035). Once a day is started, it
opens without a network connection (ADR 0020, ADR 0021, ADR 0024 to ADR 0026). The saved binder and
the shared PDFs can't be read while the device is locked (ADR 0022).

## Finishing a day

On an iPad, **Finish Day** in the binder's toolbar sends the day to Google Drive and starts your
end-of-day Claude routine (ADR 0027, ADR 0028). Magenda renders the day once, with the printed
text kept as text and your handwriting on top, and uploads it as `Magenda <date>.pdf` to a
folder in your Drive, `Magenda` unless you pick or create another under Settings → Google Drive → Folder (ADR 0051). Next to it, it creates a Google Doc named `Magenda <date> notes`
whose first line is the day's status. Magenda can see your whole Drive; it only lists folders and writes its own PDFs and Docs (ADR 0051). A day finished
without a connection waits and is sent the next time the app becomes active; finishing a day again
before it was sent replaces its PDF. **Reset Hand-off**, after a confirmation, forgets that a day was sent so you can finish it again (ADR 0032); the earlier PDF and Doc stay in Drive.

On a meeting page, **Send Meeting** sends that meeting on its own, with its own PDF and Google Doc and its own row in Review, and locks its pages so they can't be written on afterwards; Finish Day then skips it in the notes (ADR 0033, ADR 0034).

To send days to Claude, open Settings → End-of-day routine and enter the fire URL and token of the
routine's API trigger (from claude.ai/code/routines). The token stays in the device's Keychain and
is sent only to that routine; Forget routine deletes it. Without a routine the day is still
uploaded, and the Review list offers Try again once a routine is saved. The routine itself, and
what it must do with the day, are described in
[`docs/end-of-day-handoff.md`](docs/end-of-day-handoff.md).

The **Review** button in the agenda's toolbar opens the list of finished days (ADR 0029). Each row
shows the day's state, an error if the last step failed, **Open Doc** to read and edit the notes in
Google Docs, and the one button the state calls for: Try again (not yet uploaded or sent), Approve
notes (the notes are ready) or Approve summaries (every asked-for summary is in the Doc). Approving
the notes starts the summary routines, or closes the day when none was asked for; Approve summaries
closes it. Magenda reads the Doc's first line (`Status: …`) and the `Summary ready:` marker lines
the summary routines append (ADR 0039).

Each kind of summary is written by its own Claude routine (ADR 0038). Add each one under Settings →
Summary routines with a name and the fire URL and token of its API trigger; the token stays in the
Keychain. Then tick which meetings get it, by meeting title under Settings → Binder rules → Meeting
summaries (a rule can be a pattern, a regular expression like `delivery sync [0-9]+`, ADR 0052) or for one meeting on its Edit sheet. The meeting page prints the ticked routines' names
after **Summary:**. Magenda starts each ticked routine once, when the notes are approved.

Five days after Magenda first reads `Status: Closed`, it deletes that day's handwriting and its
stored PDF from the device (ADR 0030). A small record of the day stays, so the day can't be sent
twice. The PDF and the Doc in Drive are not touched.

## Delegated tasks

The delegated page reads a second Google Tasks list ("Claude Delegations" by default; "None" in
Settings turns the page off). Each open task follows this format:

```
Title:  Sam: Countersign the supplier agreement
Notes:  #weekly
        2026-08-13 Delegated to Sam.
        2026-08-20 Followed up — waiting on their lawyer.
        2026-08-27 Countersigned copy received, filing pending.
```

- The title is `Owner: Task`, split at the first colon.
- The first line of the notes is `#daily`, `#weekly` or `#monthly`.
- The page shows the last two log lines. The row is marked when the task's due date (the next
  check-in) is on or before the day.
- A task that does not follow the format is still listed, with a warning ("shown as Daily", "shown
  without an owner").

## Google Cloud setup

The app ships without a Google client. You create your own and enter its client ID in the app; the
repository never holds one (ADR 0013).

1. In the [Google Cloud console](https://console.cloud.google.com/), create a project.
2. Under **APIs & Services → Library**, enable the **Google Calendar API**, the **Google Tasks
   API** and the **Google Drive API**.
3. Under **Google Auth platform** (OAuth consent screen), configure the app: choose **Internal** if
   the project belongs to your Google Workspace organization, otherwise **External** and keep it in
   **Testing** with your Google account added as a test user. Add exactly three scopes:
   `https://www.googleapis.com/auth/calendar.readonly`,
   `https://www.googleapis.com/auth/tasks.readonly` and
   `https://www.googleapis.com/auth/drive` (Magenda lists your Drive's folders so you can pick one, and writes only the day's PDF
   and Doc; ADR 0051). Google lists `drive` as a restricted scope: keep the client in Testing
   or Internal, as above, because an External client in production needs Google's
   verification.
   After an update that added a scope, Magenda asks you to sign in again.
4. Under **Clients**, create an OAuth client of type **iOS** with the bundle ID `name.tkcs.magenda`.
5. Open Magenda, enter the client ID (it looks like `123456789012-test.apps.googleusercontent.com`)
   on the "Connect Google" screen and sign in. Fill in the client secret only for a client type
   that has one; an iOS client has none. Both stay in the device's Keychain and go nowhere but
   Google. Settings → Google client changes or forgets them.

An External client in Testing mode makes Google expire the sign-in after 7 days; sign in again when
the app asks. A Google Workspace whose admin restricts third-party apps shows an "access blocked"
page until the admin trusts the client ID.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘R | Render |
| ⌘[ | Previous day |
| ⌘] | Next day |
| ⌘⇧R | Reload |
| ⌘⌥] | Next working day |
| ⌘, | Settings |
| ⌘Return | Save in the Edit sheet |
| Esc | Cancel in the Edit sheet |

Hold ⌘ on an iPad to see them.

## Build and run

You need a Mac with Xcode (with the iOS simulator runtimes) and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate            # writes Magenda.xcodeproj from project.yml
open Magenda.xcodeproj
```

The `.xcodeproj` is generated and never committed (ADR 0003): run `xcodegen generate` again after
a pull that changed `project.yml`, and make project changes in `project.yml`, not in Xcode's
project editor.

The app's logic is in `AppCore/`, a Swift package that also builds on Linux (ADR 0007):

```bash
swift test --package-path AppCore
```

## Layout

| Path | What it is |
|---|---|
| `App/` | The SwiftUI app: views, navigation, assets |
| `App/Screens/` | One SwiftUI screen per file, including the iPad binder, and the Agenda menu's keyboard shortcuts |
| `App/Rendering/` | CoreText measuring, `PageDrawer`, which draws a page on screen and into the PDF, and the PDF renderer that executes AppCore's render plan |
| `App/Platform/` | The Keychain, `UserDefaults`, HTTP and hashing behind AppCore's protocols |
| `App/Resources/` | The vendored template `chrome.pdf` and the OFL fonts (ADR 0011) |
| `AppCore/` | The app's logic, as a Swift package with its own tests: agenda model, layout, Google clients, settings and binder rules, draft building, the binder's days and pages, controller |
| `AppTests/` | Tests that run inside the built app on a simulator |
| `AppUITests/` | UI tests that drive the app on a simulator |
| `project.yml` | The Xcode project's specification (XcodeGen) |
| `scripts/` | Release, coverage and simulator helpers, with their tests |

## Documentation

- [`docs/README.md`](docs/README.md) — index of the contributor docs.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how to contribute.
- [`CHANGELOG.md`](CHANGELOG.md) — what changed in each release.
