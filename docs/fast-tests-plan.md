# Plan: tests that finish in 20 minutes

## Goal

A pull request's `tests.yml` run finishes in **20 minutes or less** of wall-clock time once runners
are available, and **no macOS job runs longer than 18 minutes**. Today a green run takes over three
hours, and a single shard can hit its 40-minute timeout. The changes that get there:

- **Magenda becomes iPad-only.** The binder and its Pencil ink are the product (ADR 0020). The app
  has only ever shipped through TestFlight, and it has no iPhone users; the maintainer confirmed
  on 26 October 2026 that there has been no App Store release. The app drops the iPhone device
  family, the iPhone-only preview code and the iPhone tests.
- **Pull requests test the newest iPad runtime only.** The oldest supported runtime runs weekly and
  in the release pre-flight. Supporting "a few iOS versions" later means adding a runtime to a
  list.
- **The UI tests get cheaper.** They launch straight into the screen they test, run with
  animations off, and stop polling with waits that miss inside scroll loops.
- **CI runs four timed shards.** Each shard builds once, then runs its share of the hosted and UI
  tests, balanced from measured timings.

No GitHub issue tracks this; it came from a `/make-plan` request.

**Base and merge order.** At the maintainer's request, the plan is cut from
`feature/summary-routines` (PR #17, stacked on #16), not from `main`, so that it speeds up every UI
test those PRs add. The feature PR targets `main` and **merges after #16 and #17**. Two things
depend on that order: `manual_after` changes the required checks, and that would block any PR
still on the old workflow. Until #16 and #17 merge, the feature PR's diff also shows their
commits; once they are in `main`, merge `main` into the feature branch and the diff shrinks to
this plan's changes.

## Current state

Line references are on `feature/summary-routines` at `07c0f64`.

### CI shape

`.github/workflows/tests.yml` has these jobs:

- `core`, `lint` and `scripts` on Ubuntu, about 2 minutes together.
- `app (family, runtime)` on macOS, 3 jobs: iPhone newest, iPhone oldest and iPad newest. Each one
  builds the app and runs the hosted `MagendaTests`.
- `ui (family, runtime, shard)` on macOS, 13 jobs. Every device point gets `edit-screen`,
  `settings`, `rules` and `rest`, and the iPad also gets `binder`.

That is **16 macOS jobs per run**, and each job generates the project and builds for itself.
`scripts/update_branch_protection.py:25-44` (`REQUIRED_STATUS_CHECKS`) lists 18 required checks.
The iPad `binder` shard is not among them.

GitHub runs at most 5 macOS jobs at once on a Free or Pro account, so 16 jobs run in about four
waves. `/implement` also dispatches `tests.yml` from several phase sessions at the same time, and
those runs queue behind each other. Nothing cancels a superseded run.

### Measured timings

These come from run 40294684850 (`feature/send-meeting-early`, green, 26 October 2026, before #16
and #17 added their tests).

The run as a whole:

- It took **3 h 38 min** of wall-clock time (08:47 to 12:25), and macOS jobs waited up to
  2 h 20 min for a runner.
- **`build-for-testing`** takes 40–60 s in an `app` job, but 4–7.5 min in a `ui` job. The `ui` job
  boots the simulator at the same time, in its "Boot the simulator" step before "Build for
  testing".
- **The hosted tests** (Swift Testing) take **18 s**. The `app (ipad, newest)` job spends about
  **3 min** in front of them, booting the simulator and installing the app.

The iPad UI tests take **3,646 s (61 min)** in all. Per shard:

| Shard | Classes | Tests took | Job took | Overhead (job − tests) |
|---|---|---|---|---|
| `rest` | Preview, Rules, Setup, SignIn | 1,529 s | 34 min | 8.5 min |
| `settings` | Settings | 897 s | 23 min | 8 min |
| `binder` | Binder, Handoff, StartOver | 704 s | 22 min | 10 min |
| `edit-screen` | AgendaEdit, AgendaScreen, LongText | 516 s | 19 min | 10.5 min |

Per class, in seconds, with the test count on this branch in brackets:

| Class | Seconds | Tests on this branch |
|---|---|---|
| Rules | 1,318 | 12 |
| Settings | 897 | 14 |
| Binder | 390 | 13 |
| AgendaEdit | 320 | 7 |
| Handoff | 258 | 8 |
| Preview | 161 | 5 |
| AgendaScreen | 118 | 5 |
| LongText | 79 | 2 |
| StartOver | 55 | 2 |
| SignIn | 25 | 2 |
| Setup | 24 | 1 |

The Rules and Settings classes are **61%** of all UI test time. The slowest test is
`testResetRulesRestoresTheDefaults` at 280 s; the next is `testADuplicateSummaryTitleShowsAnError`
at 203 s. Scaled to this branch's test counts, the iPad UI tests would take about **4,900 s**.

### Where the UI test time goes

1. **Scroll-to-reveal loops: about 1,000 s.** `RulesUITests.reveal`
   (`AppUITests/RulesUITests.swift:110`) and `SettingsUITests.reveal`
   (`AppUITests/SettingsUITests.swift:68`) each, on every iteration:
   - probe with `waitForExistence(timeout: 1)` or `waitForExistence(timeout: 2)`;
   - re-query `settingsDone` and the target;
   - drag 100–300 points, anchored on the Done button.

   One iteration costs about **8.5 s**, and the run had 116 of them. Every Rules test also opens
   the Settings sheet and scrolls to `rulesLink` first (`openRules`, `RulesUITests.swift:35`).
2. **Waits that miss: about 620 s.** A `waitForExistence` that times out costs about **4 s**, not
   1–2 s, because XCTest then captures an element debug description: four full accessibility
   snapshots. The run had 148 misses, almost all inside the reveal loops. An
   `XCTNSPredicateExpectation` also polls only once a second.
3. **Idle waits after taps: about 200 s.** These come from animations (sheets, navigation pushes,
   the keyboard), and the app has no switch to turn animations off.
4. **Launches: about 700 s.** Each of the 60 launches takes about 10 s, and the first launch on a
   fresh simulator takes 24–52 s. This is a fixed cost.
5. **Untyped queries: about 70 s.** `descendants(matching: .any)[id]` takes about 0.5 s per
   `Find`. This plan leaves it alone (D5).

### iPhone-specific code

- **`project.yml`.** Line 42 sets `TARGETED_DEVICE_FAMILY: "1,2"`. Line 48 sets
  `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`. Lines 89–91 set
  `gatherCoverageData: true` and `coverageTargets`.
- **`App/Screens/AgendaView.swift`.** `detail` (line 214) and `toolbar` (line 238) branch on
  `UIDevice.current.userInterfaceIdiom == .pad`. The iPhone branch shows `PreviewView`, which
  wraps `PDFKitView`; nothing else uses either file. The file's comments mention the iPhone at
  lines 5–6 and 97–98.
- **UI tests.** They switch on `userInterfaceIdiom` in several places:
  - a `previewID` property in AgendaEdit, AgendaScreen, LongText, Preview and Settings;
  - a `shareID` property in Preview;
  - `XCTSkipUnless(... == .pad)` lines in Binder, Handoff, StartOver, Preview and AgendaEdit;
  - an `if` block in `AgendaScreenUITests.swift:146`;
  - one iPhone-only test, `PreviewUITests.testRenderingAgainAfterGoingBackShowsThePreviewAgainOnIPhone`.

  The views keep their `horizontalSizeClass` logic: an iPad window is compact in Slide Over and
  Split View.
- **Stale CI references** elsewhere:
  - `.claude/toolkit.yaml:45` and `:65-66`;
  - `.claude/commands/dod.md:37`;
  - `scripts/pre_release_check.py:110`;
  - `docs/coding-and-testing-guidelines.md:155`;
  - `docs/testing-policy.md` (its layer table, the "Layers 1–3" section and the jobs table);
  - `.claude/skills/steward/SKILL.md:25`;
  - `README.md:5` and `:69`;
  - `docs/release-testing.md:45`.

## Design

### D1. iPad-only app

- **`project.yml`.**
  - Set `TARGETED_DEVICE_FAMILY: "2"`.
  - Delete the `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` line.
  - Put the comment `# iPad-only.` on the line above the device family setting. p7 appends the
    ADR number to it.
- **`AgendaView`.**
  - `detail` keeps only its iPad branch: the binder, or the "No binder yet" placeholder.
  - The Start Over toolbar item drops the idiom check and keeps `controller.binder != nil`.
  - Delete `ID.pdfPreview` if nothing else in `App/` uses it.
  - Rewrite the comments at lines 5–6 and 97–98 so they no longer mention the iPhone.
- **Delete** `App/Screens/PreviewView.swift` and `App/Screens/PDFKitView.swift`.
- **`CHANGELOG.md`**, under `[Unreleased]`: add a `### Removed` heading between `### Changed` and
  `### Fixed` (Keep a Changelog order), with this line:
  `- Magenda no longer runs on iPhone; it is an iPad app.`
- **`scripts/simulator.py`.** Its `--family` default becomes `ipad`. The `iphone` choice stays,
  because the picker is device-agnostic. `scripts/pre_release_check.py` uses the default.
- **`README.md` and `docs/release-testing.md`** stop describing an iPhone.
- **ADR 0020** is not edited, apart from its Status. ADR 0041 amends its item 7, "The iPhone keeps
  the read-only PDF preview".

Rejected:

- **Keep the app universal and drop only iPhone CI.** That ships an iPhone build nobody tests.
- **Keep `PreviewView` for later.** No later use is planned.

Out of scope: `AgendaController.render` still writes a PDF on every Render
(`AppCore/Sources/Controller/AgendaController.swift:328-342`), which only the deleted preview
read. Removing that is a separate change.

### D2. CI shape (`tests.yml`)

**Triggers.** The existing ones stay. Add a schedule:

```yaml
schedule:
  - cron: "17 3 * * 1"   # Mondays 03:17 UTC: the oldest supported runtime, on main
```

Add inputs to `workflow_dispatch`:

```yaml
workflow_dispatch:
  inputs:
    simulators:
      description: Build the app and run its hosted and UI tests on simulators
      type: boolean
      default: true
    runtimes:
      description: Which iOS runtimes the simulator jobs test on
      type: choice
      options: [newest, oldest, both]
      default: newest
```

**Concurrency.** Add at the top level:

```yaml
# A new push to a PR, or a new dispatch on the same branch, cancels the stale run. Pushes and the
# weekly run get a group of their own, so they are never cancelled or replaced.
concurrency:
  group: tests-${{ (github.event_name == 'pull_request' || github.event_name == 'workflow_dispatch') && format('{0}-{1}', github.event_name, github.ref) || github.run_id }}
  cancel-in-progress: true
```

**The `app` job is deleted.** The hosted tests run inside a shard (D3).

**The `ui` job.** Phase p1 writes it with the generous limits marked below, because the UI tests
are still slow then. Phase p6 tightens those limits once the tests are measured.

```yaml
ui:
  name: ui (ipad, ${{ matrix.runtime }}, ${{ matrix.shard }})
  if: github.event_name != 'workflow_dispatch' || inputs.simulators
  runs-on: macos-latest
  timeout-minutes: 45            # p6 lowers this to 25
  strategy:
    fail-fast: false
    matrix:
      runtime: ${{ fromJSON((github.event_name == 'schedule' || inputs.runtimes == 'both') && '["newest","oldest"]' || (inputs.runtimes == 'oldest' && '["oldest"]' || '["newest"]')) }}
      shard: [1, 2, 3, 4]
  env:
    RUNTIME: ${{ matrix.runtime }}
    SHARD: ${{ matrix.shard }}
    HOMEBREW_NO_AUTO_UPDATE: "1"
```

The job's steps, in order:

1. `actions/checkout`, with the same pinned SHA as today.
2. `xcodebuild -version`.
3. `brew install xcodegen` then `xcodegen generate`.
4. Pick a simulator. Assign to a variable first, so `bash -e` fails the step if the script fails:
   ```bash
   destination=$(python3 scripts/simulator.py --family ipad --runtime "$RUNTIME")
   echo "DESTINATION=$destination" >> "$GITHUB_ENV"
   ```
5. Choose the shard's tests the same way:
   ```bash
   args=$(python3 scripts/ui_shards.py --shard "$SHARD")
   echo "SHARD_ARGS=$args" >> "$GITHUB_ENV"
   ```
6. Build for testing, with today's command unchanged.
7. Boot the simulator and wait for it: `xcrun simctl bootstatus "${DESTINATION#id=}" -b`. Its
   comment says why the boot comes after the build: a boot that overlaps the build slows the
   build from about 1 minute to 4–7 minutes, and `bootstatus -b` returns only once the device is
   fully up, so the first test does not launch into a half-booted simulator.
8. Run the tests (100% pass rate required). Keep the existing comment saying `SHARD_ARGS` is
   deliberately unquoted.
   ```bash
   xcodebuild test-without-building -project Magenda.xcodeproj -scheme Magenda \
     -destination "$DESTINATION" -derivedDataPath build/DerivedData \
     -test-timeouts-enabled YES -default-test-execution-time-allowance 600 \
     -maximum-test-execution-time-allowance 600 \
     $SHARD_ARGS -resultBundlePath "build/tests-$SHARD.xcresult"
   ```
   p6 lowers both allowances (see p6).
9. On failure, upload `build/*.xcresult` as `xcresult-ipad-${{ matrix.runtime }}-${{ matrix.shard }}`,
   with the same pinned `upload-artifact` SHA and a 14-day retention.

**Required checks.** `REQUIRED_STATUS_CHECKS` becomes these seven:

- `core`, `lint`, `scripts`;
- `ui (ipad, newest, 1)`, `ui (ipad, newest, 2)`, `ui (ipad, newest, 3)`, `ui (ipad, newest, 4)`.

The `oldest` jobs never run on a PR, so they are not required.

**Scheme.** In `project.yml`, `schemes.Magenda.test` sets `gatherCoverageData: false` and drops
`coverageTargets`. Nothing reads the app's coverage, because the coverage ratchet is AppCore's
(ADR 0007), and coverage instrumentation slows both the build and the UI tests.

Rejected:

- **More shards, or more parallel sessions.** The 5-job macOS cap is per account. Every extra job
  pays the fixed overhead again (checkout, project generation, simulator pick, build, boot, first
  launch: about 6–7 minutes), and it lengthens the queue for every other run. The time-outs that
  prompted the idea came from degraded runners, not from too few shards.
- **Parallel testing on cloned simulators inside one runner** (`-parallel-testing-enabled YES`).
  Hosted macOS runners have 3 cores and 7 GB of memory, and two iPad simulator clones on one make
  launch time-outs likelier.
- **One build job handing its products to the test jobs.** It adds a serial job and a transfer of
  several hundred MB to save about 1 minute of build per shard, once the boot no longer overlaps
  the build.
- **Retrying failed tests** (`-retry-tests-on-failure`). That hides a missing wait, which the
  steward skill forbids. The test time allowances make a hung test fail fast instead.
- **Pinning the runner image.** `build.yml` archives on `macos-latest`, so tests on any other image
  would test a different Xcode than the one that ships.

### D3. `scripts/ui_shards.py`

A new script, standard library only. It follows `scripts/simulator.py`'s shape: a module docstring
with usage lines, `from __future__ import annotations`, `main(argv: list[str] | None = None) -> int`
and `if __name__ == "__main__": sys.exit(main())`.

```python
SHARD_COUNT = 4

# Seconds each entry took in the last measured tests.yml run on the newest iPad. An entry is the
# hosted test target, a whole UI test class, or one UI test method of a class that is too long for
# one shard. Shards are balanced from these, so `--check` (and the scripts job) fails when a test
# class or method has no entry.
CLASS_SECONDS: dict[str, int] = {
    "MagendaTests": 60,
    "MagendaUITests/AgendaEditUITests": 450,
    "MagendaUITests/AgendaScreenUITests": 120,
    "MagendaUITests/BinderUITests": 390,
    "MagendaUITests/HandoffUITests": 300,
    "MagendaUITests/LongTextUITests": 80,
    "MagendaUITests/PreviewUITests": 160,
    "MagendaUITests/RulesUITests": 1980,
    "MagendaUITests/SettingsUITests": 1260,
    "MagendaUITests/SetupUITests": 30,
    "MagendaUITests/SignInUITests": 30,
    "MagendaUITests/StartOverUITests": 60,
}
```

These numbers are estimates: the measured class totals, scaled to this branch's test counts. p6
replaces them with measured values.

Functions:

- **`test_classes(directory: Path) -> dict[str, list[str]]`.** For each `*.swift` file in
  `directory`, sorted by name:
  - Find classes with `^(?:final )?class (\w+): XCTestCase`, multiline.
  - If the file has more than one, raise `ValueError(f"{file.name} declares more than one XCTestCase")`.
  - If it has exactly one, map its name to the sorted list of `^\s+func (test\w+)\(` matches in
    that file.
- **`problems(seconds: dict[str, int], classes: dict[str, list[str]]) -> list[str]`.** Returns
  human-readable lines, with an empty list meaning everything checks out:
  - `MagendaTests` is required.
  - For each class `C`, either the key `MagendaUITests/C` exists and no `MagendaUITests/C/<method>`
    key does, or every method of `C` has a `MagendaUITests/C/<method>` key and the class key is
    absent.
  - Every other key is reported as stale.
- **`assign(seconds: dict[str, int], count: int) -> list[list[str]]`.** Longest processing time
  first:
  - Sort the keys by `(-seconds, key)`.
  - Put each key into the shard with the smallest running total; on a tie, use the lowest index.
  - Return each shard's keys sorted.
- **`arguments(keys: list[str]) -> list[str]`** returns `["-only-testing:" + key for key in keys]`.
- **The CLI.** It takes exactly one of these (an argparse mutually exclusive group, required):
  - `--shard N` prints shard N's arguments, space-separated, on one line. N is 1-based, and an
    out-of-range N exits 2 with an argparse error. `--count`, which defaults to `SHARD_COUNT`,
    sets the number of shards.
  - `--check` prints each line of
    `problems(CLASS_SECONDS, test_classes(<repo>/AppUITests))` and exits 1 if there are any,
    otherwise 0.
  - `--table` prints one line per shard: `shard N: <total> s: <keys comma-separated>`.

Tests go in a new file, `scripts/tests/test_ui_shards.py`. Load the module the way
`scripts/tests/test_scripts.py:39` loads `simulator`, and load `update_branch_protection` the same
way. The tests:

1. `problems(CLASS_SECONDS, test_classes(AppUITests))` is empty for the repository.
2. `assign` places every key exactly once, for counts 1 to 6, on `CLASS_SECONDS`.
3. `assign({"a": 10, "b": 9, "c": 8, "d": 1}, 2)` returns `[["a", "d"], ["b", "c"]]`.
4. `problems` reports:
   - a class with neither form of key;
   - a class with both forms;
   - a class with only some of its methods;
   - a stale key;
   - a missing `MagendaTests`.

   Use a hand-written `classes` dict for each case.
5. `test_classes` on a temporary directory:
   - finds `final class A: XCTestCase` with its two `test` methods;
   - finds a non-final `class B: XCTestCase`;
   - ignores `class Helper` and a `func helper()`;
   - raises on a file with two `XCTestCase` classes.
6. The `shard:` line in `.github/workflows/tests.yml` (regex `shard: \[([\d, ]+)\]`) lists exactly
   `1..SHARD_COUNT`.
7. `update_branch_protection.REQUIRED_STATUS_CHECKS` contains `ui (ipad, newest, N)` for N in
   `1..SHARD_COUNT`, and no other entry starting with `ui (` or `app (`.

### D4. Fixture launch options (AppCore and App)

**New file: `AppCore/Sources/Controller/LaunchOptions.swift`.**

```swift
/// What a fixture launch asks of the app beyond its fixture: a screen to open on, and whether to
/// animate. UI tests use it to start where they test and to skip animation waits.
public struct LaunchOptions: Equatable, Sendable {
    /// A screen a launch can open on.
    public enum Screen: String, Equatable, Sendable {
        /// The settings sheet.
        case settings
        /// The binder rules, pushed inside the settings sheet.
        case rules
    }

    /// The screen to open on, or `nil` for the agenda.
    public let screen: Screen?
    /// `false` when the launch asked for no animations.
    public let animates: Bool

    /// Reads `-MagendaOpen <settings|rules>` and `-MagendaNoAnimations`. An unknown screen name, or
    /// `-MagendaOpen` with nothing after it, opens nothing.
    public init(launchArguments: [String])

    /// What a launch with neither argument gets.
    public static let standard: LaunchOptions
}
```

**Tests: `AppCore/Tests/Controller/LaunchOptionsTests.swift`**, as `@Suite("Launch options")`.
Its cases:

- no arguments equals `.standard` (screen `nil`, `animates == true`);
- `-MagendaOpen settings`;
- `-MagendaOpen rules`;
- `-MagendaOpen bogus` gives `nil`;
- a trailing `-MagendaOpen` gives `nil`;
- `-MagendaNoAnimations` gives `animates == false`;
- both arguments together, in any order around `-MagendaFixture standard`.

AppCore's overall floor is 100% (`scripts/check_coverage_floor.py:36`), so these tests must reach
every line.

**New file: `App/LaunchRequest.swift`.**

```swift
import AppCore
import SwiftUI

/// The screen a fixture launch asked to open on, handed out once, so a view that is rebuilt after
/// setup or sign-in does not open it again.
@MainActor
final class LaunchRequest {
    private var screen: LaunchOptions.Screen?

    init(_ options: LaunchOptions) {
        screen = options.screen
    }

    /// The requested screen the first time it is asked for, then `nil`.
    func take() -> LaunchOptions.Screen? {
        defer { screen = nil }
        return screen
    }
}

extension EnvironmentValues {
    @Entry var launchRequest: LaunchRequest?
}
```

**App wiring.**

- **`App/AppEnvironment.swift`.**
  - `AppServices` gains `let animates: Bool` and `let launchRequest: LaunchRequest`.
  - The fixture branch builds `let launch = LaunchOptions(launchArguments: arguments)` and passes
    `animates: launch.animates, launchRequest: LaunchRequest(launch)`.
  - The live branch passes `animates: true, launchRequest: LaunchRequest(.standard)`, so a real
    launch never honours these arguments.
  - `previewServices` passes what the fixture branch does.
- **`App/MagendaApp.swift`.**
  - Add `import UIKit`.
  - In `init()`, build the services into a local `let services = try? AppEnvironment.makeServices(...)`,
    then `_services = State(initialValue: services)`, then
    `if services?.animates == false { UIView.setAnimationsEnabled(false) }`. That call is what
    turns off sheet, push and keyboard animations.
  - On `RootView`, add `.environment(\.launchRequest, services.launchRequest)`.
- **`App/Screens/AgendaView.swift`.**
  - Add `@Environment(\.launchRequest) private var launchRequest` and
    `@State private var settingsOpensRules = false`.
  - Add this `.task` on the `NavigationSplitView`:
    ```swift
    .task {
        guard let screen = launchRequest?.take() else { return }
        settingsOpensRules = screen == .rules
        showsSettings = true
    }
    ```
  - The settings sheet becomes:
    ```swift
    .sheet(isPresented: $showsSettings, onDismiss: { settingsOpensRules = false }) {
        SettingsView(appInfo: appInfo, opensRules: settingsOpensRules)
    }
    ```
- **`App/Screens/SettingsView.swift`.**
  - Add a nested `enum Route: Hashable { case rules }` and `@State private var path: [Route]`.
  - Add `init(appInfo: AppInfo, opensRules: Bool = false)`, which sets `self.appInfo` and
    `_path = State(initialValue: opensRules ? [.rules] : [])`. Every other stored property keeps
    its default.
  - `NavigationStack {` becomes `NavigationStack(path: $path) {`.
  - The link becomes `NavigationLink("Binder rules", value: Route.rules)` and keeps its
    identifier.
  - Add `.navigationDestination(for: Route.self) { _ in RulesView() }` on the `Form`.
  - Add `static let form = "settingsForm"` to `ID`, and `.accessibilityIdentifier(ID.form)` on the
    `Form`.
- **`App/Screens/RulesView.swift`.** Add `static let form = "rulesForm"` to `ID`, and
  `.accessibilityIdentifier(ID.form)` on the `Form` at line 72.

**New UI test: `AppUITests/LaunchOptionsUITests.swift`.** It proves the app side before the other
UI tests rely on it. Header comment: "Fixture launch options: a UI test can open on a screen
directly." It has these tests, each with its own private launch helper in the style of
`SignInUITests`:

- `testOpeningOnSettingsShowsTheSettingsSheet` launches with
  `["-MagendaFixture", "standard", "-MagendaOpen", "settings"]` and asserts
  `app.buttons["settingsDone"].waitForExistence(timeout: 30)`.
- `testOpeningOnRulesShowsTheRules` launches with `-MagendaOpen rules` and asserts that
  `rulesRow.personalBlocks.0` (as `descendants(matching: .any)`) exists within 30 s.
- `testClosingTheOpenedSettingsDoesNotReopenThem` launches with `-MagendaOpen settings`, taps
  `settingsDone` until it is gone (the retry loop from `SettingsUITests.closeSettings`), then
  asserts that `settingsDone` does not exist after `XCTWaiter().wait(for: [], timeout: 3)`. A
  fixed wait is acceptable here because it asserts an absence.
- `testWithoutAnimationsTheAppStillRenders` launches with `-MagendaNoAnimations`, taps
  `renderButton`, and asserts `binderView` exists within 30 s.

`scripts/ui_shards.py` gains `"MagendaUITests/LaunchOptionsUITests": 60`.

### D5. Shared UI test support (`AppUITests/MagendaUI.swift`)

A new file. Its header comment says it holds the steps every UI test class shares. Every member is
`@MainActor`.

```swift
extension XCUIApplication {
    /// Launches Magenda on `fixture` with animations off, plus `extra` arguments.
    static func launchMagenda(fixture: String = "standard", _ extra: [String] = []) -> XCUIApplication
    // let app = XCUIApplication()
    // app.launchArguments = ["-MagendaFixture", fixture, "-MagendaNoAnimations"] + extra
    // app.launch(); return app

    /// The element with `identifier`, of any type.
    func element(_ identifier: String) -> XCUIElement
    // descendants(matching: .any)[identifier].firstMatch
}

extension XCUIElement {
    /// Waits until `keyPath` equals `value`. Xcode's `wait(for:toEqual:timeout:)` does not poll once
    /// a second, as an `XCTNSPredicateExpectation` does.
    @discardableResult
    func waitUntil<V: Equatable>(_ keyPath: KeyPath<XCUIElement, V>, is value: V,
                                 timeout: TimeInterval = 30) -> Bool
    // wait(for: keyPath, toEqual: value, timeout: timeout)

    /// Scrolls the content of `container` (positive `distance` shows what is further down) with
    /// one held drag that does not fling.
    func scrollContent(by distance: CGFloat)

    /// Scrolls `container` until this element is hittable with its middle between `top` and
    /// `bottom`, or until the container cannot scroll further. Fails the test otherwise.
    func reveal(in container: XCUIElement, top: CGFloat? = nil, bottom: CGFloat? = nil,
                file: StaticString = #filePath, line: UInt = #line)
}
```

**`scrollContent(by:)`**, called on the container:

- For `distance > 0`, the finger goes from `coordinate(withNormalizedOffset: (0.5, 0.7))` to that
  point offset by `(0, -distance)`.
- For `distance < 0`, it goes from `(0.5, 0.3)` offset by `(0, +|distance|)`.
- Either way it uses `press(forDuration: 0.05, thenDragTo: end, withVelocity: 600, thenHoldForDuration: 0.2)`.

**`reveal(in:top:bottom:)`**, exactly:

```swift
let topLimit = top ?? container.frame.minY + 60
let bottomLimit = bottom ?? container.frame.maxY - 20
var lastMid: CGFloat?
var stalled = 0
for attempt in 0..<24 {
    guard exists else {
        lastMid = nil
        container.scrollContent(by: attempt < 12 ? 300 : -300)
        continue
    }
    let mid = frame.midY
    if mid >= topLimit && mid <= bottomLimit && isHittable { return }
    stalled = lastMid.map { abs($0 - mid) < 2 ? stalled + 1 : 0 } ?? 0
    lastMid = mid
    if stalled >= 2 && isHittable { return }   // the container cannot scroll any further
    if mid < topLimit {
        container.scrollContent(by: -min(max(topLimit - mid + 40, 100), 300))
    } else {
        container.scrollContent(by: min(max(mid - bottomLimit + 40, 100), 300))
    }
}
XCTFail("\(self) was never scrolled into view", file: file, line: line)
```

When the element is inside the range but not hittable, `mid >= topLimit` holds, so the last branch
scrolls it 100 points further up. The old `upperHalf: true` becomes
`bottom: app.windows.firstMatch.frame.height / 2`.

**Migration rules for p4 and p5.** Each test file:

1. Deletes its private `launch` and `element` helpers, and calls `XCUIApplication.launchMagenda`
   and `app.element(_:)` instead. Typed queries the file already has (`app.buttons[...]`,
   `app.textFields[...]`) stay as they are.
2. Changes no element types. Typed queries save only about 70 s in all, and every wrong guess
   costs a CI round.
3. Inside **scroll loops only** — `reveal`, `drag`, `scrollList`, `scrollToHittable`,
   `scrollToExist`, `scrollIntoView`, and any loop whose body drags or swipes — replaces
   `waitForExistence(timeout:)` with a plain `.exists` read. **Retry loops around a tap** keep
   their `waitForExistence`, because it is what gives the tap time to land. Examples are
   `openSettings`, `closeSettings`, `openRules`, the forget-confirm loop and the swipe-delete loop.
4. Replaces an `XCTWaiter().wait(for: [XCTNSPredicateExpectation(...)])` with
   `waitUntil(\.<property>, is: <value>)` only when its predicate is a single `==` comparison on
   one of `exists`, `isEnabled`, `isSelected`, `isHittable` or `label`. A predicate that is
   `exists == false` becomes `waitForNonExistence(timeout:)`. Everything else stays exactly as it
   is: any predicate on `value` (it is `Any?`, so not `Equatable`), and any predicate that uses
   `!=`, `NOT`, `OR`, `AND`, `BEGINSWITH`, `CONTAINS` or `MATCHES`.
5. Replaces the file's own `reveal`, `drag` and `formTop` helpers with `reveal(in:)`. The container
   is `app.element("settingsForm")` on the settings form and `app.element("rulesForm")` on the
   rules.

**Launching into a screen.**

- Every `RulesUITests` test launches with `["-MagendaOpen", "rules"]` and first waits for
  `rulesRow.personalBlocks.0`. `openRules` is deleted.
- A `SettingsUITests` test launches with `["-MagendaOpen", "settings"]`, and first waits for
  `settingsDone`, when its first step is a call to `openSettings` with nothing before it. There is
  one exception: `testTheRulesLinkAndTheVersionAreThere` keeps tapping through the agenda, so the
  link itself stays tested.
- Tests that do something on the agenda before opening settings keep `openSettings`.

**iPad-only cleanup (p5).**

- `previewID` becomes the literal `"binderView"`, and `shareID` becomes `"binderShareButton"`.
- Every `XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, ...)` line is deleted. A test
  whose only `throws` came from that line loses `throws`.
- `PreviewUITests.testRenderingAgainAfterGoingBackShowsThePreviewAgainOnIPhone` is deleted.
- `PreviewUITests.swift`'s header comment stops citing `PreviewView.ID`.
- `import UIKit` goes from any file where nothing else needs it.

### D6. Time budget

What one shard's job must fit into, for an 18-minute job:

| Part | Minutes | Basis |
|---|---|---|
| Checkout, xcodegen, simulator pick | 1.5 | Measured: up to 2 min when `simctl list` starts CoreSimulator |
| Build for testing, no boot running alongside | 1 | Measured in the `app` jobs: 40–60 s |
| Boot and wait | 2.5 | Measured in the `app` job: about 3 min before the first test, including install |
| xcodebuild start-up, first launch, teardown, upload | 2.5 | Measured: "Testing" elapsed minus tests, about 110 s, plus 30–50 s first launch |
| **Fixed per job** | **7.5** | |
| **Tests per shard** | **≤ 10.5 (630 s)** | |

Four shards then hold at most **2,520 s** of tests, and no single entry may exceed 630 s. The
targets by class:

| Entry | Now (scaled) | Target | Lever |
|---|---|---|---|
| RulesUITests | 1,980 | ≤ 600 | Launch into the rules (no settings scroll), the bounded `reveal`, animations off |
| SettingsUITests | 1,260 | ≤ 700 | Launch into settings, the bounded `reveal`, animations off |
| All other entries | about 1,770 | ≤ 1,400 | Animations off, no missed waits in scroll loops, one fewer Preview test |
| **Total** | about 5,000 | **≤ 2,700** | |

This is tight. p6 splits any entry over 630 s into per-method entries. If the four shards still
cannot each stay at 630 s or less, p6 stops and reports to the user instead of adding a fifth shard
(see Risks).

### D7. Docs, steward and release pre-flight

**`docs/testing-policy.md`** (p1):

- The layer table's rows 1–3 say "`tests.yml` `ui` shards" instead of `app`. Layer 3 becomes
  "the newest iPad on every PR; the oldest supported runtime weekly and in the release pre-flight".
- The failure-type row reads: "Works on the newest iOS, breaks on the oldest supported iOS".
- The "Layers 1–3: every PR" section and its jobs table list `core`, `lint`, `scripts` and
  `ui (ipad, <runtime>, <1-4>)`. They say that each shard builds once, boots after the build, and
  runs its share of `MagendaTests` and the UI tests, and that `oldest` runs on Mondays and on a
  dispatch with `runtimes: oldest` or `both`.
- Add a paragraph on `scripts/ui_shards.py`:
  - it balances the shards from `CLASS_SECONDS`;
  - a new UI test class needs an entry there (the `scripts` job fails without one);
  - the numbers are refreshed from a green run when a shard's job passes 18 minutes, and a class
    over 630 s is split into per-method entries.
- Drop the boot-before-build paragraph.

**`docs/coding-and-testing-guidelines.md:155`** (p1): "every simulator `tests.yml` runs on a pull
request".

**`.claude/skills/steward/SKILL.md`** (p1), in the dispatch table's simulator row:

- Read the four `ui (ipad, newest, N)` jobs.
- `simulators: false` is allowed only for a branch whose diff touches nothing but `docs/`,
  `CHANGELOG.md`, `.claude/`, or `scripts/` files other than `ui_shards.py`, `simulator.py` and
  `pre_release_check.py`. Any change under `App/`, `AppCore/`, `AppTests/`, `AppUITests/`,
  `project.yml` or `.github/` runs the simulators.
- `/dod`'s simulator row always needs a run with simulators.
- "Ten to twenty minutes" becomes "up to twenty minutes".

**`.claude/toolkit.yaml:45`, `:65-66`** and **`.claude/commands/dod.md:37`** (p1): replace the
`app` jobs and "thirteen ui" with the four `ui (ipad, newest, N)` jobs.

**`scripts/pre_release_check.py:110`** (p1): its message says tests.yml's `ui` jobs.

**Release pre-flight** (p7):

- In `docs/releasing.md:52` and `.claude/commands/cut-release.md:32-39`, the pre-flight dispatches
  `tests.yml` with `runtimes: both` against the same commit, alongside `build.yml`.
- A release waits for both runs to be green.
- This is the only place the oldest runtime gates a release.

## ADRs

All four are written in p7, one decision each. Their numbers follow #17's 0040; if a parallel
branch takes one first, renumber per `docs/adr/README.md` rule 6.

- **0041 — Magenda is an iPad app.** It drops the iPhone device family and the iPhone PDF preview,
  and amends ADR 0020 item 7. It rejects a universal build that CI does not test.
- **0042 — Pull requests test the newest iPad runtime; the oldest supported runtime is tested
  weekly and in the release pre-flight.** It rejects testing every runtime on every PR, and it says
  how a runtime is added later.
- **0043 — Simulator tests run as four shards, balanced from measured timings, and each shard
  builds once.** It rejects:
  - more shards or more sessions (the macOS concurrency cap);
  - parallel testing on cloned simulators inside one runner;
  - a shared build artifact;
  - test retries;
  - pinning the runner image.

  Its consequences cover cancelling stale runs, and turning off app coverage.
- **0044 — UI tests start in the screen they test, with animations off, through launch arguments
  that only a fixture launch reads.**

## Manual steps

The step-by-step page is `docs/fast-tests-plan-manual-steps.html`, and the manifest links its
published version.

- **Before:** nothing. The maintainer has already confirmed that there was never an App Store
  release, so dropping the iPhone family is allowed.
- **After, right before the PR merges:** once #16 and #17 have merged, a maintainer runs
  `python3 scripts/update_branch_protection.py apply`. The PR cannot merge until they do, because
  GitHub keeps waiting for the old `app (...)` checks.

## Risks and open questions

- **#16 or #17 get more commits.** `/implement` merges `feature/summary-routines` into
  `feature/fast-tests` before the next phase. A worker that finds a UI test class or method that
  `CLASS_SECONDS` is missing adds it at 60 s per test method and says so in its report.
- **Animations off breaks a binder test** (a page turn, or the undo scroll). That is a test that
  passed before p5b and fails after, in the Binder, Handoff or StartOver classes only. Fix the
  test's wait, never by re-enabling animations. If what the app shows is wrong, stop with
  `status=blocked`.
- **Presenting the sheet from `.task` is dropped on iPad.** p2's
  `testOpeningOnSettingsShowsTheSettingsSheet` fails. p2 stops with `status=blocked` and reports
  it; it does not add sleeps.
- **`bootstatus -b` after the build brings back launch time-outs** in a shard's first test. p1
  stops and reports the log lines.
- **After p6, a shard's tests are still over 630 s.** p6 stops with `status=blocked` and reports
  the `--table` output. Adding a fifth shard changes ADR 0043's reasoning and the required checks,
  so that is the user's call.
- **The account's macOS cap is higher than 5.** Nothing changes; there is just more headroom.

## Implementation manifest

```yaml
plan_slug: fast-tests
feature_branch: feature/fast-tests
max_parallel: 2
manual_steps_artifact: https://claude.ai/artifact/GGreiC8rzJmCGowqHdNZVU
manual_steps_source: docs/fast-tests-plan-manual-steps.html
manual_before: []
manual_after:
  - id: ma1-apply-required-checks
    title: After #16 and #17 merge, apply the new required checks with scripts/update_branch_protection.py apply
    why: the required checks change from 18 jobs to 7; until a maintainer applies them, GitHub waits for app (...) and old ui (...) checks that no longer run, and the PR cannot merge
verify_after_merge:
  - python3 -m unittest discover -s scripts/tests
final_checks:
  - git grep -n "fast-tests-plan" prints nothing, and docs/fast-tests-plan.md and docs/fast-tests-plan-manual-steps.html are deleted
  - ADRs 0041 to 0044 (or their renumbered successors) exist, are Accepted, and are in docs/adr/README.md's index; ADR 0020's Status has an "Amended by [ADR 0041]" line
  - CHANGELOG.md has the [Unreleased] "### Removed" iPhone line and no new version heading
  - git grep -n "userInterfaceIdiom" -- App AppUITests prints nothing
  - git grep -n -i "iphone" -- .github/workflows/tests.yml prints nothing
  - the PR's last tests.yml run is green with exactly four ui (ipad, newest, N) macOS jobs, each 18 minutes or less
phases:
  - id: p1-ci-shards
    title: Four timed iPad shards with the hosted tests inside them, older runtimes weekly, stale runs cancelled
    depends_on: []
    complexity: M
    touches:
      - .github/workflows/tests.yml
      - scripts/ui_shards.py
      - scripts/tests/test_ui_shards.py
      - scripts/simulator.py
      - scripts/tests/test_scripts.py
      - scripts/update_branch_protection.py
      - scripts/pre_release_check.py
      - project.yml
      - docs/testing-policy.md
      - docs/coding-and-testing-guidelines.md
      - .claude/skills/steward/SKILL.md
      - .claude/toolkit.yaml
      - .claude/commands/dod.md
    brief: |
      Read the plan's "Current state", D2, D3 and D7 first. This phase changes CI and docs only.
      1. Create scripts/ui_shards.py exactly as D3 specifies, with CLASS_SECONDS holding D3's
         numbers (LaunchOptionsUITests is added by p2, not here).
      2. Create scripts/tests/test_ui_shards.py with D3's seven tests.
      3. In scripts/simulator.py, change the --family default to "ipad", and make the first
         usage line of the docstring "python3 scripts/simulator.py   # newest iOS, an iPad -> id=<udid>".
         In scripts/tests/test_scripts.py's TestSimulator:
         - rename test_newest_iphone_by_default to test_newest_iphone;
         - add test_main_picks_an_ipad_by_default: write json.dumps({"devices": self.DEVICES})
           to a tempfile.NamedTemporaryFile, call simulator.main(["--devices-json", path]) with
           stdout captured by contextlib.redirect_stdout(io.StringIO()), and assert the return
           value is 0 and the output is "id=NEW-PAD\n".
      4. Rewrite .github/workflows/tests.yml per D2:
         - keep core, lint and scripts unchanged;
         - add the schedule, the dispatch inputs and the concurrency block, with its comment;
         - delete the app job;
         - replace the ui job with D2's job and steps 1-9, using the generous limits
           (timeout-minutes 45, both allowances 600).
         Update the header comment to say the simulator jobs are four timed shards on the newest
         iPad; name no ADR yet.
      5. In scripts/update_branch_protection.py, set REQUIRED_STATUS_CHECKS to D2's seven.
      6. In project.yml, under schemes.Magenda.test, set gatherCoverageData: false and delete
         coverageTargets. Put "# The coverage ratchet is AppCore's (ADR 0007); the app's coverage is not read."
         on the line above.
      7. Apply D7's edits to docs/testing-policy.md, docs/coding-and-testing-guidelines.md,
         .claude/skills/steward/SKILL.md, .claude/toolkit.yaml, .claude/commands/dod.md and
         scripts/pre_release_check.py. Name no ADR number in them.
      8. Run python3 -m unittest discover -s scripts/tests and python3 scripts/ui_shards.py --check.
         Push, then dispatch tests.yml against this phase branch (simulators=true, runtimes=newest)
         and read the four ui jobs. Change no test to make a shard pass.
      Stop with status=blocked if:
      - GitHub refuses the dispatch inputs;
      - `xcrun simctl bootstatus -b` fails, or a shard's first test times out at launch;
      - the build fails with gatherCoverageData false.
      Report the log lines in each case.
    acceptance:
      - python3 -m unittest discover -s scripts/tests passes, including test_ui_shards.py
      - python3 scripts/ui_shards.py --check exits 0
      - python3 scripts/ui_shards.py --shard 1 prints one line that starts with "-only-testing:"
      - git grep -n -i "iphone" -- .github/workflows/tests.yml prints nothing
      - git grep -n "cancel-in-progress" -- .github/workflows/tests.yml prints one line
      - the dispatched tests.yml run on this branch has exactly ui (ipad, newest, 1) to ui (ipad, newest, 4) as macOS jobs, all green, and one job's log shows the hosted tests ran (a Swift Testing line "Test run with ... tests ... passed")

  - id: p2-launch-options
    title: Fixture-only launch options that open Settings or Rules directly and turn animations off
    depends_on: [p1-ci-shards]
    complexity: M
    touches:
      - AppCore/Sources/Controller/LaunchOptions.swift
      - AppCore/Tests/Controller/LaunchOptionsTests.swift
      - App/LaunchRequest.swift
      - App/AppEnvironment.swift
      - App/MagendaApp.swift
      - App/Screens/AgendaView.swift
      - App/Screens/SettingsView.swift
      - App/Screens/RulesView.swift
      - AppUITests/LaunchOptionsUITests.swift
      - scripts/ui_shards.py
    brief: |
      Read the plan's D4 first. It gives every name, signature and line of wiring.
      1. Create AppCore/Sources/Controller/LaunchOptions.swift as D4 specifies, with a ///
         comment on every public declaration. Read the arguments the way GoogleFixture's
         init?(launchArguments:) does (AppCore/Sources/Controller/GoogleFixtures.swift:18).
      2. Create AppCore/Tests/Controller/LaunchOptionsTests.swift with D4's cases. Use Swift
         Testing, in the style of AppCore/Tests/Controller/GoogleFixturesTests.swift, and
         @Test(arguments:) where cases share one invariant. Open the file with a one-line header
         comment. Every line of LaunchOptions.swift must be covered.
      3. Create App/LaunchRequest.swift exactly as D4 shows.
      4. Wire AppEnvironment.swift, MagendaApp.swift, AgendaView.swift, SettingsView.swift and
         RulesView.swift exactly as D4's "App wiring" says. SettingsView's existing #Preview must
         keep compiling through the new init's default argument.
      5. Create AppUITests/LaunchOptionsUITests.swift with D4's four tests, and add
         "MagendaUITests/LaunchOptionsUITests": 60 to CLASS_SECONDS in scripts/ui_shards.py.
      6. Run swift test --package-path AppCore --filter LaunchOptionsTests (if this container has
         no toolchain, read the dispatched core job instead), python3 scripts/ui_shards.py --check,
         and python3 -m unittest discover -s scripts/tests. Push and dispatch tests.yml against
         this branch. Every existing UI test must still pass, because none passes the new
         arguments yet, and the four new ones must pass.
      Stop with status=blocked if:
      - testOpeningOnSettingsShowsTheSettingsSheet or testOpeningOnRulesShowsTheRules fails (the
        sheet presentation from .task did not happen; report the log, add no sleep);
      - SettingsView's NavigationStack(path:) makes an existing RulesUITests or SettingsUITests
        test fail;
      - UIView.setAnimationsEnabled cannot be called from MagendaApp.init without unsafe
        annotations.
    acceptance:
      - swift test --package-path AppCore --filter LaunchOptionsTests passes (or the dispatched core job is green)
      - the dispatched lint and scripts jobs are green
      - git grep -n "MagendaNoAnimations" -- AppCore/Sources/Controller/LaunchOptions.swift finds it
      - git grep -n "setAnimationsEnabled(false)" -- App/MagendaApp.swift finds it
      - 'git grep -n "navigationDestination(for: Route.self)" -- App/Screens/SettingsView.swift finds it'
      - the dispatched tests.yml run on this branch is green, including the four LaunchOptionsUITests tests

  - id: p3-ipad-only
    title: Make the app iPad-only and remove the iPhone PDF preview
    depends_on: [p2-launch-options]
    complexity: S
    touches:
      - project.yml
      - App/Screens/AgendaView.swift
      - App/Screens/PreviewView.swift
      - App/Screens/PDFKitView.swift
      - README.md
      - docs/release-testing.md
      - CHANGELOG.md
    brief: |
      Read the plan's D1 first.
      1. In project.yml, set TARGETED_DEVICE_FAMILY to "2", delete the
         INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone line, and put "# iPad-only." on
         the line above TARGETED_DEVICE_FAMILY.
      2. In App/Screens/AgendaView.swift:
         - reduce `detail` to its iPad branch;
         - remove the idiom check from the Start Over item, keeping `controller.binder != nil`;
         - rewrite the comments at lines 5-6 and 97-98 so they no longer mention the iPhone;
         - run git grep -n "pdfPreview" -- App, and if AgendaView.ID.pdfPreview is the only hit,
           delete it.
      3. git rm App/Screens/PreviewView.swift App/Screens/PDFKitView.swift. Then run
         git grep -n -e PreviewView -e PDFKitView -e "import PDFKit" -- App and remove what only
         served them.
      4. In README.md, rewrite the iPhone sentences at lines 5 and 69 to describe an iPad app.
         In docs/release-testing.md, make line 45 and any other iPhone mention a real iPad only.
      5. In CHANGELOG.md, add D1's "### Removed" heading and line under [Unreleased], between
         "### Changed" and "### Fixed".
      6. Push and dispatch tests.yml against this branch. The UI tests still have iPhone branches,
         but on an iPad they take the iPad path, so they must pass unchanged.
      Stop with status=blocked if:
      - git grep -n "userInterfaceIdiom" -- App finds a use outside AgendaView;
      - the build fails because something else uses PreviewView or PDFKitView.
    acceptance:
      - git grep -n "userInterfaceIdiom" -- App prints nothing
      - test ! -e App/Screens/PreviewView.swift && test ! -e App/Screens/PDFKitView.swift
      - git grep -n "TARGETED_DEVICE_FAMILY" -- project.yml shows the value "2"
      - git grep -n "no longer runs on iPhone" -- CHANGELOG.md finds it
      - the dispatched tests.yml run on this branch is green

  - id: p4-ui-settings-rules
    title: Shared UI test helpers, and Settings and Rules tests that launch into their screen
    depends_on: [p2-launch-options]
    complexity: M
    touches:
      - AppUITests/MagendaUI.swift
      - AppUITests/RulesUITests.swift
      - AppUITests/SettingsUITests.swift
    brief: |
      Read the plan's "Where the UI test time goes", D5 and D6 first. This is the biggest saving.
      1. Create AppUITests/MagendaUI.swift with D5's helpers. Implement scrollContent(by:) and
         reveal(in:top:bottom:file:line:) exactly as D5 writes them.
      2. Migrate AppUITests/RulesUITests.swift:
         - apply D5's migration rules 1-5;
         - launch every test with ["-MagendaOpen", "rules"] and first wait
           app.element("rulesRow.personalBlocks.0").waitForExistence(timeout: 30), deleting
           openRules;
         - keep closeSettings;
         - use app.element("rulesForm") as the reveal container;
         - map the old `upperHalf: true` to bottom: app.windows.firstMatch.frame.height / 2.
      3. Migrate AppUITests/SettingsUITests.swift the same way:
         - apply D5's "Launching into a screen" rule;
         - keep testTheRulesLinkAndTheVersionAreThere going through openSettings;
         - use app.element("settingsForm") as the reveal container.
      4. Keep every test name, assertion and failure message. Change only how a test gets there
         and how it waits. Delete, skip or weaken no test.
      5. Push and dispatch tests.yml against this branch, and read every job. Put the "Executed N
         tests ... in X seconds" figures for RulesUITests and SettingsUITests in your report.
      Stop with status=blocked if:
      - MagendaUI.swift does not compile;
      - a test fails because -MagendaOpen did not open its screen;
      - after one round of fixing waits, RulesUITests is still over 600 s or SettingsUITests over
        700 s; report the five slowest tests and what their steps spend time on.
    acceptance:
      - test -f AppUITests/MagendaUI.swift
      - git grep -n "MagendaOpen" -- AppUITests/RulesUITests.swift finds it
      - git grep -n "func openRules" -- AppUITests/RulesUITests.swift prints nothing
      - git grep -c "func test" -- AppUITests/RulesUITests.swift prints 12, and for AppUITests/SettingsUITests.swift prints 14
      - the dispatched tests.yml run on this branch is green
      - the report gives RulesUITests at 600 s or less and SettingsUITests at 700 s or less

  - id: p5a-ui-agenda
    title: Move the agenda, preview and sign-in UI tests to the shared helpers and drop their iPhone paths
    depends_on: [p3-ipad-only, p4-ui-settings-rules]
    complexity: M
    touches:
      - AppUITests/AgendaEditUITests.swift
      - AppUITests/AgendaScreenUITests.swift
      - AppUITests/LongTextUITests.swift
      - AppUITests/PreviewUITests.swift
      - AppUITests/SetupUITests.swift
      - AppUITests/SignInUITests.swift
      - AppUITests/LaunchOptionsUITests.swift
    brief: |
      Read D5 first. MagendaUI.swift exists from p4; do not change it. If a helper it lacks would
      serve three or more files, stop with status=blocked and name the helper.
      1. In each file in touches, apply D5's migration rules 1-4. The agenda list's own scrollers
         (scrollToHittable, scrollToExist, scrollIntoView) stay, with rule 3 applied to them.
      2. Apply D5's "iPad-only cleanup" to these files.
      3. In AgendaScreenUITests, the `if UIDevice.current.userInterfaceIdiom == .pad` block near
         line 146: keep its iPad body, and delete the condition and the else branch.
      4. Delete, skip or weaken no other test, and keep every other test name.
      5. Push and dispatch tests.yml against this branch. All four shards must be green. Put each
         class's "Executed N tests ... in X seconds" figure in your report.
    acceptance:
      - git grep -n -e "userInterfaceIdiom" -e "XCTSkipUnless" -- AppUITests/AgendaEditUITests.swift AppUITests/AgendaScreenUITests.swift AppUITests/LongTextUITests.swift AppUITests/PreviewUITests.swift prints nothing
      - git grep -n "testRenderingAgainAfterGoingBackShowsThePreviewAgainOnIPhone" prints nothing
      - git grep -n "private func launch" -- AppUITests/AgendaEditUITests.swift AppUITests/AgendaScreenUITests.swift AppUITests/LongTextUITests.swift AppUITests/PreviewUITests.swift AppUITests/SetupUITests.swift AppUITests/SignInUITests.swift AppUITests/LaunchOptionsUITests.swift prints nothing
      - the dispatched tests.yml run on this branch is green

  - id: p5b-ui-binder
    title: Move the binder, hand-off and Start Over UI tests to the shared helpers and drop their iPad-only skips
    depends_on: [p3-ipad-only, p4-ui-settings-rules]
    complexity: M
    touches:
      - AppUITests/BinderUITests.swift
      - AppUITests/HandoffUITests.swift
      - AppUITests/StartOverUITests.swift
    brief: |
      Read D5 and the plan's Risks first. These classes are where animations off is most likely
      to matter. MagendaUI.swift exists from p4; do not change it.
      1. In each file in touches, apply D5's migration rules 1-4. Keep the -MagendaFingerDrawing
         and -MagendaBinderStoreFile arguments that tests pass today, as extra arguments to
         launchMagenda. A test that relaunches onto the same store relaunches with launchMagenda
         too.
      2. Delete every XCTSkipUnless on the idiom, drop `throws` where nothing else throws, and
         drop import UIKit where nothing needs it.
      3. Delete, skip or weaken no test, and keep every test name.
      4. Push and dispatch tests.yml against this branch. All four shards must be green. Put each
         class's "Executed N tests ... in X seconds" figure in your report.
      Stop with status=blocked if a test fails with animations off and the failure is in what the
      app shows, not in how the test waits.
    acceptance:
      - git grep -n -e "userInterfaceIdiom" -e "XCTSkipUnless" -- AppUITests/BinderUITests.swift AppUITests/HandoffUITests.swift AppUITests/StartOverUITests.swift prints nothing
      - git grep -n "private func launch" -- AppUITests/BinderUITests.swift AppUITests/HandoffUITests.swift AppUITests/StartOverUITests.swift prints nothing
      - the dispatched tests.yml run on this branch is green

  - id: p6-measure
    title: Record measured timings, rebalance the shards, and tighten the time limits
    depends_on: [p5a-ui-agenda, p5b-ui-binder]
    complexity: S
    touches:
      - scripts/ui_shards.py
      - .github/workflows/tests.yml
    brief: |
      Read D3 and D6 first.
      1. Dispatch tests.yml against this phase branch (simulators=true, runtimes=newest) and wait
         for a green run. If it is red, stop with status=blocked and report the failure; do not
         fix tests here.
      2. From each ui (ipad, newest, N) job's log (mcp__github__get_job_logs), collect:
         - every UI class's "Test Suite '<Class>' passed at ... Executed N tests ... in X seconds"
           figure;
         - every "Test Case '-[MagendaUITests.<Class> <method>]' passed (X seconds)" line;
         - for MagendaTests, the seconds on its Swift Testing line "Test run with N tests in M
           suites passed after X seconds", plus 20.
      3. Set every CLASS_SECONDS value to its measured seconds, rounded up to a multiple of 10.
         For any class over 630 s, replace its key with one key per test method
         ("MagendaUITests/<Class>/<method>"), each at its own measured seconds, rounded up the
         same way. Update the comment above CLASS_SECONDS to name the run ID.
      4. Run python3 scripts/ui_shards.py --table and --check, and
         python3 -m unittest discover -s scripts/tests. Put the --table output in your report.
      5. In .github/workflows/tests.yml:
         - set the ui job's timeout-minutes to 25;
         - let L be the longest single test measured in step 2;
         - set -default-test-execution-time-allowance to the smallest multiple of 60 that is at
           least 2 × L and at least 120;
         - set -maximum-test-execution-time-allowance to twice that.
      6. Push, dispatch tests.yml again, and record:
         - each ui job's duration, as completed_at − started_at from mcp__github__actions_list
           list_workflow_jobs;
         - the run's wall time, from the first job's start to the last job's end.
      Stop with status=blocked if any shard in the --table output is over 630 s, or any ui job in
      step 6 takes more than 18 minutes. Report the table and the per-class figures; do not add a
      fifth shard.
    acceptance:
      - python3 scripts/ui_shards.py --check exits 0
      - the comment above CLASS_SECONDS names a tests.yml run ID
      - git grep -n "timeout-minutes: 25" -- .github/workflows/tests.yml finds the ui job's line
      - the second dispatched run is green, and the report lists every ui (ipad, newest, N) job at 18 minutes or less

  - id: p7-retire
    title: ADRs 0041 to 0044, the release pre-flight, standing docs, and retire the plan
    depends_on: [p6-measure]
    complexity: S
    touches:
      - docs/adr/0041-magenda-is-an-ipad-app.md
      - docs/adr/0042-pull-requests-test-the-newest-ipad-runtime.md
      - docs/adr/0043-simulator-tests-run-in-four-timed-shards.md
      - docs/adr/0044-ui-tests-start-in-the-screen-they-test.md
      - docs/adr/0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md
      - docs/adr/README.md
      - docs/testing-policy.md
      - docs/releasing.md
      - .claude/commands/cut-release.md
      - .github/workflows/tests.yml
      - project.yml
      - docs/fast-tests-plan.md
      - docs/fast-tests-plan-manual-steps.html
    brief: |
      1. Check the next free ADR number on this branch (ls docs/adr). If 0041 is taken, number
         the four ADRs from the next free one, and use those numbers (and matching file names)
         in every step below.
      2. Write the four ADRs in the plan's ADRs section from the template in docs/adr/README.md,
         with Status "Accepted — <today>":
         - 0041 from D1;
         - 0042 from D2's triggers and matrix, and D7's release pre-flight;
         - 0043 from D2's job, D3 and D6, with D2's rejected list;
         - 0044 from D4 and D5.
         Put the measured numbers from "Current state", and p6's figures from the merge commit
         messages or the phase reports, into Context and Consequences. Link only to source
         files, other ADRs and run URLs, never to this plan.
      3. In ADR 0020's Status, after the existing Amended-by lines, add:
         "Amended by [ADR 0041](0041-magenda-is-an-ipad-app.md): Magenda is iPad-only, so item 7's iPhone preview is gone."
         Change nothing else in ADR 0020.
      4. Add the four ADRs to the index in docs/adr/README.md.
      5. In docs/releasing.md (the pre-flight paragraph at line 52) and
         .claude/commands/cut-release.md (lines 32-39), add D7's release pre-flight: dispatch
         tests.yml with runtimes=both against the same commit, and wait for both it and build.yml
         to be green. Cite ADR 0042.
      6. Cite ADR 0042 and ADR 0043 in docs/testing-policy.md where the runtimes and shards are
         described, and ADR 0044 where the launch arguments are mentioned. Cite ADR 0043 in
         tests.yml's header comment. Change project.yml's "# iPad-only." to
         "# iPad-only (ADR 0041)."
      7. git rm docs/fast-tests-plan.md docs/fast-tests-plan-manual-steps.html, then
         git grep -n "fast-tests-plan" and fix anything that still refers to them.
      8. Run python3 -m unittest discover -s scripts/tests (it includes the no-project-history
         guard).
    acceptance:
      - ls docs/adr/0041-*.md docs/adr/0042-*.md docs/adr/0043-*.md docs/adr/0044-*.md lists four files (or their renumbered successors)
      - git grep -n "Amended by \[ADR 0041\]" -- docs/adr finds the line in ADR 0020
      - git grep -n "runtimes" -- docs/releasing.md .claude/commands/cut-release.md finds the pre-flight in both
      - git grep -n "fast-tests-plan" prints nothing
      - python3 -m unittest discover -s scripts/tests passes
```
