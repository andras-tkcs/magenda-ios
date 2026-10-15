# ADR 0018: The Team ID comes from the app-store environment

## Status

Accepted — 2026-10-15. Implemented in `build.yml`'s `testflight` job.
Amends [0009](0009-signing-and-upload-use-an-app-store-connect-api-key.md).

## Context

Signing needs the developer account's Team ID. The repository is public, and a Team ID committed to
it would tie the public source to one developer account. ADR 0009 already keeps the App Store
Connect API key in the `app-store` environment, which only the signed job reads.

## Decision

1. The Team ID is the secret `APPLE_TEAM_ID` of the `app-store` environment.
2. The `testflight` job passes it to the signed archive as `DEVELOPMENT_TEAM` and to both exports
   (the App Store Connect upload and the Ad Hoc export) as `teamID`.
3. The job fails before archiving if `APPLE_TEAM_ID` is empty.
4. `project.yml` carries no Team ID.

## Alternatives considered

- **Committing the Team ID to `project.yml`.** Rejected: it publishes the account's identifier in
  a public repository for no gain, since the signed job already has a protected place to read it.

## Consequences

- The environment holds four secrets instead of three.
- A local signed build has to pass `DEVELOPMENT_TEAM` on the command line or set it in Xcode.
- The unsigned `archive` job and local development need no Team ID.

## Verification

`.github/workflows/build.yml` (`testflight` job: `APPLE_TEAM_ID`, "Write the App Store Connect API
key", the archive and export steps); `docs/releasing.md`, "Signing and App Store Connect".

## Related

ADR 0009.
