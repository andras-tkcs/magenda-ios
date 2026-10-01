#!/usr/bin/env python3
"""Print what a release version means for the build: its channel, or its marketing version.

Release tags use `vX.Y.Z` for a stable release and `vX.Y.Z-alpha.N`, `vX.Y.Z-beta.N` or
`vX.Y.Z-rc.N` for a pre-release (docs/releasing.md). App Store Connect only accepts `X.Y.Z` as an
app's version (`CFBundleShortVersionString`), so a pre-release ships under the version it leads to,
and the build number tells the uploads apart. The workflows ask this script rather than carrying
their own copy of the parsing rule.

    python3 scripts/release_channel.py 1.2.0-rc.1               # -> rc
    python3 scripts/release_channel.py --marketing v1.2.0-rc.1  # -> 1.2.0
"""

from __future__ import annotations

import argparse
import re
import sys

_VERSION_RE = re.compile(r"^v?(\d+\.\d+\.\d+)(?:-(alpha|beta|rc)\.\d+)?$")


def _match(version: str) -> re.Match[str]:
    match = _VERSION_RE.match(version.strip())
    if not match:
        raise ValueError(
            f"{version!r} is not a release version (expected X.Y.Z, optionally -alpha.N/-beta.N/-rc.N)"
        )
    return match


def channel(version: str) -> str:
    """`stable`, `alpha`, `beta` or `rc`."""
    return _match(version).group(2) or "stable"


def marketing_version(version: str) -> str:
    """The `X.Y.Z` App Store Connect accepts, without the `v` or any pre-release suffix."""
    return _match(version).group(1)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("version")
    parser.add_argument("--marketing", action="store_true", help="print the marketing version instead")
    args = parser.parse_args(argv)
    try:
        print(marketing_version(args.version) if args.marketing else channel(args.version))
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
