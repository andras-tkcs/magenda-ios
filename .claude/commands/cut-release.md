---
description: Pre-flight and cut a release tag through the release workflow
argument-hint: "<version>  e.g. 1.2.0, or 1.2.0-alpha.1 / 1.2.0-beta.2 / 1.2.0-rc.1"
---

Cut the release: **$ARGUMENTS**

If no version was given above, stop and ask. Never infer the next version from `CHANGELOG.md` or
`project.yml` — the git tag is the only version source, and the build number is the commit count
(ADR 0004).

A cloud container cannot push `refs/tags/*`, so the tag is cut by `.github/workflows/release.yml`.
Do not try to `git tag && git push` from here; it will fail on the push and may leave a local tag
behind that makes later checks lie.

**Before dispatching anything**, report the state so I can sanity-check it:

- `git fetch origin main --tags`, and what commit `origin/main` is at
  (`git log -1 --oneline origin/main`). That commit is what gets tagged, and its build number will
  be `git rev-list --count origin/main`.
- `python3 scripts/release_channel.py <version>` and `--marketing <version>` — the channel, and the
  version App Store Connect will show.
- `git tag --list 'v*' --sort=-v:refname | head` — the most recent tags, so the sequence is
  visible. A pre-release must be exactly +1 on its stage; a stable must be an unskipped bump.
- For a **stable** version only: `python3 scripts/changelog_section.py <version>` must succeed;
  show me the rendered notes, which are the literal GitHub Release body. Never pass
  `--allow-unreleased`. If it fails because `[Unreleased]` is still populated, the fix is a PR that
  merges those entries into the version's section, not a flag.
- For a **stable** version only: whether a release candidate of this version was tagged and
  tested (`docs/release-testing.md`). If not, say so; I may want one first.

**Then pre-flight `build.yml` against that same commit — do not skip this** (ADR 0006).
`release.yml` builds nothing. Dispatch `.github/workflows/build.yml` (`workflow_dispatch`, no
inputs) against `origin/main`'s exact commit and wait for `version` and `archive` to finish. The
signing and upload jobs are gated on a tag ref, so this run uploads nothing. Report the run URL and
its outcome.

If it fails: stop. Treat it as an ordinary CI failure on `main` — diagnose, fix, push, and re-run
this pre-flight against the fixed commit — before touching `release.yml`.

**Only once the pre-flight is green, dispatch `release.yml` against `main` with
`dry_run: true`** and report the result. The dry run performs every check and creates the tag on
the runner without pushing it.

**Only cut for real once I have seen the dry run and said to.** Then re-dispatch with
`dry_run: false`, and watch it: the workflow verifies that `build.yml` started for the tagged
commit, and a failure there means the tag exists but the release did not start — tell me
immediately if that happens; it needs the tag deleted and re-pushed, not a retry.

After a real cut, report the tag and the `build.yml` run URL, and follow that run to the end:
whether `testflight` uploaded (if the `app-store` environment has a required reviewer, say that it
is waiting for approval), and whether the GitHub Release was created. Remind me that the build
appears in TestFlight only after Apple's processing, and that submitting a stable version for App
Review is mine to do in App Store Connect.
