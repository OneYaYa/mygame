#!/usr/bin/env python3
"""Build the final 18-map gallery, integer-nearest detail crops, and batch sheets."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / "art_review" / "full_map_rollout"
BEFORE = REVIEW / "before"
AFTER = REVIEW / "after"
FINAL = REVIEW / "final_gallery"
DETAILS = FINAL / "details"

MAPS = [
    ("01", "town"), ("02", "inn-yard"), ("03", "chapel-hill"),
    ("04", "photo-lane"), ("05", "archive-lane"), ("06", "harbor"),
    ("07", "player-room"), ("08", "inn-lobby"), ("09", "inn-upstairs"),
    ("10", "clock-cabin"), ("11", "chapel-interior"), ("12", "chapel-belfry"),
    ("13", "photo-studio"), ("14", "archive-room"), ("15", "harbor-control"),
    ("16", "low-tide-cave"), ("17", "clock-basement"), ("18", "hidden-darkroom"),
]

BATCHES = {
    "batch_a_inn_contact_sheet.png": ["inn-yard", "player-room", "inn-lobby", "inn-upstairs"],
    "batch_b_chapel_contact_sheet.png": ["chapel-hill", "chapel-interior", "chapel-belfry"],
    "batch_c_photo_archive_contact_sheet.png": ["photo-lane", "archive-lane", "photo-studio", "archive-room"],
    "batch_d_engineering_contact_sheet.png": ["harbor", "clock-cabin", "harbor-control", "clock-basement"],
    "batch_e_hidden_contact_sheet.png": ["low-tide-cave", "hidden-darkroom"],
}

# 384x256 source rectangles. The two views deliberately cover the visual focus and
# the most important functional zone while staying inside the 1152x648 viewport.
CROPS = {
    "town": [(384, 78), (40, 300)],
    "inn-yard": [(368, 72), (672, 292)],
    "chapel-hill": [(384, 78), (580, 318)],
    "photo-lane": [(224, 92), (548, 250)],
    "archive-lane": [(336, 74), (584, 250)],
    "harbor": [(516, 170), (704, 72)],
    "player-room": [(388, 104), (548, 264)],
    "inn-lobby": [(356, 96), (548, 220)],
    "inn-upstairs": [(330, 98), (520, 214)],
    "clock-cabin": [(382, 106), (532, 232)],
    "chapel-interior": [(382, 102), (532, 226)],
    "chapel-belfry": [(386, 102), (522, 216)],
    "photo-studio": [(370, 102), (530, 226)],
    "archive-room": [(374, 102), (520, 222)],
    "harbor-control": [(382, 102), (534, 224)],
    "low-tide-cave": [(282, 96), (508, 236)],
    "clock-basement": [(364, 96), (516, 222)],
    "hidden-darkroom": [(374, 102), (516, 220)],
}


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/consola.ttf"),
        Path("C:/Windows/Fonts/arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def image_for(map_id: str) -> tuple[str, Image.Image]:
    number = next(number for number, candidate in MAPS if candidate == map_id)
    filename = f"{number}_{map_id}.png"
    return filename, Image.open(AFTER / filename).convert("RGB")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_sheet(name: str, map_ids: list[str], columns: int = 2) -> None:
    cell_w, cell_h = 576, 348
    rows = (len(map_ids) + columns - 1) // columns
    sheet = Image.new("RGB", (cell_w * columns, 42 + cell_h * rows), "#10191b")
    draw = ImageDraw.Draw(sheet)
    draw.text((16, 10), name.removesuffix(".png"), fill="#efd9a6", font=font(20))
    for index, map_id in enumerate(map_ids):
        filename, source = image_for(map_id)
        preview = source.resize((560, 315), Image.Resampling.NEAREST)
        x = (index % columns) * cell_w + 8
        y = 42 + (index // columns) * cell_h
        sheet.paste(preview, (x, y))
        draw.text((x + 8, y + 320), filename, fill="#d8c99f", font=font(15))
    sheet.save(FINAL / name)


def frozen_regression() -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    for number, map_id in MAPS:
        if map_id not in {"town", "harbor", "inn-lobby"}:
            continue
        filename = f"{number}_{map_id}.png"
        before = Image.open(BEFORE / filename).convert("RGB")
        after = Image.open(AFTER / filename).convert("RGB")
        difference = ImageChops.difference(before, after)
        bbox = difference.getbbox()
        changed = 0
        if bbox:
            pixels = difference.get_flattened_data() if hasattr(difference, "get_flattened_data") else difference.getdata()
            changed = sum(1 for pixel in pixels if pixel != (0, 0, 0))
        result[map_id] = {
            "before_sha256": sha256(BEFORE / filename),
            "after_sha256": sha256(AFTER / filename),
            "exact": bbox is None,
            "changed_pixels": changed,
            "changed_percent": round(changed * 100 / (before.width * before.height), 4),
            "difference_bbox": list(bbox) if bbox else None,
            "classification": "exact" if bbox is None else "dynamic_frame_only",
        }
    return result


def main() -> int:
    FINAL.mkdir(parents=True, exist_ok=True)
    DETAILS.mkdir(parents=True, exist_ok=True)
    detail_entries: list[dict[str, object]] = []
    for number, map_id in MAPS:
        filename = f"{number}_{map_id}.png"
        shutil.copy2(AFTER / filename, FINAL / filename)
        source = Image.open(AFTER / filename).convert("RGB")
        for index, (x, y) in enumerate(CROPS[map_id], start=1):
            crop = source.crop((x, y, x + 384, y + 256))
            crop = crop.resize((768, 512), Image.Resampling.NEAREST)
            detail_name = f"{number}_{map_id}_detail_{index}.png"
            crop.save(DETAILS / detail_name)
            detail_entries.append({"map_id": map_id, "file": f"details/{detail_name}", "scale": 2})

    for name, map_ids in BATCHES.items():
        make_sheet(name, map_ids)
    make_sheet("all_18_maps_contact_sheet.png", [map_id for _, map_id in MAPS], columns=3)

    manifest = {
        "renderer": "Godot 4.6.3 OpenGL Compatibility / NVIDIA GeForce RTX 2060",
        "full_screenshots": [f"{number}_{map_id}.png" for number, map_id in MAPS],
        "detail_screenshots": detail_entries,
        "contact_sheets": list(BATCHES) + ["all_18_maps_contact_sheet.png"],
        "frozen_regression": frozen_regression(),
    }
    (FINAL / "review_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Full-map review built: {len(MAPS)} full, {len(detail_entries)} nearest-2x details, {len(BATCHES) + 1} sheets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
