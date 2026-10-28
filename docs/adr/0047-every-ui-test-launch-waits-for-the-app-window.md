# ADR 0047: Every UI test launch waits for the app's window, not only the first

## Status

Accepted — 2026-10-27. Implemented.
Amends [0044](0044-ui-tests-start-in-the-screen-they-test.md).

## Context

ADR 0044 has the first launch of a test run wait up to 180 s for the app's window, because the app
on a freshly booted simulator can go a minute without answering accessibility queries. Later
launches went straight to the test's own waits. In run 40575586977,
`AgendaEditUITests.testOnlyAnEventOffersToRememberItsName` failed with "the list never appeared"
after a mid-shard launch: its first existence check blocked for 29 s, the list was there a moment
after its 30 s wait ran out, and the rest of the test passed. The same kind of stall, while a launch
or a render keeps the app busy, failed `testRenderShowsThePreview` in run 40570877545.

## Decision

`XCUIApplication.launchMagenda` waits for the app's window after every launch: up to 180 s for the
first launch of a run, up to 60 s for each later one. A test's own waits start once the app answers.

## Alternatives considered

- **Longer waits in each test** — every test that waits right after a launch would need it, and a
  new test would repeat the bug.
- **A sleep after launch** — costs every launch the full time, and the repo waits for a condition
  instead (`.claude/skills/steward/SKILL.md`).

## Consequences

- A launch whose app answers at once costs one existence check more.
- A launch whose app never shows a window costs up to 60 s more before the test fails on its own
  wait.

## Verification

- `AppUITests/MagendaUI.swift`: `launchMagenda(fixture:_:)`.
