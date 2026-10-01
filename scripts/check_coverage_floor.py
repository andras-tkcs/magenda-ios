#!/usr/bin/env python3
"""Coverage ratchet: fail if AppCore's line coverage drops below its recorded floor.

`swift test --enable-code-coverage` only measures. This script is the gate: it reads the JSON
`swift test --show-codecov-path` points to (an `llvm-cov export` report), keeps the files under
`AppCore/Sources/`, and fails if

  * their combined line coverage is below OVERALL_FLOOR, or
  * any file in MODULE_FLOORS is below its own floor.

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
}


def _relative(filename: str) -> str | None:
    """`.../AppCore/Sources/X.swift` -> `AppCore/Sources/X.swift`; None for anything else."""
    posix = Path(filename).as_posix()
    index = posix.rfind(SOURCES)
    return posix[index:] if index >= 0 else None


def _load(report: dict) -> tuple[float | None, dict[str, float]]:
    """Combined line coverage of AppCore's sources (None if there are none), and each file's."""
    per_file: dict[str, float] = {}
    covered = total = 0
    for entry in report["data"][0]["files"]:
        rel = _relative(entry["filename"])
        if rel is None:
            continue
        lines = entry["summary"]["lines"]
        covered += lines["covered"]
        total += lines["count"]
        per_file[rel] = 100.0 if lines["count"] == 0 else 100.0 * lines["covered"] / lines["count"]
    overall = None if not per_file else (100.0 if total == 0 else 100.0 * covered / total)
    return overall, per_file


def check(report: dict) -> list[str]:
    """Every floor that is not met, as a human-readable line. Empty means the gate passes."""
    overall, per_file = _load(report)
    if overall is None:
        return [f"the report has no files under {SOURCES} -- was it produced by `swift test` in AppCore?"]
    failures: list[str] = []
    print(f"AppCore line coverage: {overall:.2f}% (floor {OVERALL_FLOOR:.1f}%)")
    if overall < OVERALL_FLOOR:
        failures.append(f"AppCore line coverage {overall:.2f}% is below the {OVERALL_FLOOR:.1f}% floor")
    if MODULE_FLOORS:
        print("\nFile floors:")
    for path, floor in MODULE_FLOORS.items():
        if path not in per_file:
            # Renamed or deleted without updating this table: the floor protects nothing.
            failures.append(f"{path} is not in the coverage report (renamed or deleted?)")
            print(f"  MISSING {path}")
            continue
        actual = per_file[path]
        status = "ok  " if actual >= floor else "FAIL"
        print(f"  {status} {path}: {actual:.2f}% (floor {floor:.1f}%)")
        if actual < floor:
            failures.append(f"{path} coverage {actual:.2f}% is below its {floor:.1f}% floor")
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
