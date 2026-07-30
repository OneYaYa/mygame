#!/usr/bin/env python3
"""Build deterministic P0 benchmark comparison images from real Godot captures."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFont


GODOT_ROOT = Path(__file__).resolve().parents[1]
REVIEW_ROOT = GODOT_ROOT / "art_review" / "p0_visual_impact"
BEFORE = REVIEW_ROOT / "before"
AFTER = REVIEW_ROOT / "after"
DIFF = REVIEW_ROOT / "diff"
HUD_HEIGHT = 50
PIXEL_DELTA_THRESHOLD = 24
RGB_DELTA_SUM_THRESHOLD = 42
IMPACT_BLOCK_SIZE = 8
IMPACT_MODERATE_MAX_THRESHOLD = 10
IMPACT_MODERATE_SUM_THRESHOLD = 22
IMPACT_MIN_MODERATE_RATIO = 0.20
IMPACT_MIN_MEAN_MAX_DELTA = 7.0

MAPS = {
    "town": "01_town.png",
    "harbor": "06_harbor.png",
    "inn-lobby": "08_inn-lobby.png",
}

CLOSEUPS = {
    "town_clock_plaza.png": ("town", (400, 155, 740, 430), 2),
    "town_road_edge.png": ("town", (145, 300, 510, 430), 2),
    "town_pond.png": ("town", (15, 405, 305, 648), 2),
    "town_bakery_entrance.png": ("town", (65, 80, 315, 305), 2),
    "harbor_main_shore.png": ("harbor", (530, 55, 700, 590), 2),
    "harbor_dock_connection.png": ("harbor", (520, 285, 810, 470), 2),
    "harbor_lighthouse_island.png": ("harbor", (935, 50, 1135, 300), 2),
    "harbor_water_transition.png": ("harbor", (575, 55, 770, 280), 2),
    "harbor_logistics_area.png": ("harbor", (25, 285, 510, 485), 2),
    "inn_full_room_shell.png": ("inn-lobby", (150, 55, 1000, 590), 2),
    "inn_main_door.png": ("inn-lobby", (485, 415, 665, 590), 3),
    "inn_reception.png": ("inn-lobby", (580, 145, 845, 365), 2),
    "inn_fireplace_area.png": ("inn-lobby", (245, 135, 475, 390), 2),
    "inn_stair_connection.png": ("inn-lobby", (735, 145, 940, 480), 2),
}


def open_capture(folder: Path, map_id: str) -> Image.Image:
    path = folder / MAPS[map_id]
    if not path.is_file():
        raise SystemExit(f"Missing real Godot capture: {path}")
    return Image.open(path).convert("RGBA")


def normalized_exports() -> None:
    """Provide the user-requested unnumbered names without deleting gallery output."""
    for map_id in MAPS:
        for folder in (BEFORE, AFTER):
            image = open_capture(folder, map_id)
            image.save(folder / f"{map_id}.png", optimize=True)


def build_diff(map_id: str) -> dict[str, float | int | str]:
    before = open_capture(BEFORE, map_id)
    after = open_capture(AFTER, map_id)
    if before.size != after.size:
        raise SystemExit(f"Capture size mismatch for {map_id}: {before.size} != {after.size}")
    width, height = before.size
    raw = ImageChops.difference(before.convert("RGB"), after.convert("RGB"))
    raw_pixels = raw.load()
    changed = Image.new("L", (width, height), 0)
    mask_pixels = changed.load()
    changed_count = 0
    for y in range(HUD_HEIGHT, height):
        for x in range(width):
            red, green, blue = raw_pixels[x, y]
            if max(red, green, blue) >= PIXEL_DELTA_THRESHOLD and red + green + blue >= RGB_DELTA_SUM_THRESHOLD:
                mask_pixels[x, y] = 255
                changed_count += 1

    impact = Image.new("L", (width, height), 0)
    impact_pixels = impact.load()
    impact_count = 0
    for top in range(HUD_HEIGHT, height, IMPACT_BLOCK_SIZE):
        bottom = min(height, top + IMPACT_BLOCK_SIZE)
        for left in range(0, width, IMPACT_BLOCK_SIZE):
            right = min(width, left + IMPACT_BLOCK_SIZE)
            pixel_count = (right - left) * (bottom - top)
            moderate_count = 0
            max_delta_sum = 0
            for y in range(top, bottom):
                for x in range(left, right):
                    red, green, blue = raw_pixels[x, y]
                    maximum = max(red, green, blue)
                    max_delta_sum += maximum
                    if maximum >= IMPACT_MODERATE_MAX_THRESHOLD and red + green + blue >= IMPACT_MODERATE_SUM_THRESHOLD:
                        moderate_count += 1
            moderate_ratio = moderate_count / pixel_count
            mean_max_delta = max_delta_sum / pixel_count
            if moderate_ratio >= IMPACT_MIN_MODERATE_RATIO and mean_max_delta >= IMPACT_MIN_MEAN_MAX_DELTA:
                for y in range(top, bottom):
                    for x in range(left, right):
                        impact_pixels[x, y] = 255
                impact_count += pixel_count

    scene_pixels = width * (height - HUD_HEIGHT)
    strict_coverage = changed_count / scene_pixels if scene_pixels else 0.0
    impact_coverage = impact_count / scene_pixels if scene_pixels else 0.0
    muted = ImageEnhance.Brightness(before.convert("RGB")).enhance(0.28).convert("RGBA")
    accent = Image.new("RGBA", (width, height), (235, 76, 116, 218))
    muted.alpha_composite(Image.composite(accent, Image.new("RGBA", (width, height)), impact))
    draw = ImageDraw.Draw(muted)
    draw.rectangle((0, 0, width - 1, HUD_HEIGHT - 1), fill=(18, 27, 29, 255))
    label = f"{map_id}  semantic impact: {impact_coverage * 100:.2f}%  strict pixels: {strict_coverage * 100:.2f}%"
    draw.rectangle((8, 8, min(width - 8, 8 + len(label) * 8), 36), fill=(18, 27, 29, 235), outline=(206, 163, 92, 255))
    draw.text((15, 15), label, font=ImageFont.load_default(), fill=(246, 232, 201, 255))
    output = DIFF / f"{map_id}_diff.png"
    muted.save(output, optimize=True)
    return {
        "map_id": map_id,
        "width": width,
        "height": height,
        "hud_excluded_rows": HUD_HEIGHT,
        "delta_max_threshold": PIXEL_DELTA_THRESHOLD,
        "delta_rgb_sum_threshold": RGB_DELTA_SUM_THRESHOLD,
        "strict_changed_pixels": changed_count,
        "strict_coverage_percent": round(strict_coverage * 100.0, 3),
        "impact_block_size": IMPACT_BLOCK_SIZE,
        "impact_changed_pixels": impact_count,
        "scene_pixels": scene_pixels,
        "coverage_percent": round(impact_coverage * 100.0, 3),
        "diff_file": output.relative_to(GODOT_ROOT).as_posix(),
    }


def build_closeups() -> None:
    for filename, (map_id, box, scale) in CLOSEUPS.items():
        source = open_capture(AFTER, map_id)
        crop = source.crop(box)
        crop = crop.resize((crop.width * scale, crop.height * scale), Image.Resampling.NEAREST)
        crop.save(AFTER / filename, optimize=True)


def build_contact_sheet(metrics: list[dict[str, float | int | str]]) -> None:
    cell_width, cell_height = 560, 315
    sheet = Image.new("RGB", (cell_width * 2, cell_height * len(metrics)), (19, 27, 29))
    draw = ImageDraw.Draw(sheet)
    for row, metric in enumerate(metrics):
        map_id = str(metric["map_id"])
        for column, folder in enumerate((BEFORE, AFTER)):
            image = open_capture(folder, map_id).convert("RGB")
            image.thumbnail((cell_width, cell_height - 24), Image.Resampling.NEAREST)
            x = column * cell_width + (cell_width - image.width) // 2
            y = row * cell_height + 24
            sheet.paste(image, (x, y))
        label = f"{map_id}: BEFORE / AFTER   impact {metric['coverage_percent']:.3f}% / strict {metric['strict_coverage_percent']:.3f}%"
        draw.text((8, row * cell_height + 7), label, font=ImageFont.load_default(), fill=(235, 219, 183))
    sheet.save(REVIEW_ROOT / "contact_sheet.png", optimize=True)


def main() -> None:
    DIFF.mkdir(parents=True, exist_ok=True)
    normalized_exports()
    metrics = [build_diff(map_id) for map_id in MAPS]
    build_closeups()
    build_contact_sheet(metrics)
    (DIFF / "impact_metrics.json").write_text(json.dumps({"maps": metrics}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for metric in metrics:
        print(f"{metric['map_id']}: {metric['coverage_percent']:.3f}%")


if __name__ == "__main__":
    main()
