#!/usr/bin/env python3
"""Coverage ratchet: fail if AppCore's line coverage drops below its recorded floor.

`swift test --enable-code-coverage` only measures. This script is the gate: it reads the JSON
`swift test --show-codecov-path` points to (an `llvm-cov export` report), keeps the files under
`AppCore/Sources/`, and fails if

  * their combined line coverage is below OVERALL_FLOOR, or
  * any file in MODULE_FLOORS is below its own floor.

A failing file is reported with the lines where its never-run regions begin.

Only AppCore is ratcheted. The app target is a thin SwiftUI shell whose views are exercised by the
UI tests rather than measured line by line; logic that needs a floor belongs in AppCore (ADR 0007).

MODULE_FLOORS exists because one overall number protects no single file: a file that decides
something that matters can lose half its coverage inside the aggregate. List those files with a
comment saying why each one is there.

A floor only moves up. A PR whose tests raise a file's coverage raises its floor in the same PR; a
PR that needs to lower one is a coverage regression and says so in its description, never a silent
edit here. A new floor is set to the measured value rounded down to a whole percent.

    swift test --package-path AppCore --enable-code-coverage
    python3 scripts/check_coverage_floor.py "$(swift test --package-path AppCore --show-codecov-path)"
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SOURCES = "AppCore/Sources/"

OVERALL_FLOOR = 100.0

MODULE_FLOORS: dict[str, float] = {
    # What the app reports about its own build; a wrong version on screen misleads every bug report.
    "AppCore/Sources/AppInfo.swift": 100.0,
    # Text fitting and layout: a wrong cut or position puts text over the template or off the page.
    "AppCore/Sources/Layout/TextFitter.swift": 100.0,
    # Places the schedule, meeting and further-notes pages; an error moves text on every agenda.
    "AppCore/Sources/Layout/AgendaLayout.swift": 100.0,
    # The to-do grid and its omitted-task report; a wrong row height hides or overlaps tasks.
    "AppCore/Sources/Layout/AgendaLayout+Overview.swift": 100.0,
    # The delegated table's rows, marks and pagination.
    "AppCore/Sources/Layout/AgendaLayout+Delegated.swift": 100.0,
    # The check that proves no plan puts text outside its container or over other text.
    "AppCore/Sources/Layout/LayoutAudit.swift": 100.0,
    # Builds the sign-in and token requests; a wrong state or challenge check weakens PKCE.
    "AppCore/Sources/Google/GoogleOAuth.swift": 100.0,
    # Holds the tokens and refreshes them; a wrong branch signs the user out or leaks a stale token.
    "AppCore/Sources/Google/GoogleSession.swift": 100.0,
    # Folds and compares text; every binder rule that matches a title depends on it.
    "AppCore/Sources/Settings/BinderText.swift": 100.0,
    # Strips prefixes and picks the meeting-page title shown on the page.
    "AppCore/Sources/Settings/MeetingTitle.swift": 100.0,
    # Recognises "to be discussed" tasks and the person they name.
    "AppCore/Sources/Settings/TaskTitle.swift": 100.0,
    # Parses the delegated-task format read from Google Tasks, including its warnings.
    "AppCore/Sources/Settings/DelegatedTask.swift": 100.0,
    # Decides which events reach the agenda and why the others are left out.
    "AppCore/Sources/Draft/EventSelection.swift": 100.0,
    # Decides which tasks reach the to-do list and the delegated page, and in what order.
    "AppCore/Sources/Draft/TaskSelection.swift": 100.0,
    # Places added and kept pages and remaps links; an error puts handwriting on the wrong page.
    "AppCore/Sources/Binder/BinderLayout.swift": 100.0,
    # Saves handwriting and the day's snapshot; a wrong branch loses ink.
    "AppCore/Sources/Binder/BinderStore.swift": 100.0,
    # Uploads the day's PDF and creates its Doc; a wrong request loses a day or files it twice.
    "AppCore/Sources/Google/GoogleDriveClient.swift": 100.0,
    # Validates the routine's credentials and fires it; a wrong branch leaks a token or misreports a fire.
    "AppCore/Sources/Handoff/RoutineTrigger.swift": 100.0,
    # The finished-day record, its phases and the payload the routine receives.
    "AppCore/Sources/Handoff/DayHandoff.swift": 100.0,
    # Reads the Doc's status line; a wrong reading offers the wrong approve button.
    "AppCore/Sources/Handoff/DocStatus.swift": 100.0,
    # Saves the finished-day records and PDFs; a wrong branch loses a day's hand-off state.
    "AppCore/Sources/Handoff/HandoffStore.swift": 100.0,
    # Drives upload, fire, approve and the five-day deletion; an error sends a day twice or deletes ink early.
    "AppCore/Sources/Handoff/HandoffController.swift": 100.0,
    # The fixture Drive and routine behind the hand-off UI tests.
    "AppCore/Sources/Handoff/HandoffFixtures.swift": 100.0,
    # Picks the summary skill a meeting asks for; a wrong match prints the wrong skill on the page.
    "AppCore/Sources/Settings/SummarySkill.swift": 100.0,
    # Names, validates and looks up the summary routines a meeting asks for; a wrong match starts the wrong routine.
    "AppCore/Sources/Settings/SummaryRoutine.swift": 100.0,
    # Fires a summary routine with its own token; a wrong branch sends one routine's summary with another's token.
    "AppCore/Sources/Handoff/SummaryRoutineTrigger.swift": 100.0,
}


def _relative(filename: str) -> str | None:
    """`.../AppCore/Sources/X.swift` -> `AppCore/Sources/X.swift`; None for anything else."""
    posix = Path(filename).as_posix()
    index = posix.rfind(SOURCES)
    return posix[index:] if index >= 0 else None


def _zero_count_lines(entry: dict) -> list[int]:
    """Lines where a region that never ran begins; empty if the report carries no segments."""
    return sorted(
        {
            seg[0]
            for seg in entry.get("segments", [])
            if len(seg) >= 5 and seg[3] and seg[4] and seg[2] == 0 and not (len(seg) > 5 and seg[5])
        }
    )


def _load(report: dict) -> tuple[float | None, dict[str, float], dict[str, list[int]]]:
    """Combined line coverage of AppCore's sources (None if there are none), each file's, and the
    lines where each file's never-run regions begin."""
    per_file: dict[str, float] = {}
    zero_lines: dict[str, list[int]] = {}
    covered = total = 0
    for entry in report["data"][0]["files"]:
        rel = _relative(entry["filename"])
        if rel is None:
            continue
        lines = entry["summary"]["lines"]
        covered += lines["covered"]
        total += lines["count"]
        per_file[rel] = 100.0 if lines["count"] == 0 else 100.0 * lines["covered"] / lines["count"]
        zero_lines[rel] = _zero_count_lines(entry)
    overall = None if not per_file else (100.0 if total == 0 else 100.0 * covered / total)
    return overall, per_file, zero_lines


def check(report: dict) -> list[str]:
    """Every floor that is not met, as a human-readable line. Empty means the gate passes."""
    overall, per_file, zero_lines = _load(report)
    if overall is None:
        return [f"the report has no files under {SOURCES} -- was it produced by `swift test` in AppCore?"]
    failures: list[str] = []

    def where(path: str) -> str:
        lines = zero_lines.get(path, [])
        if not lines:
            return ""
        return f" (zero-count regions start at lines {', '.join(map(str, lines))})"

    print(f"AppCore line coverage: {overall:.2f}% (floor {OVERALL_FLOOR:.1f}%)")
    if overall < OVERALL_FLOOR:
        failures.append(f"AppCore line coverage {overall:.2f}% is below the {OVERALL_FLOOR:.1f}% floor")
        for path in sorted(per_file):
            if path.startswith(SOURCES) and path not in MODULE_FLOORS and per_file[path] < 100.0:
                failures.append(f"{path} is at {per_file[path]:.2f}%{where(path)}")
    if MODULE_FLOORS:
        print("\nFile floors:")
    for path, floor in MODULE_FLOORS.items():
        if path not in per_file:
            # Renamed or deleted without updating this table: the floor protects nothing.
            failures.append(f"{path} is not in the coverage report (renamed or deleted?)")
            print(f"  MISSING {path}")
            continue
        actual = per_file[path]
        if actual < floor:
            print(f"  FAIL {path}: {actual:.2f}% (floor {floor:.1f}%){where(path)}")
            failures.append(f"{path} coverage {actual:.2f}% is below its {floor:.1f}% floor{where(path)}")
        else:
            print(f"  ok   {path}: {actual:.2f}% (floor {floor:.1f}%)")
    return failures


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("report", help="the JSON file `swift test --show-codecov-path` prints")
    args = parser.parse_args(argv)

    path = Path(args.report)
    if not path.is_file():
        print(f"error: {path} not found -- run `swift test --enable-code-coverage` in AppCore first", file=sys.stderr)
        return 2

    failures = check(json.loads(path.read_text(encoding="utf-8")))
    if failures:
        print("\nCoverage floor FAILED:", file=sys.stderr)
        for line in failures:
            print(f"  - {line}", file=sys.stderr)
        print("\nAdd tests for the new code. Lowering a floor is a regression, not a config edit.", file=sys.stderr)
        return 1
    print("\nCoverage floor passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
