#!/usr/bin/env python3
"""Choose the tests one CI shard runs, balanced from measured timings.

`tests.yml` runs the hosted tests and the UI tests as a few shards. This script splits them so the
shards take about the same time, and fails when a UI test class has no timing:

    python3 scripts/ui_shards.py --shard 1     # -only-testing: words for shard 1 of 4
    python3 scripts/ui_shards.py --check       # every test class has a timing, and none is stale
    python3 scripts/ui_shards.py --table       # each shard's total and its entries
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SHARD_COUNT = 4

# Seconds each entry took in the last measured tests.yml run on the newest iPad. An entry is the
# hosted test target, a whole UI test class, or one UI test method of a class that is too long for
# one shard. Shards are balanced from these, so `--check` (and the scripts job) fails when a test
# class or method has no entry.
CLASS_SECONDS: dict[str, int] = {
    "MagendaTests": 60,
    "MagendaUITests/AgendaEditUITests": 450,
    "MagendaUITests/AgendaScreenUITests": 120,
    "MagendaUITests/BinderUITests": 390,
    "MagendaUITests/HandoffUITests": 300,
    "MagendaUITests/LaunchOptionsUITests": 60,
    "MagendaUITests/LongTextUITests": 80,
    "MagendaUITests/PreviewUITests": 160,
    "MagendaUITests/RulesUITests": 1980,
    "MagendaUITests/SettingsUITests": 1260,
    "MagendaUITests/SetupUITests": 30,
    "MagendaUITests/SignInUITests": 30,
    "MagendaUITests/StartOverUITests": 60,
}

_CLASS_RE = re.compile(r"^(?:final )?class (\w+): XCTestCase", re.MULTILINE)
_TEST_RE = re.compile(r"^\s+func (test\w+)\(", re.MULTILINE)


def test_classes(directory: Path) -> dict[str, list[str]]:
    """Each XCTestCase class declared in `directory`'s Swift files, with its test methods."""
    classes: dict[str, list[str]] = {}
    for file in sorted(directory.glob("*.swift")):
        text = file.read_text(encoding="utf-8")
        names = _CLASS_RE.findall(text)
        if len(names) > 1:
            raise ValueError(f"{file.name} declares more than one XCTestCase")
        if names:
            classes[names[0]] = sorted(_TEST_RE.findall(text))
    return classes


def problems(seconds: dict[str, int], classes: dict[str, list[str]]) -> list[str]:
    """What is wrong with `seconds` for `classes`; empty when everything checks out."""
    found: list[str] = []
    if "MagendaTests" not in seconds:
        found.append("MagendaTests has no entry")
    expected = {"MagendaTests"}
    for name, methods in classes.items():
        whole = f"MagendaUITests/{name}"
        per_method = [f"{whole}/{method}" for method in methods]
        expected.add(whole)
        expected.update(per_method)
        has_whole = whole in seconds
        present = [key for key in per_method if key in seconds]
        if has_whole and present:
            found.append(f"{name} has an entry for the class and for some of its methods; keep one form")
        elif not has_whole and not present:
            found.append(f"{name} has no entry: add {whole} or one entry per method")
        elif not has_whole and len(present) != len(per_method):
            missing = ", ".join(key.rsplit("/", 1)[1] for key in per_method if key not in seconds)
            found.append(f"{name} has entries for only some of its methods; missing: {missing}")
    found.extend(f"{key} is stale: no such test" for key in seconds if key not in expected)
    return found


def assign(seconds: dict[str, int], count: int) -> list[list[str]]:
    """Split the keys into `count` shards of about equal total time, longest first."""
    shards: list[list[str]] = [[] for _ in range(count)]
    totals = [0] * count
    for key in sorted(seconds, key=lambda key: (-seconds[key], key)):
        index = totals.index(min(totals))
        shards[index].append(key)
        totals[index] += seconds[key]
    return [sorted(shard) for shard in shards]


def arguments(keys: list[str]) -> list[str]:
    """The `xcodebuild` arguments that select `keys`."""
    return ["-only-testing:" + key for key in keys]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--shard", type=int, metavar="N", help="print shard N's xcodebuild arguments (1-based)")
    group.add_argument("--check", action="store_true", help="check that every test class has a timing")
    group.add_argument("--table", action="store_true", help="print each shard's total and entries")
    parser.add_argument("--count", type=int, default=SHARD_COUNT, help="number of shards (default: %(default)s)")
    args = parser.parse_args(argv)

    if args.check:
        lines = problems(CLASS_SECONDS, test_classes(REPO / "AppUITests"))
        for line in lines:
            print(line)
        return 1 if lines else 0

    shards = assign(CLASS_SECONDS, args.count)
    if args.table:
        for number, keys in enumerate(shards, start=1):
            print(f"shard {number}: {sum(CLASS_SECONDS[key] for key in keys)} s: {', '.join(keys)}")
        return 0

    if not 1 <= args.shard <= args.count:
        parser.error(f"--shard must be between 1 and {args.count}")
    print(" ".join(arguments(shards[args.shard - 1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
