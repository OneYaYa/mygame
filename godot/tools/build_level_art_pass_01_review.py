"""Build LEVEL ART PASS 01 review views from real Godot Compatibility captures.

Detail views are crops from the unscaled 1152x648 gameplay screenshots and are
resized only by a 2x nearest-neighbour integer scale.
"""

from __future__ import annotations

import json
from pathlib import Path
from shutil import copyfile

from PIL import Image, ImageDraw, ImageFont


GODOT_ROOT = Path(__file__).resolve().parents[1]
REVIEW = GODOT_ROOT / "art_review" / "level_art_pass_01"
BEFORE = REVIEW / "before"
AFTER = REVIEW / "after"

MAPS = {
    "player-room": "07_player-room.png",
    "chapel-belfry": "12_chapel-belfry.png",
    "low-tide-cave": "16_low-tide-cave.png",
    "clock-basement": "17_clock-basement.png",
}

# Coordinates are in real 1152x648 Compatibility screenshots. Each detail is
# deliberately large enough to remain readable at normal scale before its 2x
# nearest-neighbour enlargement.
CROPS = {
    "before": {
        "player-room": {
            "core_visual_center": (520, 150, 880, 430),
            "main_function_cluster": (250, 180, 540, 470),
            "foreground_layer": (190, 360, 960, 565),
            "entrance_and_path": (300, 300, 850, 565),
        },
        "chapel-belfry": {
            "core_visual_center": (410, 170, 735, 485),
            "main_function_cluster": (670, 185, 970, 470),
            "foreground_layer": (150, 90, 1000, 280),
            "entrance_and_path": (150, 300, 590, 555),
        },
        "low-tide-cave": {
            "core_visual_center": (650, 180, 940, 455),
            "main_function_cluster": (370, 180, 710, 470),
            "foreground_layer": (115, 65, 1035, 225),
            "entrance_and_path": (115, 210, 620, 470),
        },
        "clock-basement": {
            "core_visual_center": (390, 230, 760, 535),
            "main_function_cluster": (240, 290, 530, 555),
            "foreground_layer": (125, 75, 1025, 240),
            "entrance_and_path": (360, 355, 790, 605),
        },
    },
    "after": {
        "player-room": {
            "core_visual_center": (650, 155, 925, 430),
            "main_function_cluster": (240, 175, 520, 505),
            "foreground_layer": (210, 430, 940, 590),
            "entrance_and_path": (420, 330, 735, 600),
        },
        "chapel-belfry": {
            "core_visual_center": (420, 175, 730, 505),
            "main_function_cluster": (760, 230, 1045, 525),
            "foreground_layer": (110, 75, 1040, 245),
            "entrance_and_path": (110, 300, 455, 575),
        },
        "low-tide-cave": {
            "core_visual_center": (695, 175, 1035, 430),
            "main_function_cluster": (295, 205, 730, 470),
            "foreground_layer": (120, 75, 1045, 220),
            "entrance_and_path": (70, 245, 520, 505),
        },
        "clock-basement": {
            "core_visual_center": (370, 200, 785, 525),
            "main_function_cluster": (160, 300, 505, 570),
            "foreground_layer": (145, 505, 1005, 630),
            "entrance_and_path": (350, 385, 800, 630),
        },
    },
}


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for candidate in (
        Path("C:/Windows/Fonts/segoeui.ttf"),
        Path("C:/Windows/Fonts/msyh.ttc"),
    ):
        if candidate.is_file():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def build_views(folder: Path, phase: str) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for map_id, numbered in MAPS.items():
        source_path = folder / numbered
        if not source_path.is_file():
            raise SystemExit(f"Missing real Godot capture: {source_path}")
        source = Image.open(source_path).convert("RGB")
        if source.size != (1152, 648):
            raise SystemExit(f"Unexpected capture size for {source_path}: {source.size}")
        copyfile(source_path, folder / f"{map_id}.png")
        copyfile(source_path, folder / f"{map_id}_full_scene.png")
        copyfile(source_path, folder / f"{map_id}_gameplay_camera.png")
        views = [
            f"{map_id}.png",
            f"{map_id}_full_scene.png",
            f"{map_id}_gameplay_camera.png",
        ]
        for view_name, rect in CROPS[phase][map_id].items():
            crop = source.crop(rect)
            enlarged = crop.resize((crop.width * 2, crop.height * 2), Image.Resampling.NEAREST)
            filename = f"{map_id}_{view_name}.png"
            enlarged.save(folder / filename, optimize=True)
            views.append(filename)
        entries.append({
            "map_id": map_id,
            "source": numbered,
            "source_size": list(source.size),
            "views": views,
            "detail_scale": 2,
            "detail_resampling": "nearest",
        })
    return entries


def comparison(map_id: str) -> str:
    before = Image.open(BEFORE / f"{map_id}.png").convert("RGB")
    after = Image.open(AFTER / f"{map_id}.png").convert("RGB")
    header = 44
    gutter = 8
    result = Image.new("RGB", (before.width * 2 + gutter, before.height + header), "#0d1719")
    result.paste(before, (0, header))
    result.paste(after, (before.width + gutter, header))
    draw = ImageDraw.Draw(result)
    draw.text((16, 10), f"BEFORE  ·  {map_id}", fill="#e5cf9d", font=font(20))
    draw.text((before.width + gutter + 16, 10), "AFTER  ·  LEVEL ART PASS 01", fill="#e5cf9d", font=font(20))
    filename = f"{map_id}_comparison.png"
    result.save(REVIEW / filename, optimize=True)
    return filename


def contact_sheet() -> str:
    thumb_size = (576, 324)
    label_h = 34
    gutter = 10
    width = thumb_size[0] * 2 + gutter * 3
    height = (thumb_size[1] + label_h + gutter) * 4 + gutter
    sheet = Image.new("RGB", (width, height), "#0b1416")
    draw = ImageDraw.Draw(sheet)
    title_font = font(16)
    for row, map_id in enumerate(MAPS):
        y = gutter + row * (thumb_size[1] + label_h + gutter)
        for column, (phase, folder) in enumerate((("BEFORE", BEFORE), ("AFTER", AFTER))):
            x = gutter + column * (thumb_size[0] + gutter)
            image = Image.open(folder / f"{map_id}.png").convert("RGB")
            thumb = image.resize(thumb_size, Image.Resampling.NEAREST)
            sheet.paste(thumb, (x, y + label_h))
            draw.text((x + 8, y + 6), f"{phase} · {map_id}", fill="#ead5a4", font=title_font)
    filename = "contact_sheet.png"
    sheet.save(REVIEW / filename, optimize=True)
    return filename


def main() -> None:
    before_entries = build_views(BEFORE, "before")
    after_entries = build_views(AFTER, "after")
    comparisons = [comparison(map_id) for map_id in MAPS]
    contact = contact_sheet()
    manifest = {
        "pass_id": "level_art_vertical_slice_pass_01",
        "real_capture_renderer": "Godot 4.6.3 OpenGL Compatibility",
        "capture_size": [1152, 648],
        "before": before_entries,
        "after": after_entries,
        "comparisons": comparisons,
        "contact_sheet": contact,
        "detail_policy": "crop real capture, then 2x nearest-neighbour only",
    }
    (REVIEW / "review_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"LEVEL ART PASS 01 review built: {len(MAPS)} maps, {len(comparisons)} comparisons, {contact}")


if __name__ == "__main__":
    main()
