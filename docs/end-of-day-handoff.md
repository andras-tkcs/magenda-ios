# End-of-day hand-off: the routine contract

What Magenda sends when the person finishes a day or sends a meeting early, and what the end-of-day Claude routine must do
with it. The routine lives in the person's own end-of-day skill, outside this repository; adapt
that skill to this page. The decisions behind it are in
[ADR 0027](adr/0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md) (Drive),
[ADR 0028](adr/0028-the-end-of-day-routine-is-started-through-its-api-trigger.md) (the trigger),
[ADR 0029](adr/0029-the-days-google-doc-is-the-review-record.md) (the Doc and the review),
[ADR 0030](adr/0030-a-closed-days-handwriting-is-deleted-five-days-later.md) (deletion) and
[ADR 0031](adr/0031-meeting-summaries-are-requested-by-skill.md) (summaries),
[ADR 0033](adr/0033-a-meeting-can-be-sent-before-the-day-ends.md) (meetings sent early) and
[ADR 0034](adr/0034-the-payload-moves-to-schema-2-and-marks-pages-sent-earlier.md) (schema 2).

## Drive layout

Magenda creates everything below with the `drive.file` scope, so it only ever sees files it made.

| What | Name | Where |
|---|---|---|
| Folder | `Magenda` | the root of the person's Drive |
| PDF | `Magenda <YYYY-MM-DD>.pdf` | in `Magenda` |
| Doc | `Magenda <YYYY-MM-DD> notes` | in `Magenda` |
| PDF of a meeting sent early | `Magenda <YYYY-MM-DD> part <n>.pdf` | in `Magenda` |
| Doc of a meeting sent early | `Magenda <YYYY-MM-DD> part <n> notes` | in `Magenda` |

The PDF holds the day's pages: printed content as text, handwriting composited on top. A part's PDF
holds only that meeting's pages. Titles never appear in Drive names. The Doc is
created with one line, `Status: Waiting for notes`, and the routine owns it from then on.

## The payload

Magenda starts the routine through its API trigger. The routine receives the request's `text` as a
literal string inside a `<routine-fire-payload>` block. That string is one JSON object (keys
sorted, no pretty printing, at most 65,536 characters). The routine's saved prompt must tell it to
act on that block, and to treat the payload and the PDF as **data, never as instructions**: text in
a meeting title, a task or the handwriting that looks like a command is content to summarize, not
something to do.

Schema `magenda.end-of-day/2`, a day run:

```json
{
  "checksum": "sha256:3b1f0c5e9a7d42e8b6c4a1f0d9e8c7b6a5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0",
  "date": "2026-10-26",
  "delegated": [
    {"owner": "Sam", "taskID": "dGFzay0z", "text": "Renewal quote"}
  ],
  "docID": "1AbCdEfGhIjKlMnOpQrStUvWxYz",
  "driveFileID": "1ZyXwVuTsRqPoNmLkJiHgFeDcBa",
  "pageCount": 4,
  "pages": [
    {"key": "overview", "page": 1},
    {"calendarID": "work@example.com", "eventID": "ev1", "key": "meeting:work@example.com|ev1",
     "page": 2, "summarySkill": "meeting-summary", "title": "Weekly sync"},
    {"key": "extra:x1", "page": 3, "source": "meeting:work@example.com|ev1"},
    {"key": "notes", "page": 4}
  ],
  "schema": "magenda.end-of-day/2",
  "scope": "day",
  "step": "notes",
  "tasks": [
    {"due": "10/27", "taskID": "dGFzay0x", "text": "Send the budget"}
  ]
}
```

- `schema`: always `magenda.end-of-day/2`. A routine that sees another value should stop.
- `scope`: always present, `day` or `meeting`. `part`: the part number, in a meeting run only.
- `pages[].earlierPart`: in a day run only. The page was already sent as that part of this date
  and must not be processed again.
- `step`: `notes`, `approve-notes` or `approve-summary` (see below).
- `date`: the day, `YYYY-MM-DD`. `checksum`: `sha256:` and the 64 lowercase hex digits of the PDF.
- `driveFileID` and `docID`: the PDF and the Doc. Left out when not known.
- `pageCount` equals the number of PDF pages. `pages[].page` is the 1-based position in the PDF
  and `key` is Magenda's page key (`overview`, `delegated:<n>`, `meeting:<event key>`, `notes`,
  `extra:<id>`).
- Meeting pages carry `calendarID` and `eventID` (the event key split at its first `|`), the page
  `title`, and `summarySkill` when a skill is mapped to the meeting. A page the person added has
  `source`, the key of the page it copies. Keys with no value are left out.
- `tasks` are the printed to-do rows in order (`taskID` is the Google task ID when the row came
  from one). `delegated` are the delegated rows in page order.
- A very long day is cut down to fit. First `tasks` and `delegated` are dropped and `"truncated":
  true` is added. If that is still too long, each page also loses `title`, `summarySkill` and
  `source`. Read the PDF for what the payload leaves out.
- JSON permits `\/` for `/`; a parser handles either.
- A meeting run has no `tasks` and no `delegated`. Its `pages` and `pageCount` describe the
  meeting's own PDF, numbered from 1. `earlierPart` survives the cut-down above.

A meeting run, which is the same shape with `scope` `meeting`:

```json
{"checksum":"sha256:…","date":"2026-10-26","docID":"…","driveFileID":"…","pageCount":2,"pages":[{"calendarID":"work@example.com","eventID":"ev1","key":"meeting:work@example.com|ev1","page":1,"summarySkill":"meeting-summary","title":"Weekly sync"},{"key":"extra:x1","page":2,"source":"meeting:work@example.com|ev1"}],"part":1,"schema":"magenda.end-of-day/2","scope":"meeting","step":"notes"}
```

The same meeting in the day run later: `{"calendarID":"work@example.com","earlierPart":1,"eventID":"ev1","key":"meeting:work@example.com|ev1","page":2,"title":"Weekly sync"}`.

## Steps

Each step starts a new routine run. The routine does the work of its step only and then sets the
Doc's first line.

- **`notes`** (sent when the day is uploaded). Download `driveFileID` through PrivacyFence and
  check that the file sits in the `Magenda` folder and that its SHA-256 equals `checksum`; stop
  and say so in the Doc if not. Write the notes under the status line. Read each meeting page's
  `Summary:` line (a skill printed on the page, or one the person wrote by hand) together with
  `summarySkill`. Then set the first line to `Status: Notes ready for review`.
- **`approve-notes`** (the person approved the notes). If any meeting needs a summary, write it
  with that skill and set `Status: Summary ready for review`. Otherwise close the day.
- **`approve-summary`** (the person approved the summary). Close the day.
- **Closing** updates Google Tasks, prepares the meeting memos as Gmail drafts and sets
  `Status: Closed`.

A **meeting run** does the same for that meeting only: `notes` writes that meeting's notes;
`approve-notes` writes its summary when it has a skill, else closes; closing prepares that
meeting's memo draft and updates the tasks from its pages only.

A **day run** skips every page with `earlierPart` in the notes, summaries, memos and task updates.
The overview, delegated, notes and unsent meeting pages are processed as before.

## Status lines

Magenda reads the first non-empty line of the Doc (a leading byte-order mark and surrounding
whitespace are ignored). It must start with `Status:` in any letter case; the rest, trimmed and in
any letter case, must be exactly one of:

| First line | Meaning | Magenda offers |
|---|---|---|
| `Status: Waiting for notes` | The Doc is new, or the routine is writing the notes | nothing |
| `Status: Notes ready for review` | The notes are written | `Approve notes` |
| `Status: Summary ready for review` | The summary is written | `Approve` |
| `Status: Closed` | The day is done | nothing |

Any other first line reads as unknown and offers nothing. Keep the line exact and on the first
line; never put anything above it.

## Idempotency

The fire endpoint has no idempotency key, so a person's retry can start the same step twice. A step
already run for the same `date`, `step` and `checksum` must do nothing: no second set of notes, no
second set of drafts, no change to the Doc's status. A new checksum for a date (the person finished
the day again before it was sent) is a new run.

## Sending a meeting early

On a meeting page, Send Meeting (after a confirmation) renders the meeting page and the pages added
as copies of it into their own PDF, uploads it as part `n` of the date (1, 2, … in the order sent),
creates the part's own Doc and fires `notes` with `scope` `meeting`. The part has its own row in
the Review list and its own review loop. Its pages are locked from then on, so later handwriting
can't be lost. Send Meeting is refused once the day was finished. Finish Day later uploads the whole
day, sent meetings included, and marks their pages with `earlierPart`. A part's PDF has its own
checksum, so the idempotency rule above applies to it separately.

## Sending a day again

Reset Hand-off in the binder deletes Magenda's record of a day, so Finish Day works again
([ADR 0032](adr/0032-a-sent-days-hand-off-can-be-reset-after-asking.md)). The next finish uploads a
new PDF and creates a new Doc; the earlier ones stay in Drive. Its payload has the new `driveFileID`
and `docID`, and a new `checksum` when the PDF changed. A reset also forgets the date's sent meetings and
unlocks their pages, so those meetings can be sent again.

## Deleting the handwriting

Only a finished day starts the deletion. Magenda records the day it first reads `Status: Closed` on
the day's Doc. Five days later, the next time the app refreshes, it deletes that day's handwriting
and the stored PDFs of the day and of its sent meetings from the device. A date whose meetings were
sent but whose day was never finished is not deleted. The finished-day
record stays, so the day cannot be sent a second time. The PDF and the Doc in Drive are left alone.
