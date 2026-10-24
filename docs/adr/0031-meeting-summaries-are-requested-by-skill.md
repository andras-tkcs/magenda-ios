# ADR 0031: A meeting's summary is requested with a title-to-skill map in the rules, or by writing a skill on its page

## Status

Accepted — 2026-10-24. Implemented.

## Context

Some meetings need a summary written with a specific Claude skill, others need none. The routine
has to learn which, per meeting, from the day's PDF and its payload, and the person has to be able
to decide for a one-off meeting without opening Settings.

## Decision

1. The binder rules gain `summarySkills`, a map from a meeting title as entered to a skill name. It
   is edited in Settings → Binder rules → Meeting summaries. A skill name is 1 to 64 characters,
   the first an ASCII letter or digit, the rest ASCII letters, digits, `-`, `_`, `:` or `.`. Titles
   are folded (case and diacritics) before they are compared; a meeting matches by its page title
   or its original title, and the first matching title wins.
2. Every meeting page prints a `Summary:` line below its title. When a skill is mapped, its name
   follows the label. Otherwise the line is ruled, and the person writes a skill name there by hand
   for a one-off meeting.
3. The skill travels with the content. A day's content snapshot stores one skill per meeting
   (`meetingSummarySkills`, read as empty from days stored without it), and the payload carries
   `summarySkill` on the meeting's page entry. The routine reads both the payload and the printed
   or handwritten line.
4. After `approve-notes`, a day with a mapped skill goes to `Summary ready for review`; a day with
   none closes.
5. Task IDs are carried into the content too (`taskID` on to-do and delegated rows), so the routine
   can update the right Google Task.
6. Reset rules keeps `summarySkills`, as it keeps the short names.

## Alternatives considered

- **A per-day "needs summary" toggle or a printed checkbox** — a summary needs a specific skill, so
  a yes/no is not enough.
- **Choosing the skill in the routine only** — the person has no way to say it for a one-off
  meeting, and the rule belongs with the other title rules.

## Consequences

- The meeting page has a new printed line; days laid out before it keep the layout they were
  stored with.
- A handwritten skill name is read by the routine from the PDF, so it is as reliable as the
  handwriting.
- The skill names are not checked against the person's real skills.

## Verification

`AppCore/Sources/Settings/SummarySkill.swift`, `AppCore/Sources/Settings/BinderRules.swift`,
`AppCore/Sources/Agenda/AgendaContent.swift`, `AppCore/Sources/Draft/AgendaDraft.swift`,
`AppCore/Sources/Layout/AgendaLayout.swift`, `App/Screens/RulesView.swift`,
`AppCore/Tests/Settings/SummarySkillTests.swift`, `AppCore/Tests/Layout/AgendaLayoutTests.swift`,
`AppCore/Tests/Binder/BinderLayoutTests.swift`, `AppUITests/RulesUITests.swift`.

## Related

[ADR 0016](0016-agenda-selection-uses-editable-rules-not-a-language-model.md),
[ADR 0028](0028-the-end-of-day-routine-is-started-through-its-api-trigger.md),
[`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
