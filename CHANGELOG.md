# Changelog

<!--
HOW TO USE THIS FILE

1. `## [Unreleased]` is permanent. A feature branch adds its user-visible change under that
   heading and nothing else. Do NOT open a concrete `## [X.Y.Z]` heading on a feature branch: two
   branches in flight would both claim the same next version. Only the PR that prepares a release
   turns `## [Unreleased]` into `## [X.Y.Z] — YYYY-MM-DD`, adds a fresh empty `## [Unreleased]`
   above it, and updates the link definitions at the bottom. If a section for that version already
   exists, MERGE `[Unreleased]`'s entries into it and fix its date; renaming would create a second
   heading, and scripts/changelog_section.py refuses to render a version that has two.

2. This file is NEVER a version source. The git tag is the only one (docs/releasing.md).
   scripts/changelog_section.py reads a version's section *out* of this file to produce the GitHub
   Release body for that tag.

3. Pre-release tags (-alpha.N/-beta.N/-rc.N) get no section of their own; their content folds
   into the version they lead to, per Keep a Changelog.

4. A version that was tagged but never shipped to the App Store gets no section either. Fold its
   entries into the version that does ship and say so at the top of that section.

5. Write entries for the people who use the app: what they can now do, or what behaves
   differently, in plain words. Internal refactors and test-only changes need no entry.
-->

All notable changes to Magenda are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- On iPad, Render opens the day's binder: one whole page at a time, swiped left and right. Write on
  its pages with Apple Pencil, and the handwriting is saved with the day, also offline once the day
  is started.
- The binder toolbar has black, blue, red and green pens, an eraser, undo and redo, buttons to jump
  to the overview, delegated tasks and notes, Add page, which puts a blank copy of the current page
  after it (titled "cont." before the meeting's title on a meeting page), and Delete page, which
  removes a page you added after asking. Undo and redo reach every page you wrote on since the day
  was opened, and go to the page they change. Undo and Redo are greyed out when there is
  nothing to undo or redo.
- Double-tap the Apple Pencil (or squeeze a Pencil Pro) to switch between the pen and the eraser.
- Share PDF in the binder shares the day with your handwriting on its pages.
- The binder's saved handwriting and the PDFs it shares can't be read while the device is locked.
- Rendering a day again keeps your handwriting on its pages; a meeting page you wrote on stays even
  when the meeting is no longer on the agenda.
- Start over, on a started day, deletes all of its handwriting and added pages after asking and
  renders it fresh.
- Finish Day, in the binder, uploads the day as a PDF to a `Magenda` folder in your Google Drive,
  creates the day's notes Doc next to it and starts your end-of-day Claude routine. Enter the
  routine's fire URL and token in Settings → End-of-day routine. A day finished offline is sent
  when the app is next active.
- Reset Hand-off, in the binder of a finished day, forgets that the day was sent after asking, so
  Finish Day works again. The PDF and Doc already in Drive stay, and the next finish creates a new
  Doc.
- Send Meeting, on a meeting page in the binder, sends that meeting before the day ends with its
  own PDF and Google Doc and its own row in Review, and locks its pages. Finish Day skips it in
  the notes.
- The Review list, from the agenda's toolbar, shows each finished day's state, opens its Doc with
  Open Doc, and has the Try again, Approve notes or Approve button the state calls for.
- Summary skills: map a meeting title to a skill under Settings → Binder rules → Meeting
  summaries. Every meeting page prints a Summary line, with the skill on it, or ruled so you can
  write one.
- Settings → Binder rules has an Edit button, and a long press on a rule offers Delete, for the
  built-in entries such as PTO as well as the ones you added.
- Settings → Binder rules → People can fill in a name and email from your contacts with Choose from
  Contacts….
- Settings → Google Drive shows and lets you rename the folder finished days are uploaded to. Days
  already uploaded stay in their folder.

### Changed

- A closed day's handwriting and stored PDF are deleted from the device five days after the day is
  closed. A small record of the day stays.
- Magenda now asks for access to the files it creates in Google Drive, so sign in again after
  updating. Enable the Google Drive API and add the `drive.file` scope in your Google Cloud
  project.
- The end-of-day routine must be updated to payload schema `magenda.end-of-day/2`
  (docs/end-of-day-handoff.md); until it is, it stops on every payload.

## [0.1.1] — 2026-10-15

First stable release. It also carries everything from the 0.1.0 alpha, which was never shipped.

### Fixed

- The links in the PDF now work: "overview", "notes" and each schedule entry jump to their page.
  They were tappable in the wrong place before.

### Added

- An app icon.
- Sign in with Google and build your daily binder from Google Calendar and your "Claude" and
  "Claude Delegations" task lists, with fixed rules and no AI.
- Every item that is left out shows why ("Declined", "Personal block", "No other attendees",
  "Overdue", "Check-in due" and more).
- Editable binder rules: personal blocks, title prefixes, out-of-office words, short meeting names,
  people for "to be discussed" tasks, and the number of look-ahead days.
- Untick or edit any item before rendering; nothing is changed in Google.
- Enter your own Google client on first launch; it is kept in the Keychain and never leaves the
  device except to talk to Google.
- Preview the PDF beside the list on iPad, and share it to Noteshelf or anywhere else.
- Keyboard shortcuts for rendering, changing the day and reloading.
- Choose the font and the colors of the agenda.
- Long titles are shortened with "…" and to-dos that don't fit are listed under the preview.
- A GitHub Release can attach a signed .ipa for registered devices, when the maintainer turns it on.

[Unreleased]: https://github.com/andras-tkcs/magenda-ios/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/andras-tkcs/magenda-ios/releases/tag/v0.1.1
