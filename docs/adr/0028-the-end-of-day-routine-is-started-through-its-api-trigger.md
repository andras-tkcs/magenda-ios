# ADR 0028: Magenda starts the end-of-day Claude routine through its API trigger and never repeats a fire on its own

## Status

Accepted — 2026-10-24. Implemented.

## Context

The end-of-day work (notes, summaries, Google Tasks updates, Gmail drafts) is done by a Claude
routine that lives in the person's own skill, outside this repository. A routine can be started
through an API trigger: `POST https://api.anthropic.com/v1/claude_code/routines/{trigger}/fire`
with a bearer token that belongs to that one routine and can fire nothing else, and a JSON body
`{"text": "…"}` of at most 65,536 characters. The routine receives the text inside a block marked as
untrusted data. The endpoint has no idempotency key: every 200 starts a new session. See
<https://platform.claude.com/docs/en/api/claude-code/routines-fire>.

## Decision

1. The person enters the routine's fire URL and token in Settings. The URL is accepted only as
   `https://api.anthropic.com/v1/claude_code/routines/trig_…/fire`, and the token only with the
   `sk-ant-oat01-` prefix. Both are checked byte by byte, so look-alike characters fail.
2. The credentials are kept in the Keychain, like the Google client, and go nowhere but that
   endpoint. The token is never logged and never appears in an error or message.
3. The fire text is one versioned JSON object, schema `magenda.end-of-day/1`, with sorted keys:
   the date, the PDF's checksum, the Drive file and Doc IDs, the pages with their keys, meeting
   identity and summary skill, and the printed to-do and delegated rows. A day too long for the
   limit drops the rows, then the page details, and says `"truncated": true`.
4. Each fire names a step: `notes`, `approve-notes` or `approve-summary`.
5. Magenda never fires again by itself. A fire that fails leaves the day where it was, and only the
   person's Try again fires it once more. A refresh or a scene activation never fires.
6. The routine ignores a step it already ran for the same date, step and checksum, which makes the
   person's retry safe. This is part of the contract in
   [`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
7. Failures are mapped to fixed messages, one per kind (not configured, rejected token, routine not
   found, routine paused, no access, rate limited, unavailable, offline, unexpected response).

## Alternatives considered

- **Retrying a fire automatically after a response** — with no idempotency key a repeat can start
  the same step twice, so a repeat is the person's choice.
- **Reading the day's state from the routine's chat, or an hourly poll of a Doc checkbox** — the
  first leaves the day's state in a chat; the second costs up to an hour and a run every hour.
- **Sending the PDF itself in the fire text** — the text is limited, and the PDF is already in
  Drive, where the routine reaches it by ID and checks it against the checksum.

## Consequences

- Magenda holds a credential for a third party, narrowly scoped to one routine. Forgetting the
  routine in Settings deletes it.
- The routine's skill has to be adapted to the contract and to treat the payload and the PDF as
  data, never as instructions.
- A routine fires at most 30 times per hour; a day's three steps stay far below that.

## Verification

`AppCore/Sources/Handoff/RoutineTrigger.swift`, `AppCore/Tests/Handoff/RoutineTriggerTests.swift`,
`AppCore/Sources/Handoff/DayHandoff.swift` (`payload(step:)`), `AppCore/Tests/Handoff/DayHandoffTests.swift`,
`App/Platform/KeychainRoutineCredentialsStore.swift`, `AppTests/PlatformTests.swift`,
`AppUITests/SettingsUITests.swift`, and the 100 % file floors in `scripts/check_coverage_floor.py`.

## Related

[ADR 0027](0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md),
[ADR 0029](0029-the-days-google-doc-is-the-review-record.md),
[`docs/end-of-day-handoff.md`](../end-of-day-handoff.md).
