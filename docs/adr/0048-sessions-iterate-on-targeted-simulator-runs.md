# ADR 0048: Sessions iterate on targeted simulator runs; the four shards stay the only gate

## Status

Accepted — 2026-10-28. Implemented.

## Context

A cloud session runs on Linux and cannot run a simulator, so it uses `tests.yml` as its test
loop. Every check there is the full gate of [ADR 0043](0043-simulator-tests-run-in-four-timed-shards.md):
four shards of about 26 minutes each, and 26–40 more minutes for each shard that has to be re-run.
A session that wants to know whether one screen's tests pass waits for all of them.

## Decision

`tests.yml` has a dispatch input, `only`: comma-separated `MagendaTests`, `MagendaUITests/<Class>`
or `MagendaUITests/<Class>/<test>`. A dispatch that sets it runs one job per runtime, shown as
`ui (ipad, newest, only)`, with just those tests, in place of the four shards.

A targeted run is never a gate. Pull requests, pushes to `main` and `releases/**`, the weekly run
and `/dod` use the full shards, and `REQUIRED_STATUS_CHECKS` is unchanged.

The names are validated by `scripts/ui_shards.py --only` against the test classes and methods in
`AppUITests`, and the input reaches the shell only through the `ONLY` environment variable, never
through `${{ }}` inside a `run:` script. The step's word-split of `SHARD_ARGS` is safe because only
names made of known identifiers get through.

## Alternatives considered

- **Skipping the shards on draft PRs** — a job skipped by `if:` reports success to a required check,
  so a missed `ready_for_review` run could let a draft's head merge untested.
- **Selecting tests automatically from the changed files** — the screen-to-class map would drift
  and be wrong silently; the session names the classes instead.
- **Retries in targeted runs** — [ADR 0043](0043-simulator-tests-run-in-four-timed-shards.md)
  rejects them because they hide a missing wait.

## Consequences

- A targeted run takes the job's fixed ten minutes or so of build and boot plus its tests, about
  10–14 minutes for a few classes.
- `only` needs `simulators: true`, the default; with `simulators: false` no simulator job runs.
- A green targeted run says nothing about the classes it did not name.

## Verification

- `scripts/ui_shards.py`: `select`.
- `scripts/tests/test_ui_shards.py`: the `test_select_*` tests and
  `test_the_workflow_passes_only_through_the_environment`.
- `tests.yml`: the `ONLY` environment variable and the `shard` matrix.

Related: [0043](0043-simulator-tests-run-in-four-timed-shards.md),
[0045](0045-simulator-shards-get-a-warm-up-launch-one-retry-and-a-40-minute-limit.md),
[0047](0047-every-ui-test-launch-waits-for-the-app-window.md).
