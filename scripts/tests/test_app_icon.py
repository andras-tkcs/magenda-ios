"""scripts/make_app_icon.py: the committed icon is a valid, alpha-free PNG and matches the generator.

    python3 -m unittest discover -s scripts/tests
"""

from __future__ import annotations

import importlib.util
import json
import struct
import subprocess  # nosec B404  # runs the generator's --check with a fixed argv
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

SCRIPTS = Path(__file__).resolve().parents[1]
REPO_ROOT = SCRIPTS.parent
ICONSET = REPO_ROOT / "App/Assets.xcassets/AppIcon.appiconset"


def _load(name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


make_app_icon = _load("make_app_icon")


def _chunks(data: bytes) -> list[tuple[bytes, bytes]]:
    pos = len(b"\x89PNG\r\n\x1a\n")
    found = []
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        found.append((data[pos + 4 : pos + 8], data[pos + 8 : pos + 8 + length]))
        pos += 12 + length
    return found


class AppIconTests(unittest.TestCase):
    def setUp(self) -> None:
        self.data = (ICONSET / "AppIcon.png").read_bytes()

    def test_signature(self) -> None:
        self.assertTrue(self.data.startswith(b"\x89PNG\r\n\x1a\n"))

    def test_header_is_1024_rgb_without_alpha(self) -> None:
        kind, body = _chunks(self.data)[0]
        self.assertEqual(kind, b"IHDR")
        self.assertEqual(body, struct.pack(">IIBBBBB", 1024, 1024, 8, 2, 0, 0, 0))

    def test_only_critical_chunks(self) -> None:
        kinds = {kind for kind, _ in _chunks(self.data)}
        self.assertEqual(kinds, {b"IHDR", b"IDAT", b"IEND"})

    def test_generation_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            first = Path(tmp) / "a.png"
            second = Path(tmp) / "b.png"
            first.write_bytes(make_app_icon.png_bytes())
            second.write_bytes(make_app_icon.png_bytes())
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_check_passes_on_the_committed_file(self) -> None:
        result = subprocess.run(  # nosec B603
            [sys.executable, "scripts/make_app_icon.py", "--check"], cwd=REPO_ROOT, check=False
        )
        self.assertEqual(result.returncode, 0)

    def test_check_fails_on_a_stale_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stale = Path(tmp) / "AppIcon.png"
            stale.write_bytes(b"not a png")
            self.assertFalse(make_app_icon.is_current(stale))

    def test_contents_json_names_the_file(self) -> None:
        contents = json.loads((ICONSET / "Contents.json").read_text())
        self.assertEqual(contents["images"][0]["filename"], "AppIcon.png")


if __name__ == "__main__":
    unittest.main()
