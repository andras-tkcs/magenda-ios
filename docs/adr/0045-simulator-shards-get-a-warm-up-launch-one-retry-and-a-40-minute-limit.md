# ADR 0045: Each simulator shard warms the app up before its tests, retries a lost simulator once, and has a 40-minute limit

## Status

Accepted — 2026-10-27. Implemented.
Amends [0043](0043-simulator-tests-run-in-four-timed-shards.md).

## Context

On the hosted macOS runners the four shards of
[ADR 0043](0043-simulator-tests-run-in-four-timed-shards.md) failed for reasons that were not the
tests' own (runs 40466925355 and 40467180761, both on one commit):

- The first test of a shard failed with "Timed out while launching application via Xcode" after
  64 s. The first launch of the app on a just-booted simulator can take longer than XCTest's
  launch time-out, and that launch happens before `launchMagenda` can wait for anything.
- `xcodebuild test-without-building` failed with "Unable to find a device matching the provided
  destination specifier" although the boot step had just booted that device: the runner's
  simulator service lost it between the two steps.
- A shard was cancelled by the 30-minute job limit while its tests were still passing. Its
  simulator took 7 minutes to boot, and its tests ran 1.5 times slower than the same tests on
  another runner. The timings `CLASS_SECONDS` held had also fallen behind: the shards ran 590 to
  1,190 s of tests where the split expected 840 to 860.

## Decision

1. After `xcrun simctl bootstatus -b`, the boot step installs the built app and launches it once
   on its `standard` fixture with `xcrun simctl launch`, then terminates it, so the cold first
   launch is paid outside the tests. A failed warm-up launch is a warning, not a failure.
2. A boot that fails is retried once, after the device is erased.
3. When `xcodebuild` exits 70 (it cannot find the destination), the test step picks the simulator
   again with `scripts/simulator.py`, waits for its boot, and runs the shard's tests once more. Any
   other exit, including a failed test (65), ends the step: tests are never retried.
4. `CLASS_SECONDS` is refreshed from those two runs. The shards come out at 950–970 s of tests each.
5. The `ui` job's limit is 40 minutes. A typical shard takes about 26: some 10 minutes of build,
   boot and `xcodebuild` start-up, then about 16 of tests. A slow runner's 7-minute boot and 1.5
   times slower tests come to about 38.

## Alternatives considered

- **Keep the 30-minute limit** — a healthy shard on a slow runner is cancelled, and a cancelled
  required check is as red as a failed one. The limit is a guard against a hung job; the per-test
  time allowances (600 s, at most 1,200 s) already end a hung test long before 40 minutes.
- **A fifth shard** — rejected in ADR 0043: five macOS jobs use the whole concurrency cap, and
  each one pays the fixed cost again.
- **Retrying the launch inside `launchMagenda`** — XCTest records a launch time-out as a failure of
  the test, so a retry inside the test cannot make it pass without hiding the failure.
- **Retrying failed tests** (`-retry-tests-on-failure`) — still rejected: it hides a missing wait.

## Consequences

- A shard's job takes longer than ADR 0043 expected, about 26 minutes on a typical runner, and a
  run's wall time is that of its slowest shard.
- A lost simulator or a cold first launch no longer fails a shard; a real test failure still does,
  on its first run.
- `CLASS_SECONDS` needs refreshing when the shards drift apart, as ADR 0043 says.

## Verification

- `.github/workflows/tests.yml`: the `ui` job's `timeout-minutes`, its boot step and its test step.
- `scripts/ui_shards.py` (`--table`) and `scripts/tests/test_ui_shards.py`.

## Related

- [ADR 0043](0043-simulator-tests-run-in-four-timed-shards.md)
- Runs [40466925355](https://github.com/andras-tkcs/magenda-ios/actions/runs/40466925355) and
  [40467180761](https://github.com/andras-tkcs/magenda-ios/actions/runs/40467180761)
