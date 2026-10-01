# ADR 0009: Signing and upload use Xcode's automatic signing with an App Store Connect API key held in a protected environment

## Status

Accepted — 2026-10-01. Inherited from the iOS app template.

## Context

Uploading to App Store Connect needs a distribution certificate, a provisioning profile and an
account credential. The common ways of getting those into CI each hold something long-lived and
powerful: an exported `.p12` with its password and a profile as repository secrets, an Apple ID
with an app-specific password, or a separate encrypted git repository of certificates with its own
passphrase. Each is readable by any workflow step that can read the secret, and each has to be
renewed by hand when a certificate or profile expires.

## Decision

1. `build.yml`'s `testflight` job archives with `-allowProvisioningUpdates` and the
   `-authenticationKey*` options, so Xcode creates or fetches the certificate and profile through
   cloud-managed signing, and exports with `destination: upload`, so `xcodebuild` uploads the
   build itself.
2. The only credential is an App Store Connect API key (`ASC_KEY_P8`, `ASC_KEY_ID`,
   `ASC_ISSUER_ID`), stored as secrets of the `app-store` GitHub Environment, which only that job
   uses and only on a tag ref. It is written to a file with mode 600 for the job and deleted at the
   end.
3. No certificate, profile, `.p8`, `.p12` or password is ever committed; `.gitignore` names them.

## Alternatives considered

- **Certificates and profiles as repository secrets, installed into a temporary keychain.**
  Rejected: more secrets, readable by more workflows, and an expiry to renew by hand.
- **fastlane `match`.** Rejected: a Ruby toolchain and a second repository to protect, for what
  Xcode now does with one key.
- **Xcode Cloud.** A good fit for some teams, but it moves CI out of GitHub Actions, where this
  repository's other gates and its Claude Code workflow live.

## Consequences

- The key needs a role that may create distribution certificates and profiles (App Manager or
  Admin, depending on the account's settings), which is broader than upload alone.
- A required reviewer on the `app-store` environment makes every upload a go/no-go.
- Signing problems surface only on a tag; a release-candidate tag finds them first (ADR 0006).

## Verification

`.github/workflows/build.yml`'s `testflight` job (`environment`, `if`, the key file's lifetime);
`.gitignore`; `docs/releasing.md`, "Signing and App Store Connect".
