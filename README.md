# Magenda

An iPad-first app that builds the daily binder from Google Calendar and Google Tasks. Sign in with
Google, pick a day, review what the app selected and why, untick or edit anything, render the
agenda as a PDF, preview it beside the list (on iPad, open it as a binder you write in) and share
it to Noteshelf or anywhere else. The rules
are fixed and editable, and no AI is involved (ADR 0016). The app also runs on iPhone.

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
  matched under Settings → Binder rules → People. Otherwise it is listed unticked with the reason.
- A task's notes take one line; a task that does not fit the list is left off the PDF and listed in
  a banner under the preview (on iPad, under the binder's toolbar).

## Binder (iPad)

On iPad, Render opens the day's binder: the same pages as the PDF, drawn in the app, with Apple
Pencil handwriting on each one. The toolbar has black, blue, red and green pens, an eraser, undo and
redo, buttons that jump to the overview, the delegated tasks and the notes, and Add page, which puts
a blank copy of the current page after it. Tapping a link on a page follows it. Share PDF shares the
day with your handwriting on its pages.

Handwriting is saved on the device per page. Rendering the day again keeps it on its page, and a
meeting page you wrote on stays even when the meeting has left the agenda. Once a day is started, it
opens without a network connection. The iPhone shows the PDF preview (ADR 0020, ADR 0021).

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
2. Under **APIs & Services → Library**, enable the **Google Calendar API** and the **Google Tasks
   API**.
3. Under **Google Auth platform** (OAuth consent screen), configure the app: choose **Internal** if
   the project belongs to your Google Workspace organization, otherwise **External** and keep it in
   **Testing** with your Google account added as a test user. Add exactly two scopes:
   `https://www.googleapis.com/auth/calendar.readonly` and
   `https://www.googleapis.com/auth/tasks.readonly`.
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
