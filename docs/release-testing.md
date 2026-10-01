# Release testing

Everything a human checks before a release: the gates in the order they run, then the manual
checks. What CI proves automatically is in [`testing-policy.md`](testing-policy.md); how a tag is
cut is in [`releasing.md`](releasing.md) and `/cut-release`.

## What stays manual

A check stays manual only when automation cannot reliably decide pass or fail:

- how the app looks and feels on a real device, in light and dark appearance and at a large
  Dynamic Type size — run when a screen changed;
- hardware the simulator does not have or fakes (camera, push notifications, biometrics, real
  network conditions);
- a first-run permission prompt's wording, which iOS renders;
- App Review and the App Store listing.

Nothing is added to this list unless it meets that bar. Do not rerun the automated suite by hand
because a release is being cut.

## Gates, in order

1. **CI green on the commit to tag**, with every required check passing.
2. **`python3 scripts/pre_release_check.py`** on a Mac from the repo root: CI's blocking commands,
   PASS/FAIL each, with no SKIP rows.
3. **`build.yml` pre-flight.** Dispatch it (no inputs) against the exact commit to tag; `archive`
   succeeds. It uploads nothing.
4. **`release.yml` dry run** with `version` and `dry_run: true`. Read the rendered notes.
5. **Cut a release candidate** (`X.Y.Z-rc.N`) and run the human checks below against its
   TestFlight build.
6. **Cut the stable tag** on a new commit (the PR that prepares `CHANGELOG.md`), then submit it for
   review in App Store Connect.

## Human checks

With the release candidate installed from TestFlight on a real iPhone (and an iPad if the app
supports it):

- [ ] The app launches, shows the version and build number TestFlight lists, and every screen
      changed in this release works.
- [ ] Light and dark appearance, and the largest accessibility text size, leave nothing clipped or
      overlapping on the changed screens.
- [ ] VoiceOver reads every changed control with a label that says what it does.
- [ ] Any new permission prompt reads well, and declining it leaves the app usable.
- [ ] App Store Connect's privacy answers still match what the app collects.
