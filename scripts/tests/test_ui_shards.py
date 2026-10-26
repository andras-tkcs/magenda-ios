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
        match = re.search(r"shard: \[([\d, ]+)\]", text)
        self.assertIsNotNone(match)
        assert match
        listed = [int(number) for number in match.group(1).split(",")]
        self.assertEqual(listed, list(range(1, ui_shards.SHARD_COUNT + 1)))

    def test_required_checks_are_the_shards(self) -> None:
        checks = update_branch_protection.REQUIRED_STATUS_CHECKS
        for number in range(1, ui_shards.SHARD_COUNT + 1):
            self.assertIn(f"ui (ipad, newest, {number})", checks)
        others = [c for c in checks if (c.startswith("ui (") or c.startswith("app (")) and not re.fullmatch(r"ui \(ipad, newest, \d+\)", c)]
        self.assertEqual(others, [])


if __name__ == "__main__":
    unittest.main()
