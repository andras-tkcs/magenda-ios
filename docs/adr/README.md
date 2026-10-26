# Architecture Decision Records

An **Architecture Decision Record (ADR)** is a short, numbered, permanent note of one significant
decision: the situation that forced it, what was decided, what was rejected and why, and what
follows from it. ADRs answer the question a standing reference doc cannot: *why is it this way,
and why didn't we just…?*

This directory is the only place that question gets answered. Plans come and go, reference docs
describe whatever the code does today, and neither keeps a rejected alternative around for long.

## Where each kind of document lives

| Kind | Answers | Home | Lifecycle |
|---|---|---|---|
| **Plan** | What are we about to do, and in what order? | A GitHub issue (preferred), or a `docs/*-plan.md` while its work is open | Temporary. Deleted when its work lands, **after** its decisions have been extracted here |
| **ADR** | Why is it this way, and what was rejected? | `docs/adr/NNNN-*.md` | Permanent. Never deleted; after acceptance only its Status changes |
| **Reference** | How does it work, or how do I do X, today? | `docs/*.md`, `CONTRIBUTING.md`, code docstrings | Living. Edited in the same PR as the behavior. Links here for the *why* instead of retelling it |

## When a decision needs an ADR

Write one when a decision meets **any** of these:

- it is expensive or disruptive to reverse (a packaging format, a wire protocol, a data model);
- it sets or moves a trust or security boundary, or decides who holds a credential;
- it changes how the project is built, released or distributed;
- it rejects an alternative a reasonable newcomer would propose, for a reason that isn't obvious;
- it deliberately departs from a rule written elsewhere in this repo (e.g. "stdlib first");
- someone will plausibly ask "why didn't we just…?" in six months.

Implementation detail, naming, and task sequencing don't need one. If in doubt, write a short one:
a 40-line ADR is fine.

## Rules

1. **One decision per ADR.** A document that decides several things is a plan; split its decisions
   out.
2. **Frozen once accepted.** After `Accepted`, the body is not rewritten. The only permitted edits
   are the Status section, fixing a broken link, and typos. Implementation progress, rollout state
   and "phase N landed" notes belong in the tracking issue, not here.
3. **Change your mind with a new ADR.** A reversal or significant amendment is a new ADR that says
   `Supersedes NNNN` (or `Amends NNNN`); the old one's Status gains one line pointing forward.
   This holds even when a plan says "amend ADR NNNN in place": the plan is wrong about it.
4. **Link only to things that last.** Issues, PRs, commit SHAs, source files, and other ADRs. Never
   link a plan document: it will be deleted. To cite a plan that is already gone, give the commit
   that deleted it and the path, e.g. `git show abc1234^:docs/some-feature-plan.md`.
5. **Retiring a plan is gated on this directory.** The PR that deletes a plan either adds or amends
   the ADRs for every decision the plan contained, or states in its description that the plan
   contained none. This is part of the definition of done
   ([`coding-and-testing-guidelines.md`, "Definition of done"](../coding-and-testing-guidelines.md#definition-of-done)).
6. **Numbers are never reused.** Take the next free number when you open the PR; if a parallel
   branch takes it first, renumber yours before merging.
7. **Update the index below** in the same PR, and `docs/README.md` needs no change: it links here.

### Status values

| Status | Meaning |
|---|---|
| `Proposed` | Under discussion; decides nothing yet |
| `Accepted` | In force. Say whether it is implemented if that isn't obvious |
| `Rejected` | Considered and declined; kept so it isn't re-proposed from scratch |
| `Superseded by NNNN` | Replaced; kept for the reasoning trail |
| `Deprecated` | No longer relevant (the thing it governed is gone) with no replacement |

A decision recorded after the fact says so: `Accepted (recorded retroactively on YYYY-MM-DD;
decided around YYYY-MM-DD in <source>)`.

## Template

Copy this into `docs/adr/NNNN-short-kebab-title.md`. The title states the decision, not the topic.

```markdown
# ADR NNNN: <the decision, stated as a short sentence>

## Status

Accepted — YYYY-MM-DD. <One line on implementation state if not obvious.>
<Supersedes / Amends / Superseded by lines, one each, if any.>

## Context

What forced a decision: the problem, the constraints, the facts that mattered. Short.

## Decision

What was decided, stated so it can be checked against the code.

## Alternatives considered

- **<Alternative>** — why it was rejected.

## Consequences

What becomes easier, what becomes harder, what is now ruled out, what risk is accepted.

## Verification

Where the decision is enforced or observable: files, tests, workflows, guards.

## Related

Issues, PRs, commits, other ADRs. For a deleted source document: `git show <sha>^:<path>`.
```

## Index

ADRs 0001–0010 were inherited from the template this repository started from; each still applies
until a later ADR supersedes it.

| # | Decision | Status |
|---|---|---|
| [0001](0001-record-decisions-as-adrs-and-keep-plans-temporary.md) | Record decisions as ADRs; plans are temporary and deleted when their work lands | Accepted |
| [0002](0002-process-docs-live-in-docs-not-in-claude-md.md) | Process documentation lives in `docs/` and `CONTRIBUTING.md`, not in `CLAUDE.md` | Accepted |
| [0003](0003-the-xcode-project-is-generated-from-project-yml.md) | The Xcode project is generated from `project.yml` by XcodeGen and never committed | Accepted |
| [0004](0004-the-version-comes-from-the-git-tag.md) | The version comes from the git tag and the build number from the commit count | Accepted |
| [0005](0005-changelog-is-the-only-source-of-release-notes.md) | `CHANGELOG.md` is the only source of release notes | Accepted |
| [0006](0006-a-release-is-cut-by-a-workflow-after-a-build-pre-flight.md) | A release tag is pushed by a workflow with a non-`GITHUB_TOKEN` credential, after a `build.yml` pre-flight | Accepted |
| [0007](0007-logic-lives-in-a-platform-independent-swift-package.md) | Logic lives in AppCore, a Swift package that builds and tests on Linux; the app target is a thin SwiftUI shell | Accepted |
| [0008](0008-code-and-docs-carry-no-project-history.md) | Code and standing docs carry no project history | Accepted |
| [0009](0009-signing-and-upload-use-an-app-store-connect-api-key.md) | Signing and upload use Xcode's automatic signing with an App Store Connect API key held in a protected environment | Accepted |
| [0010](0010-swift-format-from-the-toolchain-is-the-only-linter.md) | `swift format` from the toolchain is the only formatter and linter | Accepted |
| [0011](0011-the-agenda-pdf-is-drawn-on-device-from-the-vendored-magenda-template.md) | The agenda PDF is drawn on the device from the Python Magenda's compiled template, vendored at a pinned commit | Accepted |
| [0012](0012-text-layout-is-computed-in-appcore-and-audited.md) | Text layout is computed in AppCore against a measuring protocol into a positioned plan, and every plan is audited | Accepted |
| [0013](0013-google-sign-in-uses-pkce-with-aswebauthenticationsession.md) | Google sign-in is OAuth 2.0 with PKCE presented by `ASWebAuthenticationSession`, with the user's own client kept in the Keychain | Accepted |
| [0014](0014-agenda-inputs-come-live-from-google-calendar-and-google-tasks.md) | The agenda's inputs are read live from Google Calendar and Google Tasks, with task lists found by title | Accepted |
| [0015](0015-appcore-may-import-observation.md) | AppCore may import the toolchain's `Observation` module | Accepted |
| [0016](0016-agenda-selection-uses-editable-rules-not-a-language-model.md) | What goes on the agenda is decided by fixed, editable rules, never by a language model | Accepted |
| [0017](0017-each-release-attaches-an-ad-hoc-signed-ipa.md) | A tagged release can attach an Ad Hoc signed `.ipa` | Accepted |
| [0018](0018-the-team-id-comes-from-the-app-store-environment.md) | The Team ID comes from the `app-store` environment's `APPLE_TEAM_ID` secret, not from the repository | Accepted |
| [0019](0019-alphas-are-tested-through-testflight-and-the-ad-hoc-ipa-is-opt-in.md) | Alphas are tested through TestFlight, and the Ad Hoc `.ipa` is opt-in | Accepted |
| [0020](0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md) | On iPad the agenda is a binder of native pages with PencilKit ink, and the PDF is only the export | Accepted |
| [0021](0021-a-binder-day-is-stored-as-a-content-snapshot-and-ink-per-page-key.md) | A binder day is stored as a content snapshot and ink per page key | Accepted |
| [0022](0022-binder-files-and-agenda-pdfs-are-written-with-complete-unless-open-protection.md) | Binder files and agenda PDFs are written with complete-unless-open file protection | Accepted |
| [0023](0023-binder-undo-uses-a-handwriting-history-kept-by-the-session.md) | Binder undo and redo use a handwriting history kept by the binder session, not PencilKit's undo manager | Accepted |
| [0024](0024-binder-pages-turn-sideways-one-whole-page-at-a-time.md) | The binder shows one whole page per screen and pages turn with a horizontal swipe | Accepted |
| [0025](0025-only-added-binder-pages-can-be-deleted.md) | Only pages added in the binder can be deleted, with their handwriting and undo history, after a confirmation | Accepted |
| [0026](0026-start-over-is-separate-from-render.md) | Render keeps a started day's handwriting; Start over is a separate, confirmed action that deletes it and renders the day fresh | Accepted |
| [0027](0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md) | Finished days are uploaded to the person's Google Drive as one PDF, with the `drive.file` scope; existing users sign in again | Accepted |
| [0028](0028-the-end-of-day-routine-is-started-through-its-api-trigger.md) | Magenda starts the end-of-day Claude routine through its API trigger and never repeats a fire on its own | Accepted |
| [0029](0029-the-days-google-doc-is-the-review-record.md) | The day's Google Doc is the review record, and approve buttons start the routine's next step | Accepted |
| [0030](0030-a-closed-days-handwriting-is-deleted-five-days-later.md) | A closed day's handwriting is deleted from the device five days after Magenda first reads Closed | Accepted |
| [0031](0031-meeting-summaries-are-requested-by-skill.md) | A meeting's summary is requested with a title-to-skill map in the rules, or by writing a skill on its page | Accepted |
| [0032](0032-a-sent-days-hand-off-can-be-reset-after-asking.md) | A day's hand-off can be reset after asking, so a day can be finished and sent again | Accepted |
| [0033](0033-a-meeting-can-be-sent-before-the-day-ends.md) | A meeting can be sent to the routine before the day ends, as its own PDF and Doc, and its pages are locked afterwards | Accepted |
| [0034](0034-the-payload-moves-to-schema-2-and-marks-pages-sent-earlier.md) | The routine payload moves to `magenda.end-of-day/2` and marks the pages of meetings sent earlier | Accepted |
| [0035](0035-start-over-is-refused-while-a-meeting-is-sent.md) | Start Over is refused while a meeting of the day is sent, and Reset Hand-off unlocks the pages | Accepted |
| [0036](0036-finished-days-upload-to-a-drive-folder-named-in-settings.md) | Finished days and meetings sent early upload to a Drive folder named in Settings, and each date stays in the folder its first upload used | Accepted |
| [0037](0037-people-rules-are-filled-from-the-system-contact-picker.md) | People rules are filled from the system contact picker, which needs no Contacts permission | Accepted |
| [0038](0038-summaries-are-written-by-dedicated-summary-routines-that-magenda-starts.md) | Summaries are written by dedicated summary routines, one Claude routine and API trigger per kind, chosen with checkboxes and started by Magenda when the notes are approved | Accepted |
| [0039](0039-a-summary-announces-itself-in-the-doc-with-a-marker-line.md) | A summary announces itself in the Doc with a `Summary ready: <routine ID> <page>` marker line, and Approve summaries closes the day | Accepted |
| [0040](0040-the-routine-payload-moves-to-schema-3-and-summaries-have-their-own-schema.md) | The routine payload moves to `magenda.end-of-day/3` with steps `notes` and `close`, and summary routines receive `magenda.summary/1` | Accepted |
