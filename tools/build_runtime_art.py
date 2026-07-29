"""Crop and downsample chroma-keyed source art for the browser renderer.

The source images in ``art/world`` stay untouched. Run the imagegen skill's
``remove_chroma_key.py`` helper first, then point this script at the resulting
RGBA directory. Pillow is only a build-time dependency; the game has no Python
package dependency at runtime.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def output_limit(name: str) -> int:
    if name.startswith("env_"):
        return 420
    if name.startswith("spr_"):
        return 300
    return 256


def convert(source: Path, destination: Path) -> tuple[int, int]:
    image = Image.open(source).convert("RGBA")
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError(f"{source} contains no visible pixels")

    cropped = image.crop(bounds)
    padding = max(6, round(max(cropped.size) * 0.025))
    padded = Image.new(
        "RGBA",
        (cropped.width + padding * 2, cropped.height + padding * 2),
        (0, 0, 0, 0),
    )
    padded.alpha_composite(cropped, (padding, padding))
    padded.thumbnail(
        (output_limit(source.stem), output_limit(source.stem)),
        Image.Resampling.LANCZOS,
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    padded.save(destination, "WEBP", lossless=True, method=6)
    return padded.size


def main() -> int:
    parser = argparse.ArgumentParser()
    root = Path(__file__).resolve().parents[1]
    parser.add_argument(
        "source",
        type=Path,
        nargs="?",
        default=root / "tmp" / "runtime-alpha",
        help="RGBA PNG source directory (default: tmp/runtime-alpha)",
    )
    parser.add_argument(
        "destination",
        type=Path,
        nargs="?",
        default=root / "art" / "runtime",
        help="runtime WebP directory (default: art/runtime)",
    )
    args = parser.parse_args()

    sources = sorted(args.source.glob("*.png"))
    if not sources:
        parser.error(f"no PNG files found in {args.source}")
    for source in sources:
        destination = args.destination / f"{source.stem}.webp"
        width, height = convert(source, destination)
        print(f"{source.name} -> {destination.name} ({width}x{height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
