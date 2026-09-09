#!/usr/bin/env python3
"""Centre-crops a picture to 16:9 and writes it at 800x450, the chooser card's own rectangle.

Uses CoreGraphics through PyObjC-free `sips` where it can, and falls back to nothing: the
arithmetic is small enough to do here rather than take a dependency on Pillow.
"""
import subprocess
import sys

TARGET_W, TARGET_H = 800, 450


def size(path: str) -> tuple[int, int]:
    out = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
        check=True, capture_output=True, text=True).stdout
    values = {}
    for line in out.splitlines():
        if ":" in line:
            key, _, value = line.strip().partition(":")
            values[key.strip()] = value.strip()
    return int(values["pixelWidth"]), int(values["pixelHeight"])


def main() -> int:
    source, destination = sys.argv[1], sys.argv[2]
    width, height = size(source)
    # Scale so the picture covers the target, then crop the overflow off both edges.
    scale = max(TARGET_W / width, TARGET_H / height)
    subprocess.run(
        ["sips", "-z", str(round(height * scale)), str(round(width * scale)),
         source, "--out", destination], check=True, capture_output=True)
    subprocess.run(
        ["sips", "-c", str(TARGET_H), str(TARGET_W), destination], check=True,
        capture_output=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
