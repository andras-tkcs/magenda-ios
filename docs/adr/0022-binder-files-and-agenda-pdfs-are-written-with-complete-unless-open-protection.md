# ADR 0022: Binder files and agenda PDFs are written with complete-unless-open file protection

## Status

Accepted — 2026-10-23. Implemented.
Amends [ADR 0021](0021-a-binder-day-is-stored-as-a-content-snapshot-and-ink-per-page-key.md).

## Context

The binder's day files and PencilKit ink, and the exported PDFs that carry the same handwriting,
were written with the default class (*complete until first user authentication*), so they were
readable while the device was locked after its first unlock.

## Decision

1. The app chooses the protection class; AppCore does not name one. `FileBinderStore` takes
   `protection: Data.WritingOptions` and writes every file (`day.json`, `index.json`,
   `page-<n>.pkdata`) atomically with those options added (ADR 0007: file-protection constants are
   Apple-only).
2. `App/Platform/FileProtection.swift` holds the class, *complete unless open*: unreadable while
   the device is locked, except for a file already open, so a save that starts as the iPad locks
   still finishes. `App/AppEnvironment.swift` passes its writing option to both file stores, the
   live one and the fixture one.
3. `PDFAgendaRenderer.write` creates the `Agendas` folder with the class, sets it on the folder
   again (so a folder that already exists gets it too), and sets it on each PDF after writing it.
   The iPhone preview PDF and the binder export both go through it.

## Alternatives considered

- **`.completeFileProtection`** — a save still running as the iPad locks would fail and show
  "Couldn't save your handwriting".
- **Keeping the default, *until first user authentication*** — the files stay readable whenever
  the device is locked after its first unlock.
- **Encrypting the files with a Keychain key** — the operating system's class gives the same
  protection without key management.
- **The Data Protection entitlement (an app-wide default class)** — it is a provisioning-profile
  capability, so it changes signing ([ADR 0009](0009-signing-and-upload-use-an-app-store-connect-api-key.md),
  [ADR 0018](0018-the-team-id-comes-from-the-app-store-environment.md)) and needs App ID changes by
  hand, and it would also cover files that don't need it.

## Consequences

- Nothing can read these files in the background while the device is locked, which the app does
  not do today.
- AppCore stays protection-agnostic, and Linux ignores the option.
- Application Support is still in device backups (ADR 0021).
- Binder files written before this change keep their old class until they are written again; the
  PDF folder and each new PDF get the class at once.
- The simulator does not enforce data protection, so the hosted test proves only that a protected
  write succeeds.

## Verification

`App/Platform/FileProtection.swift`, `App/AppEnvironment.swift`,
`App/Rendering/PDFAgendaRenderer.swift`, `AppCore/Sources/Binder/BinderStore.swift`,
`AppTests/PlatformTests.swift`.

## Related

https://github.com/andras-tkcs/magenda-ios/pull/7, ADR 0007, ADR 0020, ADR 0021.
