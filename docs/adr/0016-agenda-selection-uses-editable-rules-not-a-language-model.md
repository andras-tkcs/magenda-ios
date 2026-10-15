# ADR 0016: What goes on the agenda is decided by fixed, editable rules, never by a language model

## Status

Accepted — 2026-10-15. Implemented.

## Context

Building the daily binder takes judgement calls: which events are personal blocks, how to shorten
a long meeting title, which duplicate to keep, which "to be discussed" task to list. The user
wants none of them made by an AI, on or off the device, and wants to see why anything was left out.

## Decision

1. Selection is deterministic code in AppCore (`AgendaBuilder`, `EventSelection`,
   `TaskSelection`) driven by `BinderRules`, which the user edits in Settings → Binder rules:
   personal-block prefixes, title prefixes, out-of-office words, saved short meeting names, person
   aliases and look-ahead days. All text comparison goes through `BinderText`, which ignores case
   and diacritics and matches on word boundaries.
2. The rules replace the judgement calls: personal blocks by editable title prefix; the title
   prefix strip list and a short name saved per recurring meeting; the same `iCalUID`, or the same
   title starting less than 120 minutes after an earlier kept event, is a duplicate; "to be
   discussed" tasks are kept only when that person is in a meeting that day; a manual edit is the
   last resort.
3. Every left-out or changed item stays on the review screen with its reason ("Declined",
   "Personal block", "Duplicate of an earlier event", "Overdue", "Kept: …"); the app does not
   summarize.
4. Out-of-office and weekend dates show a notice and a "Go to next working day" button instead of
   blocking.

## Alternatives considered

- **An on-device language model (Apple Foundation Models) to shorten titles or spot personal
  blocks.** The user asked for no AI at all, and it would make the output depend on a model version
  and on iOS 26 hardware.
- **Personal blocks by calendar color or a tag.** Colors are per-user display settings that other
  tools change, and a tag means editing every recurring event.
- **Duplicates by title across the whole day.** Two "Team sync" events at 09:00 and 15:00 are
  both real.
- **Blocking a weekend or out-of-office date.** The user picked the date, so the app informs and
  offers the next working day.

## Consequences

- The same calendar always yields the same agenda; every difference between two agendas traces to
  a rule or an edit.
- A case the rules miss needs a rule or a manual edit, not a retry.
- Rules are stored in settings; settings from any earlier build still load (missing fields take
  their defaults).

## Verification

`AppCore/Sources/Draft/EventSelection.swift` and `TaskSelection.swift`;
`AppCore/Sources/Settings/BinderText.swift`, `MeetingTitle.swift`, `TaskTitle.swift` (100% floors);
the `standard` fixture in `AppCore/Sources/Controller/GoogleFixtures.swift`;
`AppCore/Tests/Draft/`; `AppUITests/RulesUITests.swift`.

## Related

ADR 0014; README, "What goes on the agenda".
