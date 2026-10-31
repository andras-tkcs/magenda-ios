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
- App Review and the App Store listing;
- real Google sign-in and real account data, which CI has no account for (ADR 0013): sign in with
  your own client, render a day and share it (on iPad, from the binder), and finish a day to Drive
  and the end-of-day routine (ADR 0027, ADR 0028);
- the system contact picker behind Choose from Contacts, which runs out of process and is replaced
  by a fixture in the UI tests (ADR 0037);
- handwriting with a real Apple Pencil on an iPad (pressure, palm rejection), which the simulator
  does not have;
- the comparison of the app's agenda with a binder built by the old Claude workflow while that
  workflow still runs.

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

With the release candidate installed from TestFlight on a real iPad:

- [ ] The app launches, shows the version and build number TestFlight lists, and every screen
      changed in this release works.
- [ ] Light and dark appearance, and the largest accessibility text size, leave nothing clipped or
      overlapping on the changed screens.
- [ ] VoiceOver reads every changed control with a label that says what it does.
- [ ] Any new permission prompt reads well, and declining it leaves the app usable.
- [ ] App Store Connect's privacy answers still match what the app collects.
- [ ] On an iPad with an Apple Pencil, write on a binder page, relaunch, and the handwriting is
      still there.
- [ ] On an iPad with an Apple Pencil, draw on a page, go to Notes, and Undo goes back to
      that page and removes the stroke.
- [ ] On an iPad with an Apple Pencil, swipe between binder pages with a finger while the Pencil
      writes, and no stroke turns into a swipe or a swipe into a stroke.
- [ ] With a real Google account and a real routine, on an iPad: sign in again if asked, enter the
      routine's fire URL and token in Settings, write on a day, tap Finish Day, and the PDF and the
      notes Doc appear in the Drive folder `Magenda`, or in the folder you pick under Settings →
      Google Drive → Folder (open folders, pick one, or make a new one; ADR 0051). In Review, wait for "Notes ready for review",
      open the Doc, tap Approve notes, then Approve summaries when a summary routine was ticked for a
      meeting (check that the Doc holds a `Summary ready:` marker section first), and the row ends
      as "Closed. Handwriting is deleted on …" (ADR 0027 to ADR 0030, ADR 0038 to ADR 0040).
- [ ] With a real routine updated to schema 2, on an iPad: tap Send Meeting on a meeting page and
      confirm. The page shows "Sent to Claude" and can't be written on, Start Over is disabled, and
      Review has a row for the meeting that reaches "Closed". Then tap Finish Day, and the day's notes
      cover the other pages but not that meeting (ADR 0033, ADR 0034).
- [ ] On an iPad, turn on airplane mode, tap Finish Day, and Review shows "Waiting to upload".
      Turn it off and reopen the app: the day uploads and is sent to Claude once.
- [ ] On an iPad with an Apple Pencil, double-tap (and, on a Pencil Pro, squeeze) the Pencil: a pen
      switches to the eraser and the eraser back to the pen used last.
