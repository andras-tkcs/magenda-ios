#!/usr/bin/env python3
"""Run every blocking check CI runs on a pull request, and report PASS/FAIL/SKIP for each.

This is the automated half of the definition of done (docs/coding-and-testing-guidelines.md,
"Definition of done") and the second gate of docs/release-testing.md. `/dod` runs the same commands
and also reads the diff.

    python3 scripts/pre_release_check.py

AppCore, formatting and the scripts' own tests run anywhere a Swift toolchain is installed, Linux
included. The rows that build the app need macOS with Xcode and XcodeGen; elsewhere they are
reported as SKIP, and their result has to come from `tests.yml` for the same commit instead. A
SKIP is never a pass.

Every check runs even when an earlier one fails, so one run shows everything that is red.
"""

from __future__ import annotations

import platform
import subprocess  # nosec B404  # fixed argv lists only
import sys
from collections.abc import Callable
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PY = sys.executable
SCHEME = "Magenda"
DERIVED_DATA = "build/DerivedData"
FORMATTED = ["App", "AppTests", "AppUITests", "AppCore/Package.swift", "AppCore/Sources", "AppCore/Tests"]


def _run(cmd: list[str]) -> bool:
    print(f"$ {' '.join(cmd)}", flush=True)
    try:
        return subprocess.run(cmd, cwd=REPO_ROOT).returncode == 0  # nosec B603
    except FileNotFoundError:
        print(f"error: {cmd[0]!r} not found")
        return False


def _coverage_floor() -> bool:
    try:
        path = subprocess.run(  # nosec B603 B607
            ["swift", "test", "--package-path", "AppCore", "--show-codecov-path"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"error: cannot locate the coverage report: {exc}")
        return False
    return _run([PY, "scripts/check_coverage_floor.py", path])


def _xcodebuild_test(target: str) -> bool:
    destination = subprocess.run(  # nosec B603
        [PY, "scripts/simulator.py"], cwd=REPO_ROOT, capture_output=True, text=True
    )
    if destination.returncode != 0:
        print(destination.stderr.strip())
        return False
    print(destination.stderr.strip())
    return _run(
        [
            "xcodebuild", "test",
            "-project", f"{SCHEME}.xcodeproj",
            "-scheme", SCHEME,
            "-destination", destination.stdout.strip(),
            "-derivedDataPath", DERIVED_DATA,
            f"-only-testing:{target}",
            "-quiet",
        ]
    )


ANYWHERE: dict[str, Callable[[], bool]] = {
    "swift test (AppCore)": lambda: _run(["swift", "test", "--package-path", "AppCore", "--enable-code-coverage"]),
    "coverage floor": _coverage_floor,
    "swift format": lambda: _run(["swift", "format", "lint", "--strict", "--parallel", "--recursive", *FORMATTED]),
    "scripts' tests": lambda: _run([PY, "-m", "unittest", "discover", "-s", "scripts/tests"]),
}

MACOS_ONLY: dict[str, Callable[[], bool]] = {
    "xcodegen generate": lambda: _run(["xcodegen", "generate", "--quiet"]),
    "app tests (simulator)": lambda: _xcodebuild_test(f"{SCHEME}Tests"),
    "UI tests (simulator)": lambda: _xcodebuild_test(f"{SCHEME}UITests"),
}


def main() -> int:
    on_macos = platform.system() == "Darwin"
    results: dict[str, str] = {}
    for name, check in {**ANYWHERE, **MACOS_ONLY}.items():
        if name in MACOS_ONLY and not on_macos:
            results[name] = "SKIP"
            continue
        print(f"--- {name} ---", flush=True)
        results[name] = "PASS" if check() else "FAIL"
        print(f"--- {name}: {results[name]} ---\n", flush=True)

    print("=== Summary ===")
    for name, result in results.items():
        print(f"  [{result}] {name}")
    if "FAIL" in results.values():
        return 1
    if "SKIP" in results.values():
        print(
            "\nNot the whole gate: the SKIP rows need macOS. Take their result from tests.yml's `app` "
            "jobs for this commit (dispatch it against the branch if no PR is open yet)."
        )
        return 0
    print("\nAll automated checks passed. The manual items of the definition of done still apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
