# ADR 0038: Summaries are written by dedicated summary routines that Magenda starts when the notes are approved

## Status

Accepted — 2026-10-26. Implemented.
Amends [ADR 0031](0031-meeting-summaries-are-requested-by-skill.md): decisions 1 to 4; decision 5 (task IDs) stays.
Amends [ADR 0028](0028-the-end-of-day-routine-is-started-through-its-api-trigger.md): several routines, each with its own token.
Amended by [ADR 0052](0052-summary-rules-can-match-titles-with-a-regular-expression.md): rules match exact titles or patterns.

## Context

The end-of-day routine did everything after a day was sent: the notes, any summaries, the Google
Tasks updates and the Gmail drafts. A routine started through an API trigger then held every
permission those jobs need, and one place wrote other assets with several summary skills chosen by
a name typed in the binder rules or handwritten on the page. The person does not want one routine
with that much access.

## Decision

1. Each kind of summary is its own summary routine: a Claude routine with its own API trigger and
   its own token. The person adds it once in Settings → Summary routines with a name, the fire URL
   and the token. The name is 1 to 40 characters. Magenda gives the routine a lowercase UUID that
   never changes; the URL and token are kept in the Keychain under that ID, and the ID and name in
   the settings.
2. A meeting asks for summaries with checkboxes, any number of them. The person ticks routines per
   meeting title in Settings → Binder rules → Meeting summaries, or for one meeting on its Edit
   sheet. A title rule matches the meeting's title as shown or as it was on the calendar, compared
   folded.
3. The meeting page prints `Summary:` and the ticked routines' names on one line, and nothing when
   none is ticked. The page, and the hand-off, use the names as they were when the day was rendered.
4. After the person taps Approve notes, Magenda starts each ticked routine once, in the order the
   routines were added, each with a payload naming only the meetings it summarizes. When no meeting
   asked for a summary, Approve notes starts the end-of-day routine's `close` step directly.
5. Magenda never starts a routine twice by itself. It records each routine it started; a failed
   start leaves the day waiting, and Try again starts only the routines not yet started.
6. Saving a name that already exists replaces that routine's URL and token under the same ID, so a
   regenerated token or a lost Keychain item is fixed without losing the routine's rules.
   Forgetting a routine deletes its credentials and removes it from every rule.
7. Summary skills typed in the binder rules, and the skill name carried in the payload, are gone.
   Nothing migrates them: a skill name names no routine.

## Alternatives considered

- **One routine doing everything** — the permission scheme the person refused.
- **Ticking boxes on the printed page with the Pencil** — Magenda cannot read ink, so the
  end-of-day routine would have to report back what was ticked.
- **Keeping the typed skill name beside the checkboxes** — two sources of truth for one meeting.
- **Keeping the routines with their tokens in the settings** — the settings are not a secret store.
- **One Keychain item holding every token** — one failed write would lose them all.
- **Using the trigger's ID as the routine ID** — it changes when the trigger is regenerated.

## Consequences

- Each summary routine can be given only the access its summary needs, and the end-of-day routine
  no longer writes summaries.
- Magenda now holds several narrowly scoped tokens, one per routine, and the person sets each routine
  up by hand.
- A binder day that was open during the update loses its `Summary:` line and the ruled line,
  because a day is laid out again from its stored content whenever it is opened. Handwriting on
  that line stays where it was.
- A day sent before a routine was forgotten keeps that routine's name and ID in its pages. Starting
  it then fails with a message, and Reset Hand-off ([ADR 0032](0032-a-sent-days-hand-off-can-be-reset-after-asking.md))
  is the way out.

## Verification

`AppCore/Sources/Settings/SummaryRoutine.swift`, `AppCore/Sources/Settings/AgendaSettings.swift`,
`AppCore/Sources/Settings/BinderRules.swift`, `AppCore/Sources/Handoff/SummaryRoutineTrigger.swift`,
`AppCore/Sources/Handoff/HandoffController.swift`, `AppCore/Sources/Draft/AgendaDraft.swift`,
`AppCore/Sources/Layout/AgendaLayout.swift`, `App/Platform/KeychainSummaryRoutineCredentialsStore.swift`,
`App/Screens/SettingsView.swift`, `App/Screens/RulesView.swift`, `AppCore/Tests/Settings/SummaryRoutineTests.swift`,
`AppCore/Tests/Handoff/SummaryRoutineTriggerTests.swift`, `AppCore/Tests/Handoff/HandoffControllerTests.swift`,
`AppUITests/SettingsUITests.swift`, `AppUITests/RulesUITests.swift`, and the 100 % file floors in
`scripts/check_coverage_floor.py`.

## Related

[ADR 0028](0028-the-end-of-day-routine-is-started-through-its-api-trigger.md),
[ADR 0031](0031-meeting-summaries-are-requested-by-skill.md),
[ADR 0039](0039-a-summary-announces-itself-in-the-doc-with-a-marker-line.md),
[ADR 0040](0040-the-routine-payload-moves-to-schema-3-and-summaries-have-their-own-schema.md),
[`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
