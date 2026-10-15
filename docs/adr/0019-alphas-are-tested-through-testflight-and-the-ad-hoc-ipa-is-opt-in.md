# ADR 0019: Alphas are tested through TestFlight, and the Ad Hoc .ipa is opt-in

## Status

Accepted — 2026-10-15. Implemented in `build.yml`'s `testflight` job and `docs/releasing.md`.
Amends [0017](0017-each-release-attaches-an-ad-hoc-signed-ipa.md).

## Context

Testing an alpha on the maintainer's iPad needs an installable build. The Ad Hoc `.ipa` installs
only on registered devices and is installed from a Mac (Finder or Apple Configurator). A release
with the export mandatory fails whenever no device is registered. TestFlight installs from the
iPad itself.

## Decision

1. An alpha is tested by installing it from TestFlight: an internal group with automatic
   distribution receives each uploaded build. No Mac is needed.
2. The Ad Hoc `.ipa` is exported and attached to the GitHub Release only when the repository
   variable `ADHOC_IPA` is `true`. It is a repository variable, not a variable of the `app-store`
   environment.

## Alternatives considered

- **Keeping the Ad Hoc export mandatory.** Rejected: it blocks every release made without a
  registered device, and installing its output needs a Mac.

## Consequences

- A release works with no registered device and no variable set.
- The Ad Hoc path stays available for a registered device when the variable is turned on.
- An internal TestFlight group is set up once in App Store Connect.

## Verification

`.github/workflows/build.yml` ("Export the Ad Hoc .ipa" and "Keep the .ipa for the release" steps,
both `if: vars.ADHOC_IPA == 'true'`); `docs/releasing.md`, "Installing the Ad Hoc build" and
"Testing an alpha on an iPad".

## Related

ADR 0009; ADR 0017.
