# ADR 0021: A binder day is stored as a content snapshot and ink per page key

## Status

Accepted — 2026-10-22. Implemented.
Qualifies [ADR 0014](0014-agenda-inputs-come-live-from-google-calendar-and-google-tasks.md): a
started day opens without a network connection.

## Context

The agenda pipeline runs one way and is rebuilt on every load: Google data, the draft, the content,
the layout, the plan. Nothing but settings and tokens was stored, pages were addressed by index
(`PagePlan` had no identity) and the content types could not be encoded. Handwriting has to stay
with its page when the day is rendered again, even if a meeting was added before it, and has to
survive relaunches and being offline.

## Decision

1. **Page keys.** Every page has a stable `PageKey` (`AppCore/Sources/Layout/PageKey.swift`):
   `overview`, `delegated(n)`, `meeting(eventID)`, `notes`, `extra(id)`. It has a string form for
   storage; a string that does not parse is rejected.
2. **The day.** A `BinderDay` (`AppCore/Sources/Binder/BinderDay.swift`) holds the content taken
   at Render, the theme, the pages the person added and the pages kept for their handwriting. It
   carries a format version, and decoding any other version fails. The plan is not stored: the
   content and theme lay out to the same plan.
3. **The store.** A `BinderStore` (`AppCore/Sources/Binder/BinderStore.swift`) keeps, per day, one
   `day.json` and one file of opaque PencilKit data per page key, in generated file names behind
   an `index.json` mapping each key's string to its file. `FileBinderStore` is rooted in
   Application Support (`App/AppEnvironment.swift`). Every write is atomic; an unreadable file
   throws and an index entry that does not parse, does not match the generated name pattern or has
   no file is skipped. Empty ink deletes the page's file.
4. **Rendering again.** `BinderLayout.rebased` (`AppCore/Sources/Binder/BinderLayout.swift`)
   moves the day onto the new content. A page that carries ink and left the content is kept with
   the content it was laid out from, after the remaining pages of its kind; a page without ink
   goes. Added pages follow the page they were added after, or their source page when that is
   gone.
5. **Opening.** The controller opens the stored day before it fetches from Google, so a started
   day shows offline (`AppCore/Sources/Controller/AgendaController.swift`).
6. **Saving.** `BinderSession` (`AppCore/Sources/Binder/BinderSession.swift`) saves ink and added
   pages as they change and shows a message when a save fails.

## Alternatives considered

- **Page identity by index.** One added meeting would move every later page's ink.
- **Storing a rendered plan.** It is not `Codable`, and the content and theme re-lay out to the
  same plan.
- **All of a day's ink in one file.** Every stroke would rewrite every page's drawing.
- **File names from the page key.** Google IDs are untrusted and can exceed file-name limits;
  generated names behind an index avoid both.
- **Core Data or SwiftData.** They are Apple-only, so untestable in AppCore on Linux, for a few
  files a day.
- **Locking a day once it has ink.** Rendering again keeps the ink by page instead.

## Consequences

- Storage grows with every started day. A stored day is kept on the device until a later release
  confirms it has been exported.
- `BinderDay.formatVersion` is 1. A day written by a different version cannot be decoded, and the app
  reports that the saved binder can't be read.
- [ADR 0014](0014-agenda-inputs-come-live-from-google-calendar-and-google-tasks.md) says the
  agenda is read live; it still is on every Render, but a started day opens from the device first.
- The user's Google-derived content (meeting titles, attendees' names, tasks) now sits on the
  device in Application Support, which is included in device backups.
- Ink stays in the store under its key whether or not the key is still shown.

## Verification

- `AppCore/Sources/Layout/PageKey.swift`, `AppCore/Sources/Binder/BinderDay.swift`,
  `AppCore/Sources/Binder/BinderStore.swift`, `AppCore/Sources/Binder/BinderLayout.swift`,
  `AppCore/Sources/Binder/BinderSession.swift`, `App/AppEnvironment.swift`.
- `AppCore/Tests/Layout/PageKeyTests.swift`, `AppCore/Tests/Binder/BinderDayTests.swift`,
  `AppCore/Tests/Binder/BinderStoreTests.swift`, `AppCore/Tests/Binder/BinderLayoutTests.swift`,
  `AppCore/Tests/Binder/BinderSessionTests.swift`, `AppUITests/BinderUITests.swift`.

## Related

- [ADR 0014](0014-agenda-inputs-come-live-from-google-calendar-and-google-tasks.md),
  [ADR 0020](0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md).
