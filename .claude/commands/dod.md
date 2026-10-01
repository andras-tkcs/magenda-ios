---
description: Run the full definition-of-done gate and report a pass/fail table
argument-hint: "[optional: a swift test --filter value to narrow the AppCore run]"
---

Run this repo's definition of done — `docs/coding-and-testing-guidelines.md`, "Definition of done"
— and report the result as a table. Run every command from the repo root.

$ARGUMENTS

If arguments were given above, pass them to `swift test --filter` and say so in the report; the
coverage ratchet is meaningless on a partial run, so skip it and mark that row `n/a (partial run)`
rather than reporting a number that isn't comparable.

**The blocking gate, in this order** (all of it also blocks in CI — `.github/workflows/tests.yml`):

1. `swift test --package-path AppCore --enable-code-coverage`
2. `python3 scripts/check_coverage_floor.py "$(swift test --package-path AppCore --show-codecov-path)"`
3. `swift format lint --strict --parallel --recursive App AppTests AppUITests AppCore/Package.swift AppCore/Sources AppCore/Tests`
4. `python3 -m unittest discover -s scripts/tests`
5. On macOS only: `xcodegen generate`, then the app tests and the UI tests on a simulator
   (`python3 scripts/pre_release_check.py` runs all of the above in one go).

**Where a row cannot run here, it is not a pass.** Check the hook's output first:

- If `.claude/hooks/session-start.sh` printed a `WARNING` (no Swift toolchain), rows 1–3 cannot run.
- On Linux, row 5 never can.

For each such row, take its result from `tests.yml` for this branch's head commit instead: the
open PR's checks, or, with no PR yet, a `tests.yml` run you dispatch against the branch (push
first; see `.claude/skills/steward/SKILL.md`). Report the job name, its conclusion and the run URL.
If the run has not finished, the row is `pending`, not PASS.

**Then check the conditional rows against the actual diff** (`git diff --stat origin/main...HEAD`),
and for each one that applies, say whether it has been satisfied — do not silently drop it:

- Touched `project.yml`? → `xcodegen generate` succeeds and the app builds (an `app` job of
  `tests.yml` is green on this commit), new targets are in the scheme, changed settings commented.
- Touched permissions, entitlements, `INFOPLIST_KEY_NS*UsageDescription` or `PrivacyInfo.xcprivacy`?
  → purpose strings written for the user, and the changed App Store Connect privacy answers listed
  in the PR's "Manual verification".
- Touched `AppCore/Package.swift` dependencies? → bounded version range, an ADR for a new
  third-party package, and `build.yml` dispatched against the branch (link the run).
- Touched `.github/workflows/`? → a workflow that must be dispatchable is already on `main`, or the
  PR description says it only becomes dispatchable after merge.

**Manual review items.** The definition of done's other "every PR" rows are judgements no command
can make. Read the diff for each one and report it as `ok`, `needs attention` (with the file and
line) or `n/a` — never PASS, since nothing was run:

- Is there a user-visible change? → it needs a line under `CHANGELOG.md`'s `## [Unreleased]`,
  never under a concrete version heading. Internal-only changes don't need one.
- A decision that is hard to reverse, moves a trust boundary, changes the build/release/
  distribution path, or rejects a non-obvious alternative? → it needs an ADR in `docs/adr/`. A
  deleted plan document needs its decisions extracted into ADRs first, or a PR description saying
  it made none (`docs/adr/README.md`).
- New logic is in AppCore with tests; no view computes what AppCore could.
- New elements a UI test touches have identifiers in the view's `ID` enum; new interactive elements
  have accessibility labels.
- No log line or error message carries a credential, a token or the user's content.
- Comments only where the *why* is non-obvious; no restated-*what* comments; no project history.
- Standing docs (`README.md`, `docs/`) describe the new behavior.

**Report** one row per check: the command (or the manual item), PASS/FAIL/`pending`/`n/a`
(`ok`/`needs attention`/`n/a` for a manual item), where it ran (here, or the `tests.yml` run URL),
and for a failure the actual error — not a paraphrase. Do not fix anything unless I ask; this
command reports, it doesn't repair. End with a one-line verdict on whether this branch is ready to
open or update a PR.
