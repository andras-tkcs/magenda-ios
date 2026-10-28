# ADR 0046: UI tests turn an event off through its context menu, not its switch in the sidebar

## Status

Accepted — 2026-10-27. Implemented.

## Context

`AgendaScreenUITests.testTurningAnEventOffRemovesItsNotesPageSwitch` failed in about one run in
three: five touches on an event's include switch in the agenda list left it on. Diagnostic runs on
the iOS 26 iPad simulator (40503655658 to 40560337286) showed:

- No touch changed the switch's value, even for a moment, so the draft was not edited and then
  overwritten; `AgendaController` loads once, and nothing replaces the draft after an edit.
- The app took the touches: the Settings and Render buttons, and the Rules sheet's switch, answered
  their first tap in the same launches.
- The first tap on a switch in the agenda list almost never toggled it (about 5 of 55 launches),
  turning on or off, on an event or a to-do row. Later touches of any kind (a tap at the middle, on
  the track or on the right half, a short press, a drag of the knob) toggled it only about one time
  in four; in run 40555483784 the fifth knob drag was the first one taken.
- Leaving out, one at a time and together, the list's `.refreshable`, the rows' context menu, hover
  effect and edit button, the switch's `.fixedSize()`, the sidebar's column width, its visibility
  binding and the detail column's content did not help.
- The same list outside the sidebar column, in a `NavigationStack` or in the split view's detail
  column, took the first tap in 5 of 5 launches.

So a synthesized touch on a switch in the `NavigationSplitView` sidebar column is usually not
delivered to it, and nothing in Magenda's own views causes it.

## Decision

The test turns the event off with the row's context menu: it long-presses the row and taps "Leave
out", retrying (at most five times) while the event's notes-page switch is still there, as
`RulesUITests` does for its long-press Delete. The menu's items carry no accessibility identifier,
so "Leave out" is found by its label. The assertion is unchanged: the notes-page switch disappears.
Render in `HandoffUITests` is likewise tapped again while no binder has appeared.

## Alternatives considered

- **More touches on the switch, of more kinds** — every kind was taken about one time in four, so
  any fixed number of retries still fails some runs.
- **Move the review list out of the sidebar** — the only change that made the switch take its first
  tap, but it changes the iPad layout without evidence that people are affected.
- **Skip or loosen the test** — the suite is a 100% pass-rate gate
  (`.claude/skills/steward/SKILL.md`).

## Consequences

- The test no longer touches the include switch itself; it checks the same change to the draft and
  the screen through the menu that calls the same binding.
- Open question: whether a finger's tap on a sidebar switch on a real iPad is also lost. That needs
  a check by hand on a device. If it is lost, it is an app bug, and moving the review list out of
  the sidebar comes back as the fix.

## Verification

- `AppUITests/AgendaScreenUITests.swift`: `testTurningAnEventOffRemovesItsNotesPageSwitch`.
- `AppUITests/HandoffUITests.swift`: `render(_:)`.
