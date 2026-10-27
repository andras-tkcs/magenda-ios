# ADR 0037: People rules are filled from the system contact picker

## Status

Accepted — 2026-10-26. Implemented.

## Context

Settings → Binder rules → People maps a name used in tasks to the attendee email it stands for,
so a task for "Sam" matches an invited "Samuel". Both were typed by hand. The person wanted to
take them from their contacts.

## Decision

1. The People section has a Choose from Contacts… button. It presents the system contact picker
   (`CNContactPickerViewController`) restricted to contacts with an email address, and fills the
   name and email fields with the picked contact's name and address. The person can still change
   both before adding.
2. Magenda does not read the Contacts database. The picker runs out of process and hands back only
   the one entry the person chose, so the app asks for no Contacts permission, needs no usage
   description and adds nothing to its App Store privacy answers. The picked email is stored in the
   settings as a typed one is.
3. The picker is behind an environment value, so the UI tests replace it with a fixture.

## Alternatives considered

- **Live autocomplete from the Contacts database** — needs `CNContactStore` access, the
  permission prompt, a usage string and App Store privacy answers, for a list typed a handful of
  times.
- **Google People API or the Workspace directory** — a fourth OAuth scope, so everyone signs in
  again as with ADR 0027, and a change in the Cloud console.
- **Suggesting from meeting attendees** — only covers people already met, and attendees carry no
  first names.

## Consequences

- The real picker cannot run in CI; it is checked by hand on a device (`docs/release-testing.md`).
- A contact with several addresses lets the person choose one in the picker.

## Verification

`AppCore/Sources/Settings/PersonAlias.swift`, `App/Platform/ContactPicker.swift`,
`App/Screens/RulesView.swift`, `App/MagendaApp.swift`,
`AppCore/Tests/Settings/PersonAliasTests.swift`, `AppUITests/RulesUITests.swift`.

## Related

ADR 0027.
