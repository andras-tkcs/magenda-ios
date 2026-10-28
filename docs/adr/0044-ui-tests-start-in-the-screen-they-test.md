# ADR 0044: UI tests start in the screen they test, with animations off, through launch arguments that only a fixture launch reads

## Status

Accepted — 2026-10-27. Implemented.
Amended by [0047](0047-every-ui-test-launch-waits-for-the-app-window.md).

## Context

The iPad UI tests took 3,646 s (61 minutes) in run 40294684850, and most of it was not testing.
Every Rules test opened the Settings sheet and scrolled to the rules link first. The scroll-to-reveal
loops cost about 1,000 s (one iteration about 8.5 s), the waits inside them that missed another
620 s (a missed `waitForExistence` costs about 4 s, because XCTest captures an element description),
animations about 200 s, and the 60 launches about 700 s.

## Decision

1. A fixture launch (`-MagendaFixture <name>`) reads two more arguments through `LaunchOptions` in
   AppCore: `-MagendaOpen settings|rules` opens the settings sheet, or the binder rules inside it,
   and `-MagendaNoAnimations` turns animations off with `UIView.setAnimationsEnabled(false)`. An
   unknown screen name, or `-MagendaOpen` with nothing after it, opens nothing. A real launch builds
   its services with `LaunchOptions.standard` and never honours either argument.
2. `LaunchRequest` hands the requested screen out once, so a view rebuilt after setup or sign-in
   does not open it again. `AgendaView` presents the settings sheet as an item (a `SettingsSheet`
   enum with `.sheet(item:)`): a pair of flags built the sheet with a stale value.
3. `AppUITests/MagendaUI.swift` holds the steps every UI test shares: `launchMagenda` (fixture,
   no animations, extra arguments; the first launch of a run waits up to 180 s for the app window,
   because a cold simulator can go a minute without answering), `element(_:)`, `waitUntil`,
   `scrollContent(by:)` and `reveal(in:)`. `reveal(in:)` is bounded and searches downward first, so
   a test scrolls toward a target above first.
4. Inside a scroll loop a test reads `.exists`, not `waitForExistence`. A retry loop around a tap
   keeps `waitForExistence`, because it gives the tap time to land. Typed queries stay as written;
   untyped ones cost about 0.5 s each, about 70 s in all.
5. Rules tests launch with `-MagendaOpen rules`, and Settings tests with `-MagendaOpen settings`
   unless they test getting there from the agenda.

## Alternatives considered

- **Keep tapping through the agenda in every test** — the path is tested once; repeating it in
  every Rules test is most of their cost.
- **A debug menu or a build flag** — the arguments are read only on a fixture launch, so they need
  neither.
- **Fixed sleeps for the slow steps** — they hide a missing wait, which the steward skill forbids.
- **Retyping every query** — it saves about 70 s in all, and each wrong guess costs a CI round.

## Consequences

- The UI tests no longer exercise animations. A page turn or an undo scroll is tested with
  animations off, and a test that fails that way is fixed by its wait, not by turning them on.
- A new test of a screen reachable from `-MagendaOpen` should use it. A new screen worth opening
  directly adds a case to `LaunchOptions.Screen`.
- With these changes the total UI test time is about 3,400 s on the hosted runners
  ([ADR 0043](0043-simulator-tests-run-in-four-timed-shards.md)), down from 4,900 s scaled to the
  same tests.

## Verification

- `AppCore/Tests/Controller/LaunchOptionsTests.swift`, and `AppUITests/LaunchOptionsUITests.swift`
  on a simulator.
- `App/LaunchRequest.swift`, `App/AppEnvironment.swift` (the live branch uses `.standard`) and
  `App/MagendaApp.swift`.

## Related

- [ADR 0041](0041-magenda-is-an-ipad-app.md)
- [ADR 0043](0043-simulator-tests-run-in-four-timed-shards.md)
