#!/usr/bin/env python3
"""Generate the app icon: a 1024x1024 RGB PNG without an alpha channel.

App Store Connect rejects an icon with transparency, and nothing else here needs an image
library, so the PNG is written by hand with the standard library.

    python3 scripts/make_app_icon.py           # (re)write AppIcon.png
    python3 scripts/make_app_icon.py --check   # exit 1 if the committed file is out of date

`--check` compares the decoded pixels and the header, not the file bytes, because the compressed
bytes differ between zlib builds.
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024
SIGNATURE = b"\x89PNG\r\n\x1a\n"
ICON_PATH = Path(__file__).resolve().parents[1] / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

BACKGROUND = (0x08, 0x30, 0x50)
PAGE = (0xFF, 0xFF, 0xFF)
HEADER = (0xBF, 0x4E, 0x14)
RULE = (0x21, 0x5E, 0x99)

# (x0, x1, y0, y1, colour), all inclusive, painted in order.
SHAPES = [
    (272, 751, 176, 847, PAGE),
    (272, 751, 176, 255, HEADER),
    *[(336, 687, y, y + 11, RULE) for y in (320, 416, 512, 608, 704)],
]


def ihdr_data() -> bytes:
    return struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)


def scanlines() -> bytes:
    rows = []
    for y in range(SIZE):
        row = [BACKGROUND] * SIZE
        for x0, x1, y0, y1, colour in SHAPES:
            if y0 <= y <= y1:
                row[x0 : x1 + 1] = [colour] * (x1 - x0 + 1)
        rows.append(b"\x00" + b"".join(bytes(pixel) for pixel in row))
    return b"".join(rows)


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def png_bytes() -> bytes:
    return (
        SIGNATURE
        + chunk(b"IHDR", ihdr_data())
        + chunk(b"IDAT", zlib.compress(scanlines(), 9))
        + chunk(b"IEND", b"")
    )


def parse(data: bytes) -> tuple[bytes, bytes]:
    """Return the IHDR data and the inflated IDAT stream of a PNG."""
    if not data.startswith(SIGNATURE):
        raise ValueError("not a PNG")
    pos = len(SIGNATURE)
    header = b""
    idat = b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            header = body
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    return header, zlib.decompress(idat)


def is_current(path: Path) -> bool:
    try:
        return parse(path.read_bytes()) == (ihdr_data(), scanlines())
    except (OSError, ValueError, zlib.error, struct.error):
        return False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="verify the committed icon instead of writing it")
    args = parser.parse_args(argv)
    if args.check:
        if not is_current(ICON_PATH):
            print("AppIcon.png is out of date; run python3 scripts/make_app_icon.py", file=sys.stderr)
            return 1
        return 0
    ICON_PATH.write_bytes(png_bytes())
    return 0


if __name__ == "__main__":
    sys.exit(main())
