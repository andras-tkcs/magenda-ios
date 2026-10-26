# Plan: tests that finish in 20 minutes

## Goal

A pull request's `tests.yml` run finishes in **20 minutes or less** of wall-clock time once runners
are available. Today a green run takes over three hours, and a single shard can hit its 40-minute
timeout. To get there:

- **Magenda becomes iPad-only.** The binder and its Pencil ink are the product (ADR 0020), and the
  iPhone's read-only PDF preview no longer earns its own test matrix. The app drops the iPhone
  device family, the iPhone-only preview code and the iPhone tests.
- **Pull requests test the newest iPad runtime only.** Older runtimes still run, weekly and on
  dispatch, so supporting "a few iOS versions" later only means adding the version to a list.
- **The UI tests get cheaper.** They launch straight into the screen they test, run with
  animations off, find elements with typed queries, and stop polling with waits that miss.
- **CI runs four timed shards.** Each shard builds once, runs the hosted tests and a share of the
  UI tests, and the shards are balanced from measured class timings.

No GitHub issue tracks this; it came from a `/make-plan` request.

## Current state

The plan branch is cut from `feature/summary-routines` (PR #17, stacked on PR #16), so it includes
every UI test those PRs add. Line references below are on that branch.

### CI shape

`.github/workflows/tests.yml` has these jobs:

- `core`, `lint` and `scripts` on Ubuntu, about 2 minutes together.
- `app (family, runtime)` on macOS, 3 jobs: iPhone newest, iPhone oldest and iPad newest. Each one
  builds and runs the hosted `MagendaTests`.
- `ui (family, runtime, shard)` on macOS, 13 jobs. iPhone newest and iPhone oldest each have the
  `edit-screen`, `settings`, `rules` and `rest` shards. The iPad has those four plus `binder`.

That is **16 macOS jobs per run**, and each one generates the project and builds for itself.
`scripts/update_branch_protection.py:25-46` (`REQUIRED_STATUS_CHECKS`) lists all of them as
required.

GitHub runs at most 5 macOS jobs at once on a Free or Pro account, so 16 jobs run in about four
waves. `/implement` also dispatches `tests.yml` from several phase sessions at the same time, and
those runs queue behind each other. Nothing cancels a superseded run.

### Measured timings

These come from run 40294684850 (`feature/send-meeting-early`, green, 26 October 2026, before #16
and #17 added their tests).

The run itself:

- The run took **3 h 38 min** of wall-clock time, from 08:47 to 12:25. macOS jobs waited up to
  2 h 20 min for a runner.
- `build-for-testing` takes **40–60 s** in an `app` job. In a `ui` job it takes **4–7.5 min**,
  because that job boots the simulator at the same time (the "Boot the simulator" step before
  "Build for testing").
- The hosted tests take **18 s**. The `app (ipad, newest)` job spends about **3 min** in front of
  them, booting the simulator and installing the app.

The iPad UI tests take **3,646 s (61 min)** in all, spread over four shards:

| Shard | Classes | Tests took | Job took |
|---|---|---|---|
| `rest` | Preview, Rules, Setup, SignIn | 1,529 s | 34 min |
| `settings` | Settings | 897 s | 23 min |
| `binder` | Binder, Handoff, StartOver | 704 s | 22 min |
| `edit-screen` | AgendaEdit, AgendaScreen, LongText | 516 s | 19 min |

Per class, in seconds, with the test count on this branch in brackets:

- Rules 1,318 (12)
- Settings 897 (14)
- Binder 390 (13)
- AgendaEdit 320 (7)
- Handoff 258 (8)
- Preview 161 (5)
- AgendaScreen 118 (5)
- LongText 79 (2)
- StartOver 55 (2)
- SignIn 25 (2)
- Setup 24 (1)

The Rules and Settings classes are **61%** of all UI test time. The slowest tests are
`testResetRulesRestoresTheDefaults` at 280 s and `testADuplicateSummaryTitleShowsAnError` at
203 s.

### Where the UI test time goes

1. **Scroll-to-reveal loops (about 1,000 s).** `RulesUITests.reveal` (`AppUITests/RulesUITests.swift:110`)
   and `SettingsUITests.reveal` (`AppUITests/SettingsUITests.swift:68`) are the loops. In each
   iteration:
   - they probe with `waitForExistence(timeout: 1)` or `waitForExistence(timeout: 2)`;
   - they re-query `settingsDone` and the target;
   - they drag 100–300 points, anchored on the Done button.

   One iteration costs about **8.5 s**, and there were 116 of them. Every Rules test opens the
   Settings sheet and scrolls to `rulesLink` before it starts.
2. **Waits that miss (about 620 s).** A `waitForExistence` that times out costs about **4 s**, not
   1–2 s. After the timeout, XCTest captures an element debug description, which takes four
   full accessibility snapshots. There were 148 such misses, almost all inside the reveal loops.
   An `XCTNSPredicateExpectation` also polls only once a second.
3. **Untyped queries.** Each test file has an `element(_:_:)` helper that runs
   `descendants(matching: .any)[id]`, which takes about 0.5–1 s for each `Find`. On text fields,
   `Find` averages 1.4 s and `Tap` averages 7.8 s.
4. **Idle waits after taps (about 200 s).** These come from animations: sheets, navigation pushes
   and the keyboard. The app has no way to turn animations off.
5. **Launches (about 700 s).** Each of the 60 launches takes about 10 s, and the first launch on a
   fresh simulator takes 24–52 s. This is a fixed cost, and this plan does not change it.

### iPhone-specific code

- `project.yml:42` sets `TARGETED_DEVICE_FAMILY: "1,2"`, and `project.yml:48` sets
  `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`.
- `App/Screens/AgendaView.swift:214` (`detail`) and `:238` (`toolbar`) branch on
  `UIDevice.current.userInterfaceIdiom == .pad`. The iPhone branch shows `PreviewView`, which
  wraps `PDFKitView`. Nothing else uses either of those files.
- The UI tests switch on `userInterfaceIdiom`:
  - `previewID` in AgendaEdit, AgendaScreen, LongText, Preview and Settings;
  - `shareID` in Preview;
  - `XCTSkipUnless(... == .pad)` in Binder, Handoff, StartOver, Preview and AgendaEdit;
  - one iPhone-only test, `PreviewUITests.testRenderingAgainAfterGoingBackShowsThePreviewAgainOnIPhone`.

  An iPad's `horizontalSizeClass` can still be compact (Slide Over, Split View), so the views keep
  their size-class logic.
- Version 0.1.1 shipped to TestFlight only (ADR 0019). Nothing is on the App Store yet.

## Design

### D1. iPad-only app

- In `project.yml`, set `TARGETED_DEVICE_FAMILY: "2"`, delete the
  `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` line, and add one comment line above the
  setting: `# iPad-only (ADR 0041).`
- In `AgendaView`:
  - `detail` keeps only today's iPad branch: the binder, or the "No binder yet" placeholder.
  - `toolbar`'s Start Over item drops the `UIDevice.current.userInterfaceIdiom == .pad` condition
    and keeps `controller.binder != nil`.
  - Delete `ID.pdfPreview` if nothing in `App/` uses it any more.
- Delete `App/Screens/PreviewView.swift` and `App/Screens/PDFKitView.swift`.
- `CHANGELOG.md` `[Unreleased]` gets a `### Removed` heading (create it after the existing
  headings if it is missing) with this line:
  `- Magenda no longer runs on iPhone; it is an iPad app.`
- `scripts/simulator.py`'s `--family` default becomes `ipad`. The `iphone` choice stays, because
  the picker is device-agnostic. `scripts/pre_release_check.py` uses the default, so on macOS it
  now tests on an iPad.
- `README.md` and `docs/release-testing.md` stop describing an iPhone.
- ADR 0020 is not edited. ADR 0041 amends it: item 7, "The iPhone keeps the read-only PDF
  preview", no longer holds. ADR 0020's Status gains one line: `Amended by 0041.`

Rejected:

- **Keep the app universal and only drop iPhone CI.** That ships an iPhone build nobody tests.
- **Keep `PreviewView` "for later".** No later use is planned, and dead code is untested code.

### D2. CI shape (`tests.yml`)

**Triggers.** Unchanged except for two additions:

- `schedule: - cron: "17 3 * * 1"` (Mondays 03:17 UTC).
- `workflow_dispatch.inputs`:
  ```yaml
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

**Concurrency.** At the top level:

```yaml
concurrency:
  group: tests-${{ github.event_name }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' || github.event_name == 'workflow_dispatch' }}
```

A new push to a PR, or a new dispatch on the same branch, cancels the stale run. Pushes to `main`
or `releases/**` and the weekly run are never cancelled.

**The `app` job is deleted.** The hosted tests run inside a `ui` shard (D3).

**The `ui` job:**

```yaml
ui:
  name: ui (ipad, ${{ matrix.runtime }}, ${{ matrix.shard }})
  if: github.event_name != 'workflow_dispatch' || inputs.simulators
  runs-on: macos-latest
  timeout-minutes: 30
  strategy:
    fail-fast: false
    matrix:
      runtime: ${{ fromJSON((github.event_name == 'schedule' || inputs.runtimes == 'both') && '["newest","oldest"]' || (inputs.runtimes == 'oldest' && '["oldest"]' || '["newest"]')) }}
      shard: [1, 2, 3, 4]
  env:
    RUNTIME: ${{ matrix.runtime }}
    SHARD: ${{ matrix.shard }}
```

Its steps, in this order:

1. Check out the repository, with the same pinned `actions/checkout` SHA as today.
2. `xcodebuild -version`.
3. `brew install xcodegen && xcodegen generate`.
4. Pick a simulator:
   `echo "DESTINATION=$(python3 scripts/simulator.py --family ipad --runtime "$RUNTIME")" >> "$GITHUB_ENV"`.
5. Choose the shard's tests: `echo "SHARD_ARGS=$(python3 scripts/ui_shards.py --shard "$SHARD")" >> "$GITHUB_ENV"`.
6. Build for testing: the same command as today, with `-quiet`.
7. Boot the simulator and wait for it: `xcrun simctl bootstatus "${DESTINATION#id=}" -b`. The
   comment on this step says why it comes after the build: a boot that overlaps the build slows
   the build from about 1 minute to 4–7 minutes; `bootstatus -b` boots the device and returns only
   once it is fully up, so the first test still does not launch into a half-booted simulator.
8. Run the tests (100% pass rate required):
   ```
   xcodebuild test-without-building -project Magenda.xcodeproj -scheme Magenda \
     -destination "$DESTINATION" -derivedDataPath build/DerivedData \
     -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
     -maximum-test-execution-time-allowance 300 \
     $SHARD_ARGS -resultBundlePath "build/tests-$SHARD.xcresult"
   ```
   Keep the existing "deliberately unquoted" comment for `SHARD_ARGS`.
9. On failure, upload the result bundle as `xcresult-ipad-${{ matrix.runtime }}-${{ matrix.shard }}`,
   with the same pinned `upload-artifact` SHA and a 14-day retention.

**Required checks.** `REQUIRED_STATUS_CHECKS` becomes:

```
core, lint, scripts,
ui (ipad, newest, 1), ui (ipad, newest, 2), ui (ipad, newest, 3), ui (ipad, newest, 4)
```

The `oldest` jobs never run on a PR, so they are not required.

**Scheme.** In `project.yml`, set `schemes.Magenda.test.gatherCoverageData` to `false` and delete
`coverageTargets`. Nothing reads the app's coverage; the ratchet is AppCore's (ADR 0007).
Coverage instrumentation slows both the build and the UI tests.

Rejected:

- **More shards, or more parallel sessions.** The 5-job macOS cap is per account. Every extra job
  pays about 3–4 minutes of fixed cost (checkout, project generation, simulator pick, build, boot)
  and waits longer in the queue. The time-outs seen earlier came from degraded runners, not from
  too few shards. Four shards leave one macOS slot free for a second run.
- **Parallel testing on cloned simulators inside one runner**
  (`-parallel-testing-enabled YES`). A hosted macOS runner has 3 cores and 7 GB of memory, and two
  iPad simulator clones on it make launch time-outs likelier, not rarer.
- **One build job that hands its products to the test jobs as an artifact.** It adds a serial
  step and an upload and download of several hundred MB to save about 1 minute of build per
  shard, once the boot no longer overlaps the build.
- **Retrying failed tests** (`-retry-tests-on-failure`). The steward skill treats a test that
  passes on retry as a hidden wait bug. The test timeouts above make a hang fail fast instead.
- **Pinning the runner image** (`macos-26`). `build.yml` archives on `macos-latest`. Testing on a
  different Xcode than the one that ships would test the wrong thing.

### D3. `scripts/ui_shards.py`

This is a new script, standard library only. It follows the style of `scripts/simulator.py`: a
module docstring with usage, `from __future__ import annotations`, and `main(argv) -> int`.

```python
SHARD_COUNT = 4

# Seconds each test target or UI test class took in the last measured tests.yml run on the newest
# iPad. Shards are balanced from these, so a class missing here fails `--check` and the scripts job.
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

The numbers above are this plan's estimates: the measured class totals, scaled by each class's
test count on this branch. Phase `p6-measure` replaces them with measured values.

The script's functions:

- `ui_test_classes(directory: Path) -> set[str]` reads every `*.swift` in `directory` and returns
  `"MagendaUITests/<Name>"` for each match of `^final class (\w+): XCTestCase` (multiline).
- `expected_entries(directory: Path) -> set[str]` returns `{"MagendaTests"} | ui_test_classes(directory)`.
- `assign(seconds: dict[str, int], count: int) -> list[list[str]]` splits the entries into
  shards, longest processing time first:
  - Sort the entries by `(-seconds, name)`.
  - Put each entry into the shard with the smallest running total. On a tie, use the lowest
    index.
  - Return each shard's entries sorted by name.
- `arguments(entries: list[str]) -> list[str]` returns `["-only-testing:" + e for e in entries]`.
- The CLI:
  - `--shard N` (1-based, `1 <= N <= --count`, default count `SHARD_COUNT`) prints that shard's
    arguments space-separated on one line.
  - `--check` compares `CLASS_SECONDS`' keys with
    `expected_entries(<repo>/AppUITests)`. It prints `missing from CLASS_SECONDS: …` and
    `stale in CLASS_SECONDS: …` lines and exits 1 on any difference, otherwise it exits 0.
  - `--table` prints one line per shard: `shard N: <total> s: <entries comma-separated>`.
  - Exactly one of `--shard`, `--check` and `--table` is required (an argparse mutually exclusive
    group).

The tests go in a new file, `scripts/tests/test_ui_shards.py`, and load the module the way
`scripts/tests/test_scripts.py:39` loads `simulator`. They check:

1. `--check` passes on the repository: `CLASS_SECONDS` matches `AppUITests/`.
2. `assign` places every entry exactly once, for counts 1 to 6.
3. `assign` on `{"a": 10, "b": 9, "c": 8, "d": 1}` with count 2 returns `[["a", "d"], ["b", "c"]]`.
4. `assign` is deterministic: two calls return equal results.
5. The `shard:` line in `.github/workflows/tests.yml` lists exactly `1..SHARD_COUNT`. Find it with
   the regex `shard: \[([\d, ]+)\]`.
6. `update_branch_protection.REQUIRED_STATUS_CHECKS` contains `ui (ipad, newest, N)` for every N
   in `1..SHARD_COUNT`, and nothing else starting with `ui (` or `app (`.
7. `ui_test_classes` on a temporary directory holding two fake Swift files finds both classes and
   ignores a `class Helper` that is not an `XCTestCase`.

### D4. Fixture launch options (AppCore and App)

**New file `AppCore/Sources/Controller/LaunchOptions.swift`:**

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
    public init(arguments: [String])

    /// What a launch without either argument gets.
    public static let standard: LaunchOptions
}
```

It is tested in `AppCore/Tests/Controller/LaunchOptionsTests.swift`, a `@Suite("Launch options")`
with these cases:

- no arguments gives `.standard` (screen `nil`, `animates == true`);
- `-MagendaOpen settings`;
- `-MagendaOpen rules`;
- `-MagendaOpen bogus` gives `nil`;
- a trailing `-MagendaOpen` gives `nil`;
- `-MagendaNoAnimations` gives `animates == false`;
- both arguments together;
- the arguments in any order around `-MagendaFixture standard`.

**App wiring:**

- `App/AppEnvironment.swift`:
  - `AppServices` gains `let launch: LaunchOptions`.
  - The fixture branch passes `LaunchOptions(arguments: arguments)`.
  - The live branch passes `.standard`. A real launch never honours these arguments.
- `App/Rendering/PageDrawer.swift:93-95` holds the existing `@Entry` values. Next to them, add
  `@Entry var launchOptions = LaunchOptions.standard`.
- `App/MagendaApp.swift`:
  - Add `import UIKit`.
  - In `init()`, after `services` is set:
    `if services?.launch.animates == false { UIView.setAnimationsEnabled(false) }`. Since
    `services` is a `State` wrapper there, compute the services into a local `let` first, then
    assign `_services`.
  - On `RootView` in the body, add `.environment(\.launchOptions, services.launch)` and:
    ```swift
    .transaction { transaction in
        if !services.launch.animates {
            transaction.disablesAnimations = true
            transaction.animation = nil
        }
    }
    ```
- `App/Screens/AgendaView.swift`:
  - Add `@Environment(\.launchOptions) private var launchOptions`,
    `@State private var appliedLaunch = false` and `@State private var settingsOpensRules = false`.
  - Add `.onAppear` on the `NavigationSplitView`:
    ```swift
    guard !appliedLaunch else { return }
    appliedLaunch = true
    if let screen = launchOptions.screen {
        settingsOpensRules = screen == .rules
        showsSettings = true
    }
    ```
  - The settings sheet becomes
    `.sheet(isPresented: $showsSettings, onDismiss: { settingsOpensRules = false }) { SettingsView(appInfo: appInfo, opensRules: settingsOpensRules) }`.
- `App/Screens/SettingsView.swift`:
  - Add a nested `enum Route: Hashable { case rules }`.
  - Add `@State private var path: [Route]`.
  - Add `init(appInfo: AppInfo, opensRules: Bool = false)`, which sets `self.appInfo` and
    `_path = State(initialValue: opensRules ? [.rules] : [])`. Keep every other stored property's
    default.
  - `NavigationStack {` becomes `NavigationStack(path: $path) {`.
  - The rules link becomes `NavigationLink("Binder rules", value: Route.rules)`, with its
    `.accessibilityIdentifier(ID.rulesLink)` kept.
  - Add `.navigationDestination(for: Route.self) { _ in RulesView() }` on the `Form`.
  - Add `static let form = "settingsForm"` to `ID`, and `.accessibilityIdentifier(ID.form)` on the
    `Form`.
- `App/Screens/RulesView.swift`: add `static let form = "rulesForm"` to its `ID` enum, and
  `.accessibilityIdentifier(ID.form)` on the `Form` at line 72.

### D5. Shared UI test support (`AppUITests/MagendaUI.swift`)

This is a new file. It opens with the standard header comment, and every helper is `@MainActor`.

```swift
extension XCUIApplication {
    /// Launches Magenda on `fixture` with animations off, plus `extra` arguments.
    static func launchMagenda(fixture: String = "standard", _ extra: [String] = []) -> XCUIApplication
    // launchArguments = ["-MagendaFixture", fixture, "-MagendaNoAnimations"] + extra

    /// The element with `identifier`. Pass the element's type whenever it is known: a typed query
    /// is several times faster than `.any`.
    func element(_ identifier: String, _ type: XCUIElement.ElementType = .any) -> XCUIElement
    // descendants(matching: type)[identifier].firstMatch
}

extension XCUIElement {
    /// Waits until `keyPath` equals `value`. Uses Xcode's `wait(for:toEqual:timeout:)`, which does
    /// not poll once a second as an `XCTNSPredicateExpectation` does.
    @discardableResult
    func waitUntil<V: Equatable>(_ keyPath: KeyPath<XCUIElement, V>, is value: V, timeout: TimeInterval = 30) -> Bool

    /// Scrolls `container` in held 300-point drags until this element is hittable and its middle
    /// lies between `top` and `bottom`, then stops. Between drags it reads `exists` and `frame`
    /// without waiting. It drags further down 10 times, then back up 10 times, and fails the test
    /// if the element never fits.
    func reveal(in container: XCUIElement, top: CGFloat = 0, bottom: CGFloat = .greatestFiniteMagnitude,
                file: StaticString = #filePath, line: UInt = #line)
}
```

`reveal`'s drag goes from the container's normalized point `(0.5, 0.75)` to `(0.5, 0.75)` offset
by `-300` (or `+300` when scrolling back up). It uses
`press(forDuration: 0.05, thenDragTo:withVelocity: 600, thenHoldForDuration: 0.2)`. Before each
drag, it moves the target into view as follows:

- if the element exists and its `frame.midY < top`, it drags up 150 points;
- if `frame.midY > bottom`, it drags down by `min(frame.midY - bottom + 40, 300)`.

**Rules for the migration (phases p4 and p5).** Each test file:

1. Deletes its private `launch`/`element` helpers and calls `XCUIApplication.launchMagenda` and
   `app.element(_:_:)`.
2. Picks the query type from the identifier:
   - `.button` for identifiers ending in `Button`, `Link` or `Done`, and for those starting with
     `eventRow.`;
   - `.textField` for identifiers ending in `Field`;
   - `.switch` for identifiers starting with `editSummary.` or ending in `Toggle`;
   - `.any` otherwise.

   If a typed query makes a test fail in CI, that identifier goes back to `.any`, with a short
   comment on the element type that was not matched.
3. Replaces every `waitForExistence(timeout:)` inside a loop (a reveal, a retry or a scroll) with
   a plain `.exists` read. A `waitForExistence` that waits once for something that must appear
   stays as it is.
4. Replaces each `XCTWaiter().wait(for: [XCTNSPredicateExpectation(...)])` on a single property
   with `waitUntil(\.<property>, is:)`. Predicates with `OR`, `BEGINSWITH` or `CONTAINS` stay as
   they are.
5. Drops the test's own `reveal`/`drag`/`formTop` helpers in favour of `reveal(in:)`. The
   container is `app.element("settingsForm")` on the settings form and `app.element("rulesForm")`
   on the rules.

**Launching into a screen:**

- Every `RulesUITests` test launches with `["-MagendaOpen", "rules"]` and waits for
  `rulesRow.personalBlocks.0`, instead of calling `openRules`.
- A `SettingsUITests` test launches with `["-MagendaOpen", "settings"]` and waits for
  `settingsDone` when its first step is `openSettings` with nothing before it. There is one
  exception: `testTheRulesLinkAndTheVersionAreThere`, which still taps through the UI so the link
  itself stays tested.
- Tests that do something on the agenda before opening settings keep `openSettings`.

**iPad-only cleanup:**

- `previewID` becomes the literal `"binderView"`, and `shareID` becomes `"binderShareButton"`.
- Every `XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, ...)` line is deleted. A test
  whose only `throws` came from that line loses `throws`.
- `PreviewUITests.testRenderingAgainAfterGoingBackShowsThePreviewAgainOnIPhone` is deleted, and
  `import UIKit` goes where nothing else needs it.

### D6. Docs and steward

- `docs/testing-policy.md`:
  - The jobs table lists `core`, `lint`, `scripts` and `ui (ipad, <runtime>, <1-4>)`.
  - Layer 3 becomes "newest iPad on every PR; the oldest supported runtime weekly (Monday) and on
    dispatch with `runtimes: oldest` or `both`".
  - The failure-type row reads "Works on the newest iOS, breaks on the oldest supported iOS".
  - Add a paragraph saying that `scripts/ui_shards.py` balances the shards from `CLASS_SECONDS`,
    that a new UI test class needs an entry there (the `scripts` job fails without one), and that
    the numbers are refreshed from a green run's "Executed … in N seconds" lines when a shard's
    job passes 18 minutes.
  - Drop the boot-before-build paragraph, and say the boot follows the build instead (D2 step 7).
- `.claude/skills/steward/SKILL.md`, in the dispatch table's simulator row:
  - read the four `ui (ipad, newest, N)` jobs;
  - a session whose branch changes nothing under `App/`, `AppTests/`, `AppUITests/` or
    `project.yml` dispatches with `simulators: false`, so it only waits for `core`, `lint` and
    `scripts`;
  - "Ten to twenty minutes" becomes "up to twenty minutes".

## ADRs

All three ADRs are written in `p7-retire`. Their numbers follow #17's 0040; if a parallel branch
takes one first, renumber per `docs/adr/README.md` rule 6.

- **0041 — Magenda is an iPad app.** It drops the iPhone device family and the iPhone PDF preview,
  and amends ADR 0020's item 7. It rejects keeping a universal build that CI does not test.
- **0042 — Pull requests test the newest iPad in four timed shards; older runtimes run weekly.**
  It covers D2 and D3. It rejects more shards or sessions (the macOS concurrency cap), in-runner
  parallel testing, a shared build artifact, test retries and pinning the runner image.
- **0043 — UI tests start in the screen they test, with animations off, through fixture-only
  launch arguments.** It covers D4 and D5. It also covers why these arguments are honoured only
  with `-MagendaFixture` (a real launch never reads them).

## Manual steps

The step-by-step page is `docs/fast-tests-plan-manual-steps.html`; its published link is in the
manifest.

- **Before:** confirm in App Store Connect that Magenda has never been released on the App Store.
  Apple does not let an update drop a device family that an App Store release supported;
  TestFlight builds do not count.
- **After, before the PR merges:** apply the new required checks with
  `python3 scripts/update_branch_protection.py apply`. Without it, the PR waits forever on
  `app (...)` checks that no longer run. Then confirm on a real iPad that the TestFlight build of
  the merged `main` installs and opens the binder. That second check needs a tag, so do it at the
  next release; the PR item only records that it is owed.

## Risks and open questions

- **#16 or #17 change again.** If either PR gets more commits, `/implement` merges
  `feature/summary-routines` into `feature/fast-tests` before the next phase. A phase whose
  `touches` list has a file that changed upstream re-reads it first. A worker that finds a UI test
  class not in D3's `CLASS_SECONDS` adds it with its test count × 60 s and notes it in its
  report.
- **#16/#17 merge before this PR, or after.** Either way works, because the PR has merge commits.
  If they merge first, the feature branch merges `main` once before its PR opens.
- **`wait(for:toEqual:timeout:)` is missing from the runner's Xcode** (it needs Xcode 16 or later).
  The build fails on `MagendaUI.swift`. Stop with `status=blocked`; do not hand-roll a polling
  loop.
- **Animations off breaks a binder test.** For example, a page turn or the undo scroll could
  depend on an animation finishing. That shows as a test that passed before p4 or p5 and fails
  after, only in the binder or hand-off classes. Fix the test's wait, never by re-enabling
  animations for that class. If the failure is in app behaviour, not in the test, stop with
  `status=blocked`.
- **`bootstatus -b` after the build brings back launch time-outs** in the first test of a shard.
  Stop and report the log lines; do not move the boot back in front of the build without a
  measurement.
- **The macOS cap is higher than 5** (a paid plan). Nothing breaks; there is just more headroom.
- **After p6 a shard's job still takes over 18 minutes.** p6 stops with `status=blocked` and
  reports the per-class table rather than adding a fifth shard. A fifth shard changes ADR 0042's
  reasoning and the required checks, and that is the user's call.

## Implementation manifest

```yaml
plan_slug: fast-tests
feature_branch: feature/fast-tests
max_parallel: 2
manual_steps_artifact: https://claude.ai/artifact/GGreiC8rzJmCGowqHdNZVU
manual_steps_source: docs/fast-tests-plan-manual-steps.html
manual_before:
  - id: mb1-no-app-store-release
    title: Confirm Magenda has never been released on the App Store (TestFlight only)
    why: p3-ipad-only drops the iPhone device family; App Store Connect refuses that for an app with an App Store release that supported iPhone
    done_when: App Store Connect's App Store tab for Magenda shows no version with status "Ready for Distribution" or "Removed from Sale", only TestFlight builds
manual_after:
  - id: ma1-apply-required-checks
    title: Apply the new required checks with scripts/update_branch_protection.py apply
    why: the PR's required checks change from 19 jobs to 7; until a maintainer applies them, GitHub waits for app (...) and old ui (...) checks that never run, and the PR cannot merge
  - id: ma2-ipad-testflight-smoke
    title: At the next release, install the TestFlight build on a real iPad and open the binder
    why: CI cannot check that an iPad-only build installs from TestFlight and still renders the binder on hardware
verify_after_merge:
  - python3 -m unittest discover -s scripts/tests
  - python3 scripts/ui_shards.py --check
  - swift test --package-path AppCore --filter LaunchOptionsTests
final_checks:
  - docs/fast-tests-plan.md and docs/fast-tests-plan-manual-steps.html are deleted and nothing links to them
  - ADRs 0041, 0042 and 0043 exist, are Accepted, and are in docs/adr/README.md's index; ADR 0020's Status has the line "Amended by 0041."
  - CHANGELOG.md has the [Unreleased] "### Removed" line for iPhone and no new version heading
  - grep -rn "userInterfaceIdiom" App AppUITests returns nothing
  - grep -n "iphone" .github/workflows/tests.yml returns nothing
  - the PR's last tests.yml run is green with four "ui (ipad, newest, N)" jobs, each under 18 minutes
phases:
  - id: p1-ci-shards
    title: Four timed iPad shards, hosted tests inside them, weekly older runtimes, cancel stale runs
    depends_on: []
    complexity: M
    touches:
      - .github/workflows/tests.yml
      - scripts/ui_shards.py
      - scripts/tests/test_ui_shards.py
      - scripts/simulator.py
      - scripts/tests/test_scripts.py
      - scripts/update_branch_protection.py
      - project.yml
      - docs/testing-policy.md
      - .claude/skills/steward/SKILL.md
    brief: |
      Read the plan's "Current state", D2, D3 and D6 first. This phase changes CI only.
      1. Create scripts/ui_shards.py exactly as D3 specifies, with CLASS_SECONDS holding D3's
         numbers. Model its docstring and CLI on scripts/simulator.py.
      2. Create scripts/tests/test_ui_shards.py with D3's seven tests. Load the module the way
         scripts/tests/test_scripts.py:39 loads simulator, and import update_branch_protection the
         same way.
      3. In scripts/simulator.py, change the --family default from "iphone" to "ipad", and update
         its docstring's usage lines so the first one reads "# newest iOS, an iPad -> id=<udid>".
         In scripts/tests/test_scripts.py, add a test that main() with no --family picks the iPad.
         Read how the existing simulator tests call choose() and main() and copy that. Leave the
         iphone tests as they are.
      4. Rewrite .github/workflows/tests.yml per D2. Keep the core, lint and scripts jobs
         unchanged. Add the schedule, the dispatch inputs and the top-level concurrency block.
         Delete the app job. Replace the ui job with D2's job and steps 1-9. Keep the file's
         header comment and update it to say the simulator jobs are four timed shards on the
         newest iPad (ADR 0042 will hold the reasoning; do not link it yet).
      5. In scripts/update_branch_protection.py, set REQUIRED_STATUS_CHECKS to D2's list of seven.
      6. In project.yml, under schemes.Magenda.test, set gatherCoverageData: false and delete the
         coverageTargets list. Add the comment line
         "# The coverage ratchet is AppCore's (ADR 0007); the app's coverage is not read."
      7. Update docs/testing-policy.md and .claude/skills/steward/SKILL.md per D6. Write the
         layer-3 text so it reads correctly before the ADRs exist: name no ADR number.
      8. Run python3 -m unittest discover -s scripts/tests and python3 scripts/ui_shards.py --check.
         Push, then dispatch tests.yml against this phase branch with simulators=true and
         runtimes=newest. Read the four ui (ipad, newest, N) jobs. The iPhone-only UI test skips
         on an iPad, so that is expected. Do not change any test to make a shard pass.
      Stop with status=blocked if: GitHub refuses the dispatch inputs (the workflow file on this
      ref is not the one used); `xcrun simctl bootstatus -b` fails or a shard's first test times
      out at launch; or the build fails with gatherCoverageData false. In each case, report the
      log lines.
    acceptance:
      - python3 -m unittest discover -s scripts/tests passes, including test_ui_shards
      - python3 scripts/ui_shards.py --check exits 0
      - python3 scripts/ui_shards.py --shard 1 prints a line that starts with "-only-testing:"
      - grep -c "iphone" .github/workflows/tests.yml prints 0
      - grep -n "cancel-in-progress" .github/workflows/tests.yml finds one line
      - the dispatched tests.yml run on this branch shows exactly ui (ipad, newest, 1) to ui (ipad, newest, 4) as macOS jobs, all green, and one of them ran MagendaTests (its log shows "Test Suite 'MagendaTests.xctest'" or the Swift Testing suite names)

  - id: p2-launch-options
    title: Fixture-only launch options to open Settings or Rules directly and turn animations off
    depends_on: []
    complexity: M
    touches:
      - AppCore/Sources/Controller/LaunchOptions.swift
      - AppCore/Tests/Controller/LaunchOptionsTests.swift
      - App/AppEnvironment.swift
      - App/MagendaApp.swift
      - App/Rendering/PageDrawer.swift
      - App/Screens/AgendaView.swift
      - App/Screens/SettingsView.swift
      - App/Screens/RulesView.swift
    brief: |
      Read the plan's D4 first. It gives every name, signature and line of wiring.
      1. Create AppCore/Sources/Controller/LaunchOptions.swift as specified in D4, with a ///
         comment on every public declaration. Copy the argument-reading style of GoogleFixture's
         init?(launchArguments:) in AppCore/Sources/Controller/GoogleFixtures.swift.
      2. Create AppCore/Tests/Controller/LaunchOptionsTests.swift with D4's cases, using Swift
         Testing in the same style as AppCore/Tests/Controller/GoogleFixturesTests.swift. Use
         @Test(arguments:) where the cases share one invariant. Open the file with the one-line
         header comment the guidelines require.
      3. AppCore's overall coverage floor is 100% (scripts/check_coverage_floor.py), so the
         tests in step 2 must reach every line of LaunchOptions.swift. Add no per-file floor.
      4. Wire the app exactly as D4's "App wiring" says: AppServices.launch, the @Entry in
         App/Rendering/PageDrawer.swift, MagendaApp (import UIKit, setAnimationsEnabled, the
         environment and the transaction), AgendaView (onAppear, the sheet's onDismiss and
         opensRules), SettingsView (Route, path, init, NavigationLink(value:),
         navigationDestination, ID.form) and RulesView (ID.form).
      5. SettingsView's existing #Preview must keep compiling through the new init's default
         argument; add no new #Preview.
      6. Run swift test --package-path AppCore --filter LaunchOptionsTests, then
         swift format lint --strict over the paths in docs/coding-and-testing-guidelines.md (or
         read tests.yml's core and lint jobs if this container has no toolchain). Push and
         dispatch tests.yml against this branch. No UI test passes the new arguments yet, so every
         existing UI test must still pass. That proves the default path is unchanged.
      Stop with status=blocked if: SettingsView's NavigationStack(path:) makes an existing
      RulesUITests or SettingsUITests test fail (the link's accessibility type may have changed;
      report the failing query); or UIView.setAnimationsEnabled cannot be called from
      MagendaApp.init under Swift 6 isolation without unsafe annotations.
    acceptance:
      - swift test --package-path AppCore --filter LaunchOptionsTests passes (or the dispatched core job is green)
      - the dispatched lint job is green
      - grep -n "MagendaNoAnimations" AppCore/Sources/Controller/LaunchOptions.swift finds it
      - grep -n "setAnimationsEnabled(false)" App/MagendaApp.swift finds it
      - 'grep -n "navigationDestination(for: Route.self)" App/Screens/SettingsView.swift finds it'
      - the dispatched tests.yml run on this branch is green

  - id: p3-ipad-only
    title: Make the app iPad-only and remove the iPhone PDF preview
    depends_on: [p1-ci-shards, p2-launch-options]
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
         INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone line, and add the comment
         "# iPad-only (ADR 0041)." on the line above TARGETED_DEVICE_FAMILY.
      2. In App/Screens/AgendaView.swift, reduce `detail` to its iPad branch, and remove the
         idiom check from the Start Over toolbar item (keep `controller.binder != nil`). Run
         grep -rn "pdfPreview" App. If AgendaView.ID.pdfPreview is the only hit, delete it.
      3. git rm App/Screens/PreviewView.swift App/Screens/PDFKitView.swift. Then run
         grep -rn "PreviewView\|PDFKitView\|import PDFKit" App and remove anything left that
         only served them.
      4. In README.md, rewrite the sentences that describe the iPhone (around lines 5 and 68) so
         they describe an iPad app only. In docs/release-testing.md, line 43 and anything else
         naming an iPhone, test on a real iPad only.
      5. CHANGELOG.md: add D1's "### Removed" line under [Unreleased].
      6. Push and dispatch tests.yml against this branch. The UI tests still carry iPhone
         branches; on an iPad they take the iPad path, so they must pass unchanged.
      Stop with status=blocked if: grep -rn "userInterfaceIdiom" App finds a use outside
      AgendaView (the plan missed one); or the build fails because something else imports
      PreviewView or PDFKitView.
    acceptance:
      - grep -rn "userInterfaceIdiom" App prints nothing
      - test ! -e App/Screens/PreviewView.swift && test ! -e App/Screens/PDFKitView.swift
      - 'grep -n ''TARGETED_DEVICE_FAMILY: "2"'' project.yml finds it'
      - grep -n "no longer runs on iPhone" CHANGELOG.md finds it
      - the dispatched tests.yml run on this branch is green

  - id: p4-ui-settings-rules
    title: Shared UI test helpers; Settings and Rules tests launch into their screen
    depends_on: [p2-launch-options]
    complexity: M
    touches:
      - AppUITests/MagendaUI.swift
      - AppUITests/RulesUITests.swift
      - AppUITests/SettingsUITests.swift
    brief: |
      Read the plan's "Where the UI test time goes" and D5 first. This is the biggest saving:
      Rules and Settings were 61% of all UI test time.
      1. Create AppUITests/MagendaUI.swift with D5's helpers. Open it with a header comment in
         the style of the other UI test files, saying the file holds the steps every UI test
         class shares. Implement reveal(in:top:bottom:) exactly as D5 describes. Use
         XCTFail(..., file:, line:) when the element never fits.
      2. Migrate AppUITests/RulesUITests.swift by D5's migration rules 1-5, and launch every test
         with ["-MagendaOpen", "rules"]. openRules goes away: the first wait is
         app.element("rulesRow.personalBlocks.0").waitForExistence(timeout: 30). closeSettings
         stays, because tests that check the agenda afterwards need it. The reveal container is
         app.element("rulesForm").
      3. Migrate AppUITests/SettingsUITests.swift the same way. Launch with
         ["-MagendaOpen", "settings"] per D5's "Launching into a screen" rule, keep
         testTheRulesLinkAndTheVersionAreThere tapping through openSettings, and use
         app.element("settingsForm") as the reveal container. Keep each test's assertions and
         messages; change only how it gets there and how it waits.
      4. Do not delete, skip or weaken a test. Keep every test name, so CLASS_SECONDS and the
         history stay comparable.
      5. Run the lint (or read the dispatched lint job). Push and dispatch tests.yml against this
         branch. The shard holding RulesUITests and the one holding SettingsUITests must be
         green. Write each class's "Executed N tests ... in X seconds" figure into your report.
      Stop with status=blocked if: MagendaUI.swift fails to compile on wait(for:toEqual:timeout:);
      or a test fails because -MagendaOpen did not open the screen (the app side from p2 is wrong;
      report which screen). A typed query that fails is not a stop: put that identifier back to
      .any per D5 rule 2.
    acceptance:
      - test -f AppUITests/MagendaUI.swift
      - 'grep -c "descendants(matching: .any)" AppUITests/RulesUITests.swift AppUITests/SettingsUITests.swift prints 0 for both'
      - grep -n "MagendaOpen" AppUITests/RulesUITests.swift finds it
      - grep -c "func test" AppUITests/RulesUITests.swift prints 12, and AppUITests/SettingsUITests.swift prints 14
      - the dispatched tests.yml run on this branch is green
      - the report gives RulesUITests and SettingsUITests at under half their CLASS_SECONDS values (1980 and 1260)

  - id: p5-ui-rest
    title: Move the other UI test classes to the shared helpers and drop the iPhone test paths
    depends_on: [p3-ipad-only, p4-ui-settings-rules]
    complexity: M
    touches:
      - AppUITests/AgendaEditUITests.swift
      - AppUITests/AgendaScreenUITests.swift
      - AppUITests/BinderUITests.swift
      - AppUITests/HandoffUITests.swift
      - AppUITests/LongTextUITests.swift
      - AppUITests/PreviewUITests.swift
      - AppUITests/SetupUITests.swift
      - AppUITests/SignInUITests.swift
      - AppUITests/StartOverUITests.swift
    brief: |
      Read D5 first. MagendaUI.swift already exists from p4; do not change it here. If a helper
      it lacks would serve three or more files, stop with status=blocked and name the helper
      instead of adding it.
      1. In each file listed in touches, apply D5's migration rules 1-4. Use rule 5 where the file
         has its own scroll helper over a form; the agenda list's own scrollers (scrollToHittable,
         scrollToExist, scrollIntoView) stay, with their inner waitForExistence probes turned into
         .exists reads per rule 3.
      2. Apply D5's "iPad-only cleanup": previewID becomes "binderView" and shareID becomes
         "binderShareButton"; delete every XCTSkipUnless on the idiom; delete
         PreviewUITests.testRenderingAgainAfterGoingBackShowsThePreviewAgainOnIPhone; drop
         `throws` where nothing else throws; drop import UIKit where nothing needs it.
      3. AgendaScreenUITests has an `if UIDevice.current.userInterfaceIdiom == .pad` block near
         line 146. Keep the iPad branch's body and delete the else branch.
      4. Do not delete, skip or weaken any other test, and keep every other test name.
      5. Run the lint (or read the dispatched lint job). Push and dispatch tests.yml against this
         branch. All four shards must be green. Write each class's "Executed N tests ... in X
         seconds" figure into your report.
      Stop with status=blocked if: a binder or hand-off test fails only with animations off and
      the failure is in what the app shows, not in how the test waits (see the plan's Risks).
    acceptance:
      - grep -rn "userInterfaceIdiom\|XCTSkipUnless" AppUITests prints nothing
      - grep -rn "testRenderingAgainAfterGoingBackShowsThePreviewAgainOnIPhone" AppUITests prints nothing
      - grep -rln "private func launch" AppUITests prints nothing
      - the dispatched tests.yml run on this branch is green

  - id: p6-measure
    title: Record measured class timings so the four shards balance
    depends_on: [p5-ui-rest]
    complexity: S
    touches:
      - scripts/ui_shards.py
      - scripts/tests/test_ui_shards.py
    brief: |
      1. Dispatch tests.yml against this phase branch (simulators=true, runtimes=newest) and wait
         for it to finish green. If it is red, stop with status=blocked and report the failure.
         Do not fix tests in this phase.
      2. From each ui (ipad, newest, N) job's log (mcp__github__get_job_logs), take every
         "Test Suite '<Class>' passed ... Executed N tests ... in X seconds" line for the UI
         classes. For MagendaTests, take the hosted tests' total from their suite lines, plus 20 s
         for the app's install and launch.
      3. Set each CLASS_SECONDS value to its measured seconds, rounded up to the next multiple of
         10. Update the comment above CLASS_SECONDS to name the run ID it was measured from.
      4. Run python3 scripts/ui_shards.py --table and paste its output into your report. If test
         3 in test_ui_shards.py depends on CLASS_SECONDS (it should not), fix the test to use its
         own fixture.
      5. Push, dispatch tests.yml again, and record each ui job's duration (started_at to
         completed_at, from mcp__github__actions_list list_workflow_jobs), and the run's wall time
         from the first job's start to the last job's completion.
      Stop with status=blocked if: after the rebalance any ui job takes longer than 18 minutes.
      Report the --table output and the per-class figures, and do not add a fifth shard (the
      plan's Risks).
    acceptance:
      - python3 scripts/ui_shards.py --check exits 0
      - the comment above CLASS_SECONDS names a tests.yml run ID
      - the second dispatched run is green, and every ui (ipad, newest, N) job's duration is 18 minutes or less, as listed in the report

  - id: p7-retire
    title: ADRs 0041 to 0043, standing docs, and retire the plan
    depends_on: [p6-measure]
    complexity: S
    touches:
      - docs/adr/0041-magenda-is-an-ipad-app.md
      - docs/adr/0042-pull-requests-test-the-newest-ipad-in-four-timed-shards.md
      - docs/adr/0043-ui-tests-start-in-the-screen-they-test-with-animations-off.md
      - docs/adr/0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md
      - docs/adr/README.md
      - docs/testing-policy.md
      - .github/workflows/tests.yml
      - docs/fast-tests-plan.md
      - docs/fast-tests-plan-manual-steps.html
    brief: |
      1. Check the next free ADR number on this branch (ls docs/adr). If 0041 is taken, number
         these from the next free one and use those numbers in every step below.
      2. Write the three ADRs listed in the plan's "ADRs" section from the template in
         docs/adr/README.md, Status "Accepted — <today>". Take Context, Decision and the rejected
         alternatives from D1, D2+D3 and D4+D5, and put the measured numbers from "Current state"
         and p6's report into Context and Consequences. Link to source files and ADRs only, never
         to this plan.
      3. In ADR 0020's Status section, add the line "Amended by 0041." Change nothing else in it.
      4. Add the three ADRs to the index in docs/adr/README.md.
      5. In docs/testing-policy.md, cite ADR 0042 where layer 3 and the shards are described and
         ADR 0043 next to the launch-argument mention. In tests.yml's header comment, cite
         ADR 0042.
      6. git rm docs/fast-tests-plan.md docs/fast-tests-plan-manual-steps.html, then run
         grep -rn "fast-tests-plan" . and fix anything that still links to them.
      7. Run python3 -m unittest discover -s scripts/tests (it includes the no-project-history
         guard).
    acceptance:
      - ls docs/adr/0041-*.md docs/adr/0042-*.md docs/adr/0043-*.md lists three files (or the renumbered ones)
      - grep -n "Amended by 0041" docs/adr/0020-*.md finds it
      - grep -rn "fast-tests-plan" . prints nothing
      - python3 -m unittest discover -s scripts/tests passes
```
