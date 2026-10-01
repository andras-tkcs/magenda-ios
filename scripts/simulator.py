#!/usr/bin/env python3
"""Print an `xcodebuild -destination` for an installed iOS simulator.

Simulator names and runtimes change with every Xcode release and differ between runner images, so
nothing in this repository names a device. The workflows and `scripts/pre_release_check.py` ask
this script instead:

    python3 scripts/simulator.py                          # newest iOS, an iPhone -> id=<udid>
    python3 scripts/simulator.py --family ipad
    python3 scripts/simulator.py --runtime oldest         # oldest installed iOS >= the deployment target

`--runtime oldest` is the compatibility layer's lower bound (docs/testing-policy.md). When the
deployment target's own runtime is not installed, it uses the oldest one above it and says so on
stderr; it never picks a runtime below the deployment target.

The device and runtime chosen are printed to stderr, so a CI log shows what was tested.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess  # nosec B404  # fixed xcrun argv only
import sys
from pathlib import Path

PROJECT_YML = Path(__file__).resolve().parent.parent / "project.yml"
_RUNTIME_RE = re.compile(r"SimRuntime\.iOS-(\d+)-(\d+)$")
_DEPLOYMENT_RE = re.compile(r'^\s+iOS:\s*"?(\d+)\.(\d+)"?\s*$', re.MULTILINE)
_FAMILIES = {"iphone": "iPhone", "ipad": "iPad"}


class NoSimulator(Exception):
    """No installed simulator matches. Printed without a traceback."""


def deployment_target(project_yml: str) -> tuple[int, int]:
    """The `deploymentTarget: iOS:` version in project.yml."""
    match = _DEPLOYMENT_RE.search(project_yml)
    if not match:
        raise NoSimulator("project.yml has no `deploymentTarget: iOS:` version")
    return int(match.group(1)), int(match.group(2))


def choose(devices: dict, *, family: str, runtime: str, minimum: tuple[int, int]) -> tuple[dict, tuple[int, int]]:
    """The device to test on and its iOS version, from `simctl list devices available -j`'s `devices`."""
    prefix = _FAMILIES[family]
    candidates: list[tuple[tuple[int, int], dict]] = []
    for key, entries in devices.items():
        match = _RUNTIME_RE.search(key)
        if not match:
            continue  # watchOS, tvOS, visionOS
        version = (int(match.group(1)), int(match.group(2)))
        if version < minimum:
            continue
        for device in entries:
            if device.get("isAvailable", True) and device["name"].startswith(prefix):
                candidates.append((version, device))
                break  # simctl lists device types in a stable order; the first is enough
    if not candidates:
        wanted = ".".join(map(str, minimum))
        raise NoSimulator(f"no available {prefix} simulator on iOS {wanted} or newer is installed")
    pick = min if runtime == "oldest" else max
    version, device = pick(candidates, key=lambda candidate: candidate[0])
    return device, version


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--family", choices=sorted(_FAMILIES), default="iphone")
    parser.add_argument("--runtime", choices=["newest", "oldest"], default="newest")
    parser.add_argument("--devices-json", type=Path, help="read `simctl list devices available -j` output from a file")
    args = parser.parse_args(argv)

    try:
        minimum = deployment_target(PROJECT_YML.read_text(encoding="utf-8"))
        if args.devices_json:
            listing = args.devices_json.read_text(encoding="utf-8")
        else:
            listing = subprocess.run(  # nosec B603 B607
                ["xcrun", "simctl", "list", "devices", "available", "-j"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        device, version = choose(json.loads(listing)["devices"], family=args.family, runtime=args.runtime, minimum=minimum)
    except NoSimulator as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"error: cannot list simulators (this needs macOS with Xcode): {exc}", file=sys.stderr)
        return 1

    shown = ".".join(map(str, version))
    print(f"Testing on {device['name']}, iOS {shown}", file=sys.stderr)
    if args.runtime == "oldest" and version != minimum:
        target = ".".join(map(str, minimum))
        print(f"note: iOS {target} (the deployment target) is not installed; iOS {shown} is the oldest that is", file=sys.stderr)
    print(f"id={device['udid']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
