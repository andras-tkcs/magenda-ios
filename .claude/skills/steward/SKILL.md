---
name: steward
description: Magenda repo policy for an agent session — which work has to be dispatched to a GitHub Actions runner instead of run locally (anything that needs macOS, Xcode or a simulator), which pull requests to follow, and how to treat a red check. Read this before acting on a CI failure or a review comment.
---

# Stewarding a Magenda pull request

This is repo-specific policy. It sits alongside `CONTRIBUTING.md` and `docs/releasing.md` (branch
hygiene and release mechanics), `docs/coding-and-testing-guidelines.md` (code and test conventions,
and the definition of done) and `docs/testing-policy.md` (which layer runs where) — none of which it
replaces. What it adds is what a session should do when the box it runs on cannot do the thing
being asked.

## Work that has to leave this machine

A Claude Code on the web container is Linux: it has no Xcode, no simulator and no signing
identity, and — unless the environment's setup script installs one — no Swift toolchain either.
None of that is a reason to skip a checklist row. Each of those jobs exists as a workflow with
`workflow_dispatch`, and a session can dispatch it **against its own branch** and read the result
back.

| You need | Dispatch | Notes |
|---|---|---|
| `swift test`, the coverage floor or `swift format`, with no toolchain here | `tests.yml` | Read the `core` and `lint` jobs. With a toolchain, run them here instead (`docs/testing-policy.md`, "Fast checks"). |
| The app built, its hosted tests and its UI tests on simulators | `tests.yml` | Read the three `app (...)` jobs. On a failure, download the job's `xcresult-*` artifact or read the log; never guess. |
| A Release archive with a version stamped in | `build.yml` | No inputs. Archives unsigned and uploads nothing off a tag. |
| To cut a release tag | `release.yml` | Inputs `version` and `dry_run`. **`dry_run` defaults to true** — dispatch it that way first. Only cut for real when the maintainer has seen the dry run and said to. See `/cut-release`. |
| A signed build in TestFlight | — | Only a tag does this (ADR 0009). Never try to sign or upload from a session. |

Things about dispatching, so they are not rediscovered at runtime:

- **The workflow must already be on `main`.** GitHub only offers `workflow_dispatch` for workflows
  present on the default branch; the `ref` you pass selects which checkout runs. A workflow added
  on a feature branch is not dispatchable until that branch merges.
- **Push before you dispatch.** The run checks out the remote branch, not your working tree.
- **macOS jobs are slow and queue.** Ten to twenty minutes for the `app` jobs is normal. Arm a
  check-in rather than polling.
- **Pushing a release tag directly is not possible here** — the container can push branches but
  not `refs/tags/*`. Don't try; a failed push can leave a local tag behind that makes
  `tag_release.py`'s later checks lie.

## Things only a person can do

App Store Connect, the Apple Developer account, a real device and App Review are the maintainer's.
A session never creates an app record, an API key or a certificate, never asks for one to be pasted
into the chat, and never marks a real-device check done. These go in a plan's `manual_before` or
`manual_after` (`.claude/commands/make-plan.md`), or in the PR's "Manual verification" section.

## Which pull requests to follow

- **A PR this session opened is this session's to drive to green.** Subscribe to it, and keep
  working it until CI passes and it is mergeable.
- **Do not follow Dependabot PRs** unless the maintainer asks. A dependency bump is a supply-chain
  decision for a person.
- **Stop at merge or close.** Nothing further is owed.

## A red check is real until proven otherwise

A second red run on the same commit is real and must not be re-run away. In particular:

- Never skip, disable or delete a test to get to green, and never wrap a failing UI test in
  `XCTSkip` or a failing Swift test in `.disabled`. The suite is a 100%-pass, ratcheted-coverage
  gate (`scripts/check_coverage_floor.py`).
- Never push an empty commit, or close and reopen a PR, to kick CI.
- A coverage-floor failure means the new code needs tests, not that the floor needs lowering.
- A UI test that fails only sometimes is waiting for something it should wait for explicitly
  (`waitForExistence(timeout:)`); fix the wait, never add a sleep.
- A simulator that is "not found" means `scripts/simulator.py`'s choice or the runner image
  changed; read its stderr in the log before touching the test.
- A missing Swift toolchain here is **not** a test failure. It is the dispatch table above.

## Conventions worth restating because they are easy to get wrong

- **Never edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in `project.yml` to release.** The
  tag and the commit count set them (ADR 0004).
- **Never commit the `.xcodeproj`.** Change `project.yml` and regenerate (ADR 0003).
- **Never open a concrete `## [X.Y.Z]` heading in `CHANGELOG.md` on a feature branch.** Entries go
  under `## [Unreleased]`; the release build fails on a duplicated or still-populated section.
- **PRs merge with a real merge commit, not a squash.** Every commit message on the branch
  survives into `main`'s history, so write each one for that audience.
- **Branch names.** `CONTRIBUTING.md` specifies `<type>/<kebab-case-description>`. A Claude Code on
  the web session is assigned a `claude/<generated-name>` branch it cannot rename; use it and put
  the `<type>` in the PR title instead. Apply the convention normally anywhere it can be followed.
- **`releases/*` is protected like `main`.** If work targets one, branch from it and PR back into
  it — not into `main`.
- **No project history in code or docs** (ADR 0008): no phase names, plan IDs or bare issue
  numbers in comments; `scripts/tests/test_no_project_history.py` fails on them.
