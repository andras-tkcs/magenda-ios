# ADR 0042: Pull requests test the newest iPad runtime; the oldest supported runtime is tested weekly and in the release pre-flight

## Status

Accepted — 2026-10-27. Implemented.

## Context

Layer 3 of the testing policy proves layers 1 and 2 on the newest and the oldest supported iOS. The
pull-request run did that by running every simulator test on both runtimes. That doubled the macOS
jobs, and macOS jobs are the scarce resource: GitHub runs at most five at once on this account, so
a run of sixteen jobs queued for up to 2 h 20 min and took 3 h 38 min in all (run 40294684850).
Failures that only the oldest runtime shows are rare, and they do not need to block every pull
request to be found.

## Decision

1. A pull request, and a push to `main` or `releases/**`, runs the simulator jobs on the newest
   installed iPad runtime only. The job names are `ui (ipad, newest, 1)` to `ui (ipad, newest, 4)`.
2. The oldest supported runtime, which is the oldest installed one at or above the deployment target
   in `project.yml`, runs on a schedule (Mondays 03:17 UTC, on `main`) and on a
   `workflow_dispatch` with `runtimes: oldest` or `both`. The `oldest` jobs are not required checks.
3. The release pre-flight dispatches `tests.yml` with `runtimes: both` against the commit to tag,
   beside `build.yml`, and waits for both to be green (`docs/releasing.md`, `/cut-release`). This is
   the only place the oldest runtime gates a release.
4. Supporting another iOS version later means adding it to the runtime list that
   `scripts/simulator.py` and the `runtime` matrix choose from.

## Alternatives considered

- **Test every supported runtime on every pull request** — it doubles the macOS jobs and the queue
  for a class of failure that is rare.
- **Test the oldest runtime only at release** — a break would be found with a tag already planned;
  the weekly run finds it within a week of the commit that caused it.

## Consequences

- A change that works on the newest iOS and breaks on the oldest can merge, and is found by the
  weekly run or the release pre-flight. The release cannot be cut until that run is green.
- A release takes one more macOS run: eight jobs instead of four.

## Verification

- `.github/workflows/tests.yml`: the `schedule` and `workflow_dispatch` inputs, and the `runtime`
  matrix.
- `scripts/update_branch_protection.py`: `REQUIRED_STATUS_CHECKS` names only `newest` jobs.
- `scripts/tests/test_ui_shards.py` checks both.

## Related

- [ADR 0006](0006-a-release-is-cut-by-a-workflow-after-a-build-pre-flight.md)
- [ADR 0043](0043-simulator-tests-run-in-four-timed-shards.md)
