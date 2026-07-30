#!/usr/bin/env python3
"""Build deterministic nearest-neighbour closeups and the P0 benchmark contact sheet."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


GODOT_ROOT = Path(__file__).resolve().parents[1]
REVIEW_ROOT = GODOT_ROOT / "art_review"
BEFORE = REVIEW_ROOT / "p0_batch_01_before"
AFTER = REVIEW_ROOT / "p0_batch_01_after"

CLOSEUPS = {
    "town_path_closeup.png": ("01_town.png", (330, 205, 780, 435), 2),
    "town_pond_closeup.png": ("01_town.png", (20, 425, 270, 645), 3),
    "harbor_shore_closeup.png": ("06_harbor.png", (535, 145, 735, 535), 2),
    "harbor_water_closeup.png": ("06_harbor.png", (640, 50, 1135, 300), 2),
    "inn_wall_corner_closeup.png": ("08_inn-lobby.png", (150, 80, 455, 245), 3),
    "inn_doorway_closeup.png": ("08_inn-lobby.png", (445, 420, 700, 635), 3),
}

MAPS = [
    ("town", "01_town.png"),
    ("harbor", "06_harbor.png"),
    ("inn-lobby", "08_inn-lobby.png"),
]


def nearest_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.resize(size, Image.Resampling.NEAREST)


def build_closeups() -> None:
    for output_name, (source_name, crop, scale) in CLOSEUPS.items():
        with Image.open(AFTER / source_name) as source:
            clipped = source.convert("RGBA").crop(crop)
            result = nearest_resize(clipped, (clipped.width * scale, clipped.height * scale))
            result.save(AFTER / output_name, optimize=True)


def build_contact_sheet() -> None:
    panel_size = (576, 324)
    header_height = 24
    sheet = Image.new("RGB", (panel_size[0] * 2, (panel_size[1] + header_height) * len(MAPS)), "#10191a")
    draw = ImageDraw.Draw(sheet)
    for row, (map_id, filename) in enumerate(MAPS):
        top = row * (panel_size[1] + header_height)
        draw.text((8, top + 6), f"{map_id} — BEFORE", fill="#ead7a7")
        draw.text((panel_size[0] + 8, top + 6), f"{map_id} — AFTER", fill="#ead7a7")
        with Image.open(BEFORE / filename) as before_image:
            before_panel = nearest_resize(before_image.convert("RGB"), panel_size)
        with Image.open(AFTER / filename) as after_image:
            after_panel = nearest_resize(after_image.convert("RGB"), panel_size)
        sheet.paste(before_panel, (0, top + header_height))
        sheet.paste(after_panel, (panel_size[0], top + header_height))
    sheet.save(REVIEW_ROOT / "p0_batch_01_contact_sheet.png", optimize=True)


def validate() -> None:
    required = [BEFORE / filename for _, filename in MAPS]
    required += [AFTER / filename for _, filename in MAPS]
    required += [AFTER / name for name in CLOSEUPS]
    required.append(REVIEW_ROOT / "p0_batch_01_contact_sheet.png")
    missing = [str(path.relative_to(GODOT_ROOT)) for path in required if not path.is_file()]
    if missing:
        raise SystemExit("Missing review image(s): " + ", ".join(missing))
    for path in required:
        with Image.open(path) as image:
            if image.width <= 0 or image.height <= 0:
                raise SystemExit(f"Invalid review image: {path}")
    print(f"P0 batch-one review images: {len(required)} files, nearest closeups verified")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--validate", action="store_true", help="Only validate existing review deliverables")
    args = parser.parse_args()
    if not args.validate:
        build_closeups()
        build_contact_sheet()
    validate()


if __name__ == "__main__":
    main()
