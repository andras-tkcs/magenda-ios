#!/usr/bin/env python3
"""Choose the tests one CI shard runs, balanced from measured timings.

`tests.yml` runs the hosted tests and the UI tests as a few shards. This script splits them so the
shards take about the same time, and fails when a UI test class has no timing:

    python3 scripts/ui_shards.py --shard 1     # -only-testing: words for shard 1 of 4
    python3 scripts/ui_shards.py --check       # every test class has a timing, and none is stale
    python3 scripts/ui_shards.py --table       # each shard's total and its entries
    python3 scripts/ui_shards.py --only MagendaUITests/RulesUITests   # one job's tests, unsharded
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SHARD_COUNT = 4

# The UI test class tests.yml runs on its own before a job's tests, to warm up XCTest on a
# just-booted simulator (ADR 0049). It has no timing and is never in a shard or `--only`.
WARM_UP_CLASS = "WarmUpUITests"

# Seconds each entry takes on the newest iPad: the median of tests.yml runs 40466925355 and
# 40467180761 (their green shards, and the tests a cancelled shard finished), rounded up to a
# multiple of 10. A failed test's time is left out. An entry is the
# hosted test target (its Swift Testing time plus 20 s), a whole UI test class, or one UI test
# method of a class that is too long for one shard. Shards are balanced from these, so `--check`
# (and the scripts job) fails when a test class or method has no entry. The first test in each
# shard also pays the simulator's cold first launch, so a shard runs a little longer than its total.
CLASS_SECONDS: dict[str, int] = {
    "MagendaTests": 30,
    "MagendaUITests/AgendaEditUITests": 290,
    "MagendaUITests/AgendaScreenUITests": 290,
    "MagendaUITests/BinderUITests": 430,
    "MagendaUITests/HandoffUITests": 520,
    "MagendaUITests/LaunchOptionsUITests": 60,
    "MagendaUITests/LongTextUITests": 280,
    "MagendaUITests/PreviewUITests": 80,
    "MagendaUITests/RulesUITests/testADuplicateSummaryTitleShowsAnError": 140,
    "MagendaUITests/RulesUITests/testAddingAMeetingSummaryShowsTheRowWithTheRoutineName": 110,
    "MagendaUITests/RulesUITests/testAddingAPersonShowsTheAlias": 90,
    "MagendaUITests/RulesUITests/testAddingAPersonalBlockLeavesMatchingEventsOffTheAgenda": 50,
    "MagendaUITests/RulesUITests/testAddingASummaryWithoutAChoiceShowsAnError": 60,
    "MagendaUITests/RulesUITests/testAddingATitlePatternShowsItsRow": 110,
    "MagendaUITests/RulesUITests/testAnInvalidPatternShowsAnError": 70,
    "MagendaUITests/RulesUITests/testChoosingAContactFillsThePerson": 60,
    "MagendaUITests/RulesUITests/testDeletingAPersonalBlockBringsItsEventsBack": 40,
    "MagendaUITests/RulesUITests/testEditTogglesTheRulesIntoEditing": 40,
    "MagendaUITests/RulesUITests/testLongPressDeletesADefaultOutOfOfficeWord": 60,
    "MagendaUITests/RulesUITests/testResetRulesRestoresTheDefaults": 90,
    "MagendaUITests/RulesUITests/testTheLookAheadStepperIncrements": 60,
    "MagendaUITests/RulesUITests/testWithoutSummaryRoutinesTheRulesSaySoInsteadOfCheckboxes": 40,
    "MagendaUITests/SettingsUITests/testAFolderNameIsSavedAndAnInvalidOneShowsAnError": 60,
    "MagendaUITests/SettingsUITests/testASummaryRoutineWithoutANameOrWithABadURLShowsAnError": 70,
    "MagendaUITests/SettingsUITests/testAddingASummaryRoutineShowsItsRowAndForgettingRemovesIt": 130,
    "MagendaUITests/SettingsUITests/testAnInvalidHexShowsAnErrorAndAValidOneClearsIt": 50,
    "MagendaUITests/SettingsUITests/testAnInvalidRoutineShowsAnErrorAndAValidOneIsSaved": 90,
    "MagendaUITests/SettingsUITests/testChoosingAFontAndRenderingReachesThePreview": 40,
    "MagendaUITests/SettingsUITests/testChoosingNoDelegatedListRemovesTheDelegatedPage": 70,
    "MagendaUITests/SettingsUITests/testForgettingTheClientReturnsToSetup": 30,
    "MagendaUITests/SettingsUITests/testForgettingTheRoutineBringsBackTheFields": 40,
    "MagendaUITests/SettingsUITests/testResetColorsRestoresTheDefaults": 60,
    "MagendaUITests/SettingsUITests/testSavingAnExistingSummaryRoutineNameKeepsOneRow": 110,
    "MagendaUITests/SettingsUITests/testSigningOutReturnsToSignIn": 70,
    "MagendaUITests/SettingsUITests/testTheCalendarsScreenChoosesACalendar": 60,
    "MagendaUITests/SettingsUITests/testTheClientIDIsShownAndChangeOpensTheSetupSheet": 40,
    "MagendaUITests/SettingsUITests/testTheRulesLinkAndTheVersionAreThere": 60,
    "MagendaUITests/SetupUITests": 20,
    "MagendaUITests/SignInUITests": 20,
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
        if name == WARM_UP_CLASS:
            continue
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


def select(names: str, classes: dict[str, list[str]]) -> list[str]:
    """The test keys named in `names` (separated by commas or whitespace), without duplicates.

    Only known tests are accepted, so the result is safe to word-split in a shell.
    """
    valid = {"MagendaTests"}
    for name, methods in classes.items():
        if name == WARM_UP_CLASS:
            continue
        valid.add(f"MagendaUITests/{name}")
        valid.update(f"MagendaUITests/{name}/{method}" for method in methods)
    keys = list(dict.fromkeys(part for part in re.split(r"[,\s]+", names) if part))
    unknown = [key for key in keys if key not in valid]
    if unknown:
        raise ValueError(f"unknown tests: {', '.join(unknown)}")
    if not keys:
        raise ValueError("--only needs at least one test")
    return keys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--shard", type=int, metavar="N", help="print shard N's xcodebuild arguments (1-based)")
    group.add_argument("--check", action="store_true", help="check that every test class has a timing")
    group.add_argument("--table", action="store_true", help="print each shard's total and entries")
    group.add_argument(
        "--only",
        metavar="NAMES",
        help="print the xcodebuild arguments for these comma-separated tests, without sharding",
    )
    parser.add_argument("--count", type=int, default=SHARD_COUNT, help="number of shards (default: %(default)s)")
    args = parser.parse_args(argv)

    if args.check:
        lines = problems(CLASS_SECONDS, test_classes(REPO / "AppUITests"))
        for line in lines:
            print(line)
        return 1 if lines else 0

    if args.only is not None:
        try:
            keys = select(args.only, test_classes(REPO / "AppUITests"))
        except ValueError as error:
            parser.error(str(error))
        print(" ".join(arguments(keys)))
        return 0

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
