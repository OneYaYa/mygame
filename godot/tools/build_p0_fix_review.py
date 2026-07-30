"""Build exact-name P0 fix screenshots, nearest-neighbour crops, and contact sheet."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw


GODOT_ROOT = Path(__file__).resolve().parents[1]
ROOT = GODOT_ROOT / "art_review" / "p0_fix_batch"
BEFORE = ROOT / "before"
AFTER = ROOT / "after"

FULL = {
    "town": "01_town.png",
    "harbor": "06_harbor.png",
    "inn-lobby": "08_inn-lobby.png",
}

# Crop rectangles are in the real 1152x648 Compatibility-render screenshots.
# Every detail output is resized by exactly 2x using nearest-neighbour.
CROPS = {
    "town_road_material_hierarchy.png": ("town", (90, 160, 1080, 425)),
    "town_pond_fixed.png": ("town", (25, 405, 300, 640)),
    "town_bakery_platform.png": ("town", (80, 145, 290, 335)),
    "town_clock_platform.png": ("town", (435, 160, 715, 370)),
    "harbor_shallow_deep_fixed.png": ("harbor", (520, 45, 1000, 640)),
    "harbor_main_shore_fixed.png": ("harbor", (515, 45, 710, 640)),
    "harbor_lighthouse_island_fixed.png": ("harbor", (900, 45, 1150, 330)),
    "harbor_dock_entry_fixed.png": ("harbor", (470, 270, 780, 465)),
    "harbor_logistics_fixed.png": ("harbor", (35, 285, 525, 500)),
    "inn_reception_partition.png": ("inn-lobby", (700, 175, 855, 370)),
    "inn_staircase.png": ("inn-lobby", (790, 315, 925, 525)),
    "inn_main_door_fixed.png": ("inn-lobby", (505, 420, 650, 585)),
    "inn_wall_decor.png": ("inn-lobby", (550, 140, 825, 275)),
    "inn_table_chairs.png": ("inn-lobby", (430, 265, 620, 445)),
    "inn_full_room.png": ("inn-lobby", (155, 60, 1000, 585)),
}


def nearest(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.resize(size, Image.Resampling.NEAREST)


def build() -> dict[str, object]:
    AFTER.mkdir(parents=True, exist_ok=True)
    images: dict[str, Image.Image] = {}
    for map_id, gallery_name in FULL.items():
        source = AFTER / gallery_name
        target = AFTER / f"{map_id}.png"
        if not source.is_file():
            raise FileNotFoundError(source)
        shutil.copyfile(source, target)
        images[map_id] = Image.open(target).convert("RGB")

    details = []
    for output_name, (map_id, box) in CROPS.items():
        crop = images[map_id].crop(box)
        scaled = nearest(crop, (crop.width * 2, crop.height * 2))
        scaled.save(AFTER / output_name, optimize=True)
        details.append({"file": output_name, "map_id": map_id, "crop": list(box), "nearest_scale": 2})

    thumb_size = (576, 324)
    margin, header = 8, 26
    sheet = Image.new("RGB", (thumb_size[0] * 2 + margin * 3, (thumb_size[1] + header) * 3 + margin * 4), "#11191a")
    draw = ImageDraw.Draw(sheet)
    for row, map_id in enumerate(FULL):
        for column, phase in enumerate(("before", "after")):
            path = (BEFORE if phase == "before" else AFTER) / f"{map_id}.png"
            image = Image.open(path).convert("RGB")
            thumb = nearest(image, thumb_size)
            x = margin + column * (thumb_size[0] + margin)
            y = margin + row * (thumb_size[1] + header + margin)
            draw.text((x + 4, y + 5), f"{map_id} / {phase}", fill="#ead7a8")
            sheet.paste(thumb, (x, y + header))
    sheet.save(ROOT / "contact_sheet.png", optimize=True)

    report = {
        "full_screenshots": [f"after/{map_id}.png" for map_id in FULL],
        "detail_screenshots": details,
        "detail_sampling": "nearest_neighbour_integer_2x",
        "contact_sheet": "contact_sheet.png",
    }
    (ROOT / "review_manifest.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    result = build()
    print(f"P0 fix review built: {len(result['full_screenshots'])} full, {len(result['detail_screenshots'])} detail")
