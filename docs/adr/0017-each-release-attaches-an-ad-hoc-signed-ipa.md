# ADR 0017: A tagged release can attach an Ad Hoc signed .ipa

## Status

Accepted — 2026-10-15. Implemented in `build.yml`'s `testflight` job; it runs when the repository variable
`ADHOC_IPA` is true.

## Context

TestFlight is the only other way to install a build, and it needs an App Store Connect upload, a
processing wait and an invitation. A signed build attached to the GitHub Release can be installed
directly on the maintainer's registered iPad. Ad Hoc is the only way Apple allows a signed iOS
build to be installed outside the App Store and TestFlight: it installs only on devices registered
under Certificates, Identifiers & Profiles → Devices.

## Decision

1. `build.yml`'s `testflight` job exports an Ad Hoc `Magenda-<tag>.ipa`, and its SHA-256 in
   `Magenda-<tag>.ipa.sha256`, from the same signed archive it uploads, with ADR 0009's App Store
   Connect key and no new secret. The step runs before the upload, so a failed export (for example
   no registered device) stops the release before anything reaches App Store Connect.
2. The job keeps the files as a workflow artifact and the `github-release` job attaches them to the
   GitHub Release.
3. The built app never goes into the git tree: `.gitignore` lists `*.ipa` and `*.xcarchive`.
4. The export is optional and runs when `ADHOC_IPA` is `true`.

## Alternatives considered

- **A separate `adhoc` job.** A second signed archive on a second macOS runner and the key
  written twice, for the same bits.
- **A development-signed build.** Needs a development certificate per machine, and its profiles
  expire after a week.
- **An over-the-air `itms-services` install page.** Needs a `manifest.plist` served over HTTPS next
  to the `.ipa`; GitHub release asset redirects are not a supported host.
- **Committing builds to git.** A binary per release in the history, stale the moment it lands.

## Consequences

- The release attaches an .ipa that installs only on registered devices.
- The first export needs a registered device; until then a tag with the export on fails before
  upload.
- `workflow_dispatch` runs never reach the signed job, so only a tag proves the export.

## Verification

`.github/workflows/build.yml` ("Export the Ad Hoc .ipa", "Keep the .ipa for the release", the
`github-release` job); `.gitignore`; `docs/releasing.md`, "Installing the Ad Hoc build".

## Related

ADR 0006; ADR 0009.
