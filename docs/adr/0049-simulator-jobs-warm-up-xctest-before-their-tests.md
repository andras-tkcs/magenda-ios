# ADR 0049: Simulator jobs warm up XCTest with a throwaway UI test before their tests, and get 45 minutes

## Status

Accepted — 2026-10-28. Implemented. Amends [0045](0045-simulator-shards-get-a-warm-up-launch-one-retry-and-a-40-minute-limit.md).

## Context

In run 40635910398 the first test of `ui (ipad, newest, 2)`,
`BinderUITests.testAddPageAddsAPageAfterTheCurrentOne`, failed with "Failed to get matching
snapshots: Timed out while evaluating UI query" during `launchMagenda`'s first 180 s window wait.
The other 20 tests of the shard passed. The error ended the test at once, although no test sets
`continueAfterFailure = false`. The same kind of failure has hit the first test of a shard before,
despite [ADR 0045](0045-simulator-shards-get-a-warm-up-launch-one-retry-and-a-40-minute-limit.md)'s
`simctl` warm-up launch and [ADR 0047](0047-every-ui-test-launch-waits-for-the-app-window.md)'s
waits: the cold part is XCTest's automation session, not the app.

## Decision

The Tests step of each simulator job first runs one throwaway UI test, `WarmUpUITests`, in its own
`xcodebuild` invocation, and runs it again after a lost simulator is picked and booted again. The
step tolerates that run's failure with a warning. The job's real tests then run in a second
invocation on a warm session and fail as before. The warm-up test launches the app and waits for
its window. It has a 300 s allowance, which covers `launchMagenda`'s 180 s first wait, the test's
own 60 s and the launch, so a hung warm-up fails itself instead of the job.

`WarmUpUITests` has no entry in `CLASS_SECONDS`, is never in a shard, and `--only` rejects it.
No real test is wrapped in an expected failure or can pass without running its body.

The job limit becomes 45 minutes, replacing ADR 0045's 40: about 28 minutes on a typical runner,
and about 43 on a slow one that takes 7 minutes to boot and 5 to warm up.

## Alternatives considered

- **`XCTExpectFailure` around the first window wait** — the snapshot error ends the test, so the
  test would be recorded as an expected failure and pass without running its body: a silently
  skipped test.
- **A separate warm-up step before the Tests step** — it would leave the re-pick path after an
  exit 70 cold again, so the warm-up lives in the Tests step with both calls.
- **Running the warm-up test first in the same `xcodebuild` invocation** (for example, a class
  named to sort first) — XCTest's order is not a contract, and a failed warm-up would fail the
  shard.
- **Longer waits** — the error comes from the first snapshot attempt itself, so a longer wait
  changes nothing (runs 40597112018, 40635910398).
- **Test retries** — [ADR 0043](0043-simulator-tests-run-in-four-timed-shards.md) rejects them.
- **Doing nothing and re-running the shard each time** — each re-run costs 26–40 minutes and
  teaches nothing. Re-running a failed shard stays the response to other failures (ADR 0043).

## Consequences

- Each simulator job takes about 2 minutes longer, and up to about 5 when the warm-up meets a cold
  snapshot.
- That the warm-up carries over to the next `xcodebuild` invocation (a new runner process, the same
  simulator and `testmanagerd`) is a hypothesis. The evidence is the shards' first tests in runs
  with and without the warm-up.
- A real test can still fail on a cold snapshot; that is then a real failure to investigate.

## Verification

- `AppUITests/WarmUpUITests.swift`.
- `warm_up` in `tests.yml`'s Tests step, and its `timeout-minutes`.
- `WARM_UP_CLASS` in `scripts/ui_shards.py`, and its tests in `scripts/tests/test_ui_shards.py`.

Related: [0043](0043-simulator-tests-run-in-four-timed-shards.md),
[0045](0045-simulator-shards-get-a-warm-up-launch-one-retry-and-a-40-minute-limit.md),
[0047](0047-every-ui-test-launch-waits-for-the-app-window.md).
