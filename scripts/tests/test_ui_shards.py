"""scripts/ui_shards.py and the CI shape that depends on it.

    python3 -m unittest discover -s scripts/tests
"""

from __future__ import annotations

import importlib.util
import re
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

SCRIPTS = Path(__file__).resolve().parents[1]
REPO = SCRIPTS.parent


def _load(name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


ui_shards = _load("ui_shards")
update_branch_protection = _load("update_branch_protection")


class TestUIShards(unittest.TestCase):
    def test_every_test_class_has_a_timing(self) -> None:
        classes = ui_shards.test_classes(REPO / "AppUITests")
        self.assertEqual(ui_shards.problems(ui_shards.CLASS_SECONDS, classes), [])

    def test_assign_places_every_key_exactly_once(self) -> None:
        keys = sorted(ui_shards.CLASS_SECONDS)
        for count in range(1, 7):
            placed = [key for shard in ui_shards.assign(ui_shards.CLASS_SECONDS, count) for key in shard]
            self.assertEqual(sorted(placed), keys, f"count {count}")

    def test_assign_balances_longest_first(self) -> None:
        shards = ui_shards.assign({"a": 10, "b": 9, "c": 8, "d": 1}, 2)
        self.assertEqual(shards, [["a", "d"], ["b", "c"]])

    def test_problems_reports_each_kind_of_mistake(self) -> None:
        classes = {"AUITests": ["testOne", "testTwo"]}
        base = {"MagendaTests": 1}
        cases = {
            "no entry": ({**base}, "AUITests has no entry"),
            "both forms": (
                {**base, "MagendaUITests/AUITests": 5, "MagendaUITests/AUITests/testOne": 2},
                "AUITests has an entry for the class and for some of its methods",
            ),
            "some methods": (
                {**base, "MagendaUITests/AUITests/testOne": 2},
                "AUITests has entries for only some of its methods; missing: testTwo",
            ),
            "stale": (
                {**base, "MagendaUITests/AUITests": 5, "MagendaUITests/GoneUITests": 5},
                "MagendaUITests/GoneUITests is stale",
            ),
            "no hosted tests": ({"MagendaUITests/AUITests": 5}, "MagendaTests has no entry"),
        }
        for label, (seconds, expected) in cases.items():
            with self.subTest(label):
                found = ui_shards.problems(seconds, classes)
                self.assertTrue(any(line.startswith(expected) for line in found), found)
        self.assertEqual(ui_shards.problems({**base, "MagendaUITests/AUITests": 5}, classes), [])

    def test_test_classes_reads_swift_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "A.swift").write_text(
                "final class A: XCTestCase {\n    func testTwo() {}\n    func testOne() {}\n    func helper() {}\n}\n",
                encoding="utf-8",
            )
            (directory / "B.swift").write_text("class B: XCTestCase {\n    func testB() throws {}\n}\n", encoding="utf-8")
            (directory / "Support.swift").write_text("class Helper {\n    func helper() {}\n}\n", encoding="utf-8")
            self.assertEqual(ui_shards.test_classes(directory), {"A": ["testOne", "testTwo"], "B": ["testB"]})
            (directory / "C.swift").write_text("class C: XCTestCase {}\nclass D: XCTestCase {}\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "C.swift declares more than one XCTestCase"):
                ui_shards.test_classes(directory)

    def test_the_workflow_matrix_lists_every_shard(self) -> None:
        text = (REPO / ".github/workflows/tests.yml").read_text(encoding="utf-8")
        match = re.search(r"'\[([\d, ]+)\]'\) \}\}", text)
        self.assertIsNotNone(match)
        assert match
        listed = [int(number) for number in match.group(1).split(",")]
        self.assertEqual(listed, list(range(1, ui_shards.SHARD_COUNT + 1)))

    def test_select_accepts_the_hosted_tests_a_class_and_a_method(self) -> None:
        classes = {"AUITests": ["testOne", "testTwo"]}
        keys = ui_shards.select("MagendaTests, MagendaUITests/AUITests MagendaUITests/AUITests/testOne", classes)
        self.assertEqual(keys, ["MagendaTests", "MagendaUITests/AUITests", "MagendaUITests/AUITests/testOne"])

    def test_select_drops_duplicates_and_keeps_order(self) -> None:
        classes = {"AUITests": ["testOne", "testTwo"]}
        keys = ui_shards.select("MagendaUITests/AUITests/testTwo, MagendaTests MagendaUITests/AUITests/testTwo", classes)
        self.assertEqual(keys, ["MagendaUITests/AUITests/testTwo", "MagendaTests"])

    def test_select_rejects_unknown_tests(self) -> None:
        classes = {"AUITests": ["testOne", "testTwo"]}
        with self.assertRaises(ValueError) as caught:
            ui_shards.select("MagendaUITests/Nope, MagendaTests MagendaUITests/AUITests/testNope", classes)
        message = str(caught.exception)
        self.assertEqual(message, "unknown tests: MagendaUITests/Nope, MagendaUITests/AUITests/testNope")

    def test_select_rejects_an_empty_list(self) -> None:
        with self.assertRaises(ValueError):
            ui_shards.select(" , ", {"AUITests": ["testOne"]})

    def test_select_rejects_shell_words(self) -> None:
        for names in ("MagendaTests;rm", "$(id)"):
            with self.subTest(names):
                with self.assertRaises(ValueError):
                    ui_shards.select(names, {"AUITests": ["testOne"]})

    def test_select_rejects_the_warm_up_class(self) -> None:
        classes = {"WarmUpUITests": ["testTheAppAnswers"]}
        for names in ("MagendaUITests/WarmUpUITests", "MagendaUITests/WarmUpUITests/testTheAppAnswers"):
            with self.subTest(names):
                with self.assertRaises(ValueError):
                    ui_shards.select(names, classes)

    def test_the_warm_up_class_needs_no_timing(self) -> None:
        classes = {"AUITests": ["testOne"], ui_shards.WARM_UP_CLASS: ["testTheAppAnswers"]}
        seconds = {"MagendaTests": 1, "MagendaUITests/AUITests": 1}
        self.assertEqual(ui_shards.problems(seconds, classes), [])
        found = ui_shards.problems({**seconds, "MagendaUITests/WarmUpUITests": 1}, classes)
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].endswith("is stale: no such test"), found)

    def test_the_workflow_passes_only_through_the_environment(self) -> None:
        text = (REPO / ".github/workflows/tests.yml").read_text(encoding="utf-8")
        self.assertIn("ONLY: ${{ inputs.only }}", text)
        self.assertIn('--only "$ONLY"', text)
        self.assertEqual(text.count("inputs.only"), 2)

    def test_the_workflow_warms_up_before_each_test_run(self) -> None:
        text = (REPO / ".github/workflows/tests.yml").read_text(encoding="utf-8")
        needle = "-only-testing:MagendaUITests/WarmUpUITests"
        self.assertEqual(text.count(needle), 1)
        self.assertGreater(text.index(needle), text.index("name: Tests (100% pass rate required)"))
        self.assertEqual(len(re.findall(r"^\s+warm_up$", text, re.MULTILINE)), 2)

    def test_required_checks_are_the_shards(self) -> None:
        checks = update_branch_protection.REQUIRED_STATUS_CHECKS
        for number in range(1, ui_shards.SHARD_COUNT + 1):
            self.assertIn(f"ui (ipad, newest, {number})", checks)
        others = [c for c in checks if (c.startswith("ui (") or c.startswith("app (")) and not re.fullmatch(r"ui \(ipad, newest, \d+\)", c)]
        self.assertEqual(others, [])


if __name__ == "__main__":
    unittest.main()
