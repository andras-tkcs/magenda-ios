# Changelog

<!--
HOW TO USE THIS FILE

1. `## [Unreleased]` is permanent. A feature branch adds its user-visible change under that
   heading and nothing else. Do NOT open a concrete `## [X.Y.Z]` heading on a feature branch: two
   branches in flight would both claim the same next version. Only the PR that prepares a release
   turns `## [Unreleased]` into `## [X.Y.Z] — YYYY-MM-DD`, adds a fresh empty `## [Unreleased]`
   above it, and updates the link definitions at the bottom. If a section for that version already
   exists, MERGE `[Unreleased]`'s entries into it and fix its date; renaming would create a second
   heading, and scripts/changelog_section.py refuses to render a version that has two.

2. This file is NEVER a version source. The git tag is the only one (docs/releasing.md).
   scripts/changelog_section.py reads a version's section *out* of this file to produce the GitHub
   Release body for that tag.

3. Pre-release tags (-alpha.N/-beta.N/-rc.N) get no section of their own; their content folds
   into the version they lead to, per Keep a Changelog.

4. A version that was tagged but never shipped to the App Store gets no section either. Fold its
   entries into the version that does ship and say so at the top of that section.

5. Write entries for the people who use the app: what they can now do, or what behaves
   differently, in plain words. Internal refactors and test-only changes need no entry.
-->

All notable changes to Magenda are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] — 2026-10-15

First stable release. It also carries everything from the 0.1.0 alpha, which was never shipped.

### Fixed

- The links in the PDF now work: "overview", "notes" and each schedule entry jump to their page.
  They were tappable in the wrong place before.

### Added

- An app icon.
- Sign in with Google and build your daily binder from Google Calendar and your "Claude" and
  "Claude Delegations" task lists, with fixed rules and no AI.
- Every item that is left out shows why ("Declined", "Personal block", "No other attendees",
  "Overdue", "Check-in due" and more).
- Editable binder rules: personal blocks, title prefixes, out-of-office words, short meeting names,
  people for "to be discussed" tasks, and the number of look-ahead days.
- Untick or edit any item before rendering; nothing is changed in Google.
- Enter your own Google client on first launch; it is kept in the Keychain and never leaves the
  device except to talk to Google.
- Preview the PDF beside the list on iPad, and share it to Noteshelf or anywhere else.
- Keyboard shortcuts for rendering, changing the day and reloading.
- Choose the font and the colors of the agenda.
- Long titles are shortened with "…" and to-dos that don't fit are listed under the preview.
- A GitHub Release can attach a signed .ipa for registered devices, when the maintainer turns it on.

[Unreleased]: https://github.com/andras-tkcs/magenda-ios/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/andras-tkcs/magenda-ios/releases/tag/v0.1.1
