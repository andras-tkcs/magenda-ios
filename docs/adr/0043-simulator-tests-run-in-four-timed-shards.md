# ADR 0043: Simulator tests run as four shards balanced from measured timings, and each shard builds once

## Status

Accepted — 2026-10-27. Implemented. The run-time targets it set (a run in 20 minutes or less, no
macOS job over 18) are not met on the hosted runners; see Consequences.
Amended by [0045](0045-simulator-shards-get-a-warm-up-launch-one-retry-and-a-40-minute-limit.md)
(the warm-up launch, the retry of a lost simulator, and the 40-minute job limit).

## Context

Before this decision a green `tests.yml` run took over three hours (run 40294684850): sixteen macOS
jobs, each generating the project and building for itself, behind a cap of five concurrent macOS
jobs. The iPad UI tests took 3,646 s in all, and two classes, Rules and Settings, were 61% of that.
The hosted tests took 18 s, but the separate `app` job spent about 3 minutes booting a simulator
for them.

After the UI tests were made cheaper ([ADR 0044](0044-ui-tests-start-in-the-screen-they-test.md))
the tests still total about 3,400 s. Per-step costs on the hosted runners are about four times what
was assumed: a query takes 1–4 s, a launch about 11.5 s, a tap on a text field 9–17 s, and the
first launch on a cold simulator up to 160 s. Each job also spends about 430 s (250–550 s) outside
the tests, on checkout, `xcodegen`, the simulator pick, the build, the boot and `xcodebuild`
start-up.

## Decision

1. `tests.yml` has one simulator job, `ui`, with four shards. Each shard generates the project,
   builds for testing once, boots its simulator after the build and waits for the boot
   (`xcrun simctl bootstatus -b`), then runs its share of `MagendaTests` and the UI tests. The
   separate `app` job is gone.
2. `scripts/ui_shards.py` chooses a shard's tests. `CLASS_SECONDS` holds the median seconds each
   entry took over measured green runs (40421450881, 40428109901, 40428155713, 40434325760,
   40440931951 and 40447182533), and a longest-first split balances the shards. An entry is the
   hosted tests, a UI test class, or one test method of a class that is too long for one shard
   (Rules and Settings, each over 630 s). The shards come out at 840–860 s of tests each. The
   `scripts` job fails when a UI test class or method has no entry.
3. Each job times out after 30 minutes, and `xcodebuild` runs with
   `-default-test-execution-time-allowance 600` and `-maximum-test-execution-time-allowance 1200`,
   so a hung test fails the shard and does not wait for the job limit.
4. A new push to a pull request, or a new dispatch on the same branch, cancels the stale run.
   Pushes and the weekly run have groups of their own and are never cancelled.
5. The app scheme gathers no coverage. The coverage ratchet is AppCore's
   ([ADR 0007](0007-logic-lives-in-a-platform-independent-swift-package.md)), and instrumentation
   slows both the build and the UI tests.
6. The required checks are the seven that `REQUIRED_STATUS_CHECKS` in
   `scripts/update_branch_protection.py` lists: `core`, `lint`, `scripts`, and `ui (ipad, newest, 1)`
   to `ui (ipad, newest, 4)`. A maintainer applies the list by hand.

## Alternatives considered

- **A fifth shard, or more shards or sessions** — at about 680 s of tests per shard the jobs would
  take about 18.5 minutes, but five jobs use the whole macOS concurrency cap of 5, so another run
  queues behind them, and a fifth job pays about 7 more minutes of fixed cost. Every extra job pays
  that cost again.
- **Parallel testing on cloned simulators in one runner** (`-parallel-testing-enabled`) — hosted
  macOS runners have 3 cores and 7 GB of memory, and two iPad simulators on one make launch
  time-outs likelier.
- **One build job handing its products to the test jobs** — it adds a serial job and a transfer of
  several hundred MB, to save about a minute of build per shard.
- **Retrying failed tests** (`-retry-tests-on-failure`) — it hides a missing wait. The time
  allowances make a hung test fail fast instead; a failed shard is re-run on its own.
- **Pinning the runner image** — `build.yml` archives on `macos-latest`, so tests on another image
  would test a different Xcode than the one that ships.

## Consequences

- A green run took over three hours before; it now takes about 22–25 minutes of wall time (runs
  40447182533: jobs of 15 m 00 s, 19 m 17 s, 22 m 14 s and 18 m 39 s, wall time 22 m 14 s;
  40440931951: 25 m 26 s, 14 m 19 s, 11 m 42 s and 10 m 28 s, wall time 25 m 27 s). A job takes
  10–15 minutes on a fast runner and 19–25 on a slow one, about 21 on a typical runner.
- The targets set when this was decided, a run in 20 minutes or less and no macOS job over 18, are
  **not met** on these runners. Four shards of 840–860 s plus 430 s of fixed cost come to about 21
  minutes. A fifth shard was rejected for the reasons above. What could close the gap later: cheaper
  per-step cost (fewer queries, fewer launches), fewer text-field-heavy tests, or a larger runner.
- The 30-minute job limit is above the 25 first planned, because a slow runner passes in about 27.
- `CLASS_SECONDS` needs refreshing from a green run when the shards' jobs drift more than a few
  minutes apart or one nears the limit; `python3 scripts/ui_shards.py --table` shows the split.
- A failed shard is re-run on its own, and the other three stay green.
- Changing the number of shards changes the required checks and this ADR's reasoning.

## Verification

- `.github/workflows/tests.yml`: the `ui` job, its `concurrency` group, its time limits.
- `scripts/ui_shards.py` and `scripts/tests/test_ui_shards.py`: the timings, the split, and the
  checks that the workflow's `shard:` list and the required checks agree with `SHARD_COUNT`.
- `project.yml`: `gatherCoverageData: false` on the Magenda scheme.

## Related

- [ADR 0041](0041-magenda-is-an-ipad-app.md)
- [ADR 0042](0042-pull-requests-test-the-newest-ipad-runtime.md)
- [ADR 0044](0044-ui-tests-start-in-the-screen-they-test.md)
- Runs [40447182533](https://github.com/andras-tkcs/magenda-ios/actions/runs/40447182533) and
  [40440931951](https://github.com/andras-tkcs/magenda-ios/actions/runs/40440931951)
