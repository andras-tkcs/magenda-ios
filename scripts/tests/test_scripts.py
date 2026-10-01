"""scripts/: the release, coverage and simulator helpers.

These scripts guard a release against failures that are silent otherwise (notes missing from a
green build, a skipped version, coverage quietly dropping, a test run on the wrong simulator), so
their refusals are tested as carefully as their happy paths. Stdlib `unittest` only, so they run
anywhere `python3` does, with nothing installed.

    python3 -m unittest discover -s scripts/tests
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]


def _load(name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


changelog_section = _load("changelog_section")
tag_release = _load("tag_release")
release_channel = _load("release_channel")
check_coverage_floor = _load("check_coverage_floor")
simulator = _load("simulator")

CHANGELOG = """# Changelog

<!-- ## [Unreleased] quoted inside a comment must not count -->

## [Unreleased]

## [1.1.0] — 2026-02-01

### Added

- Something.

## [1.0.0] — 2026-01-01

- First.
"""


def _quiet() -> contextlib.ExitStack:
    stack = contextlib.ExitStack()
    stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
    stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
    return stack


class TestChangelogSection(unittest.TestCase):
    def test_returns_the_body_without_its_heading(self) -> None:
        self.assertEqual(changelog_section.section(CHANGELOG, "1.1.0"), "### Added\n\n- Something.")

    def test_tolerates_a_leading_v(self) -> None:
        self.assertEqual(changelog_section.section(CHANGELOG, "v1.0.0"), "- First.")

    def test_missing_section_raises(self) -> None:
        with self.assertRaisesRegex(LookupError, "no section"):
            changelog_section.section(CHANGELOG, "9.9.9")

    def test_duplicated_section_raises(self) -> None:
        """A section opened early plus a renamed [Unreleased] would ship only the first half."""
        doubled = CHANGELOG + "\n## [1.1.0] — 2026-02-02\n\n- Other half.\n"
        with self.assertRaisesRegex(LookupError, "2 headings"):
            changelog_section.section(doubled, "1.1.0")

    def test_populated_unreleased_fails_the_cli(self) -> None:
        """Entries stranded in [Unreleased] would be missing from the release notes."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "CHANGELOG.md"
            path.write_text(CHANGELOG.replace("## [Unreleased]\n", "## [Unreleased]\n\n- Pending.\n"), encoding="utf-8")
            with _quiet():
                self.assertEqual(changelog_section.main(["1.1.0", "--changelog", str(path)]), 1)
                self.assertEqual(changelog_section.main(["1.1.0", "--changelog", str(path), "--allow-unreleased"]), 0)


class TestTagSequence(unittest.TestCase):
    def _known(self, *tags: str) -> list:
        return [tag_release._parse_existing_tag(tag) for tag in tags]

    def _check(self, version: str, *tags: str) -> None:
        tag_release.check_sequential(tag_release.parse_version(version), self._known(*tags))

    def test_tag_names_use_the_semver_prerelease_form(self) -> None:
        self.assertEqual(tag_release.tag_name(tag_release.parse_version("1.2.0-beta.3")), "v1.2.0-beta.3")
        self.assertEqual(tag_release.tag_name(tag_release.parse_version("v1.2.0")), "v1.2.0")

    def test_first_prerelease_of_a_line_is_1(self) -> None:
        self._check("1.1.0-alpha.1", "v1.0.0")

    def test_skipped_prerelease_number_is_refused(self) -> None:
        with self.assertRaisesRegex(tag_release.TagError, "must be alpha.2"):
            self._check("1.1.0-alpha.3", "v1.0.0", "v1.1.0-alpha.1")

    def test_skipped_version_is_refused(self) -> None:
        with self.assertRaisesRegex(tag_release.TagError, "no version may be skipped"):
            self._check("1.2.0", "v1.0.0")

    def test_stable_after_its_prereleases_is_allowed(self) -> None:
        self._check("1.1.0", "v1.0.0", "v1.1.0-rc.1")

    def test_retagging_a_stable_version_is_refused(self) -> None:
        with self.assertRaisesRegex(tag_release.TagError, "already tagged"):
            self._check("1.0.0", "v1.0.0")

    def test_non_canonical_versions_are_refused(self) -> None:
        for bad in ["1.0", "1.0.0-beta1", "1.0.0b1", "v1.0.0.1", "latest"]:
            with self.subTest(bad=bad), self.assertRaises(tag_release.TagError):
                tag_release.parse_version(bad)


class TestReleaseChannel(unittest.TestCase):
    def test_channel(self) -> None:
        cases = {"1.2.0": "stable", "v1.2.0": "stable", "1.2.0-alpha.1": "alpha", "1.2.0-beta.2": "beta", "1.2.0-rc.1": "rc"}
        for version, expected in cases.items():
            with self.subTest(version=version):
                self.assertEqual(release_channel.channel(version), expected)

    def test_marketing_version_drops_the_prerelease_suffix(self) -> None:
        """App Store Connect accepts only X.Y.Z as an app's version."""
        self.assertEqual(release_channel.marketing_version("v1.2.0-rc.1"), "1.2.0")

    def test_garbage_is_an_error(self) -> None:
        with _quiet():
            self.assertEqual(release_channel.main(["1.2"]), 1)


class TestCoverageFloor(unittest.TestCase):
    def _report(self, files: dict[str, tuple[int, int]]) -> dict:
        return {
            "data": [
                {
                    "files": [
                        {"filename": name, "summary": {"lines": {"count": count, "covered": covered}}}
                        for name, (covered, count) in files.items()
                    ]
                }
            ]
        }

    def _check(self, report: dict, overall: float, modules: dict[str, float]) -> list[str]:
        with mock.patch.object(check_coverage_floor, "OVERALL_FLOOR", overall), mock.patch.object(
            check_coverage_floor, "MODULE_FLOORS", modules
        ), _quiet():
            return check_coverage_floor.check(report)

    def test_only_appcore_sources_count(self) -> None:
        """Test files and anything outside AppCore/Sources must not dilute or inflate the number."""
        report = self._report(
            {
                "/work/repo/AppCore/Sources/A.swift": (10, 10),
                "/work/repo/AppCore/Tests/ATests.swift": (0, 50),
                "/work/repo/AppCore/.build/checkouts/dep/B.swift": (0, 50),
            }
        )
        self.assertEqual(self._check(report, 100.0, {"AppCore/Sources/A.swift": 100.0}), [])

    def test_fails_below_a_file_floor(self) -> None:
        report = self._report({"/r/AppCore/Sources/A.swift": (9, 10), "/r/AppCore/Sources/B.swift": (90, 90)})
        self.assertTrue(self._check(report, 0.0, {"AppCore/Sources/A.swift": 95.0}))

    def test_fails_below_the_overall_floor(self) -> None:
        report = self._report({"/r/AppCore/Sources/A.swift": (1, 2)})
        self.assertTrue(self._check(report, 60.0, {}))

    def test_a_file_missing_from_the_report_fails(self) -> None:
        """A renamed file would otherwise keep a floor that protects nothing."""
        report = self._report({"/r/AppCore/Sources/A.swift": (1, 1)})
        self.assertTrue(self._check(report, 0.0, {"AppCore/Sources/Gone.swift": 50.0}))

    def test_a_report_without_appcore_fails(self) -> None:
        self.assertTrue(self._check(self._report({"/r/Other.swift": (1, 1)}), 0.0, {}))


class TestSimulator(unittest.TestCase):
    DEVICES = {
        "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [{"name": "iPhone 15", "udid": "OLD"}],
        "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
            {"name": "iPhone 16", "udid": "MID-PHONE"},
            {"name": "iPad Air 11-inch (M2)", "udid": "MID-PAD"},
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
            {"name": "iPhone 17", "udid": "NEW-PHONE", "isAvailable": True},
            {"name": "iPad Pro 13-inch (M4)", "udid": "NEW-PAD"},
        ],
        "com.apple.CoreSimulator.SimRuntime.watchOS-11-0": [{"name": "iPhone-shaped watch", "udid": "WATCH"}],
    }

    def _udid(self, **kwargs: str) -> str:
        device, _ = simulator.choose(self.DEVICES, minimum=(18, 0), **kwargs)
        return device["udid"]

    def test_newest_iphone_by_default(self) -> None:
        self.assertEqual(self._udid(family="iphone", runtime="newest"), "NEW-PHONE")

    def test_ipad_family(self) -> None:
        self.assertEqual(self._udid(family="ipad", runtime="newest"), "NEW-PAD")

    def test_oldest_never_goes_below_the_deployment_target(self) -> None:
        """iOS 17.5 is installed but below the target, so testing on it would prove nothing."""
        self.assertEqual(self._udid(family="iphone", runtime="oldest"), "MID-PHONE")

    def test_unavailable_devices_are_skipped(self) -> None:
        devices = {"com.apple.CoreSimulator.SimRuntime.iOS-18-0": [{"name": "iPhone 16", "udid": "X", "isAvailable": False}]}
        with self.assertRaises(simulator.NoSimulator):
            simulator.choose(devices, family="iphone", runtime="newest", minimum=(18, 0))

    def test_deployment_target_is_read_from_project_yml(self) -> None:
        text = (SCRIPTS.parent / "project.yml").read_text(encoding="utf-8")
        self.assertGreaterEqual(simulator.deployment_target(text), (13, 0))


if __name__ == "__main__":
    unittest.main()
