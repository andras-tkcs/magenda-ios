# Testing policy

What runs where, and when. How to *write* a test is in
[`coding-and-testing-guidelines.md`](coding-and-testing-guidelines.md); the checks a human runs
before a release are in [`release-testing.md`](release-testing.md).

## Principle

**Do not test the full Cartesian product** (`iOS version × device × orientation × locale ×
appearance × backend`). Each dimension is proven on its own, in one layer below, and only a few
high-value end-to-end tests cross a boundary.

## The layers

| # | Layer | What it proves | Where it lives | Where it runs |
|---|---|---|---|---|
| 1 | Unit | Logic in isolation, offline | `AppCore/Tests/` (`swift test`); `AppTests/` for what only the built app can show | `tests.yml` `core` (Linux), `app` (simulators), every PR |
| 2 | UI | The real app launches on a simulator, and a user's path through it works | `AppUITests/` (XCUITest) | `tests.yml` `app`, every PR |
| 3 | Compatibility | Layers 1–2 on the newest and the oldest supported iOS, and on iPad | A matrix, not a test | `tests.yml` `app`, every PR |
| 4 | Backend contract | Google's responses still decode the way the app expects | `AppCore/Tests/Google/Fixtures/` | `tests.yml` `core`, every PR; no live check; see below |
| 5 | Release archive | The Release configuration archives and carries the tag's version | `build.yml` `archive` | Tag push, and dispatched as the release pre-flight |
| 6 | Distribution | The signed build is accepted by App Store Connect and installs from TestFlight | `build.yml` `testflight` | Tag push |
| 7 | Manual | Real devices, real accounts, App Review, how it feels | [`release-testing.md`](release-testing.md) | Before a stable release |

| Failure type | Owning layer |
|---|---|
| Wrong logic, malformed decoding, an edge case | 1 |
| A crash at launch, a missing accessibility identifier, a broken navigation path | 2 |
| Works on iOS 26 / iPhone, breaks on the oldest supported iOS or on iPad | 3 |
| Google renamed a field the app decodes | 4 |
| Release-only compiler errors, a lost version number | 5 |
| Signing, entitlements, a missing icon or privacy manifest rejected on upload | 6 |
| Feels wrong, reads badly, fails on a real device's hardware | 7 |

## Layers 1–3: every PR

`.github/workflows/tests.yml` runs on every pull request, every push to `main` or `releases/**`,
and on dispatch. A 100% pass rate is required to merge.

| Job | Runs |
|---|---|
| `core` (Ubuntu) | `swift test` in AppCore with coverage, then `scripts/check_coverage_floor.py` |
| `lint` (Ubuntu) | `swift format lint --strict` |
| `scripts` (Ubuntu) | `python3 -m unittest discover -s scripts/tests`, including the no-project-history guard |
| `app (iphone, newest)`, `app (iphone, oldest)`, `app (ipad, newest)` (macOS) | `xcodegen generate`, then the hosted app tests on a simulator `scripts/simulator.py` picks |
| `ui (<family>, <runtime>, <shard>)` (macOS), ten jobs | The same build, then one shard of the UI tests on the same three simulators: `edit-screen`, `settings`, and `rest` (every UI test class not in another shard, so a new class runs there), plus a `binder` shard on the iPad only, because the binder, Start over and hand-off UI tests are iPad-only |

The UI tests run as parallel shards per device (four on the iPad, three on each iPhone), so a
failed shard is re-run on its own ("Re-run failed jobs") instead of repeating every UI test. Each
shard boots its simulator before the build and waits for the boot to finish before the first test: a device's first boot keeps the
runner busy for minutes, and a UI test launched during it times out before its body runs.

`scripts/simulator.py` chooses devices by family and runtime rather than by name, because names
change with every Xcode. `oldest` means the oldest installed runtime at or above the deployment
target in `project.yml`; when the target's own runtime is not on the runner image, the job log says
which one it used instead.

**Coverage is a ratchet** over AppCore (ADR 0007). `scripts/check_coverage_floor.py` fails if
AppCore's line coverage, or any file on its list, drops below its recorded floor. Raise a floor in
the PR that raises its coverage; lowering one is a regression, not a config edit. A failing file is
reported with the lines where its never-run regions begin.

**Required checks.** `REQUIRED_STATUS_CHECKS` in `scripts/update_branch_protection.py` is the
reviewed list. Update it in the PR that adds, renames or removes one of those jobs; a maintainer
applies it by hand (`... apply`). `... show` compares it with what is live.

## Layer 4: backend contract

The app's only backend is Google's Calendar and Tasks REST APIs (ADR 0014). The Google decoding
tests replay recorded responses from `AppCore/Tests/Google/Fixtures` and run on every PR with the
rest of AppCore. No live contract check runs: the app signs in with each user's own Google client
(ADR 0013), and there is no account for CI to use. A live account is checked by hand in
[`release-testing.md`](release-testing.md).

If a live check is ever added, its credential lives only on a runner the project controls, never in
a GitHub-hosted job or a `pull_request` workflow, and that boundary gets an ADR.

## Layout audit and binder rules

`LayoutAudit` checks every render plan for text outside its container or the page, overlapping
text and bad links (ADR 0012). It runs in AppCore with a deterministic fake font over the
long-text fixtures, and in `AppTests` with the real fonts. The binder rules are tested in AppCore
against the `standard` fixture, with no network and no simulator. Binder pages (added and
retained pages) are audited in AppCore too (`BinderLayoutTests`).

## Layers 5–6: release archive and distribution

`build.yml` archives the Release configuration with the version from the tag and the build number
from the commit count, and checks the archive's `Info.plist` carries both (ADR 0004). It runs on a
`v*` tag push and on dispatch; signing and upload are gated on a tag ref, so a dispatched run
archives unsigned and uploads nothing. That dispatched run is the release pre-flight (ADR 0006).
On a tag, the `testflight` job archives again with signing and uploads to App Store Connect, where
Apple's own validation runs (ADR 0009). When the maintainer turns it on, it also exports an Ad Hoc
`.ipa` before the upload (ADR 0017).

## Layer 7: manual

The manual release checks, and the rule for what may stay manual, are in
[`release-testing.md`](release-testing.md).

## Fast checks

The subset a session runs after every merge into a feature branch (`/implement`) and before
handing a branch to review. It is not the definition of done; `/dod` is.

```bash
swift test --package-path AppCore
python3 -m unittest discover -s scripts/tests
```

Without a Swift toolchain (a cloud container whose network policy does not reach
`download.swift.org`; see `.claude/hooks/session-start.sh`), push the branch and read the `core`
and `lint` jobs of a dispatched `tests.yml` run instead.

## Running the gate yourself

- **`/dod`** (`.claude/commands/dod.md`) runs the blocking gate of the
  [definition of done](coding-and-testing-guidelines.md#definition-of-done), then checks the diff
  for the conditional items and reports a pass/fail table.
- **`python3 scripts/pre_release_check.py`** runs the same blocking commands as one script and exits
  non-zero on any failure. On Linux it reports the simulator rows as SKIP: their result has to come
  from `tests.yml`.
