#!/usr/bin/env python3
"""Prepare the P0 benchmark-fix imagegen masters as production pixel sprites.

The image-generation masters remain untouched.  Chroma-cleaned copies are split
into semantic cells, hard-alpha trimmed, nearest-neighbour resized, palette
limited, and written to source_art/generated for the normal manifest processor.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw


GODOT_ROOT = Path(__file__).resolve().parents[1]
MASTER_ROOT = GODOT_ROOT / "assets" / "images" / "source_art" / "generated" / "masters"
ALPHA_ROOT = GODOT_ROOT / "assets" / "images" / "source_art" / "generated" / "alpha_clean"
SOURCE_ROOT = GODOT_ROOT / "assets" / "images" / "source_art" / "generated"
REPORT_PATH = SOURCE_ROOT / "p0_fix_processing_report.json"


@dataclass(frozen=True)
class SpriteSpec:
    asset_id: str
    master_id: str
    columns: int
    rows: int
    index: int
    size: tuple[int, int]
    palette_colors: int = 20
    padding: int = 1


SPECS = (
    SpriteSpec("inn_staircase", "inn_staircase", 1, 1, 0, (64, 112), 24, 1),
    SpriteSpec("inn_reception_partition", "inn_reception_partition", 1, 1, 0, (48, 56), 20, 1),
    SpriteSpec("inn_main_door_closed", "inn_main_door", 2, 1, 0, (48, 64), 22, 1),
    SpriteSpec("inn_main_door_open", "inn_main_door", 2, 1, 1, (48, 64), 22, 1),
    SpriteSpec("generic_table_small", "generic_table_set", 3, 1, 0, (48, 40), 20, 1),
    SpriteSpec("generic_table_dining", "generic_table_set", 3, 1, 1, (64, 48), 20, 1),
    SpriteSpec("generic_table_reading", "generic_table_set", 3, 1, 2, (64, 48), 22, 1),
    SpriteSpec("generic_chair_front", "generic_chair_set", 2, 2, 0, (24, 32), 18, 1),
    SpriteSpec("generic_chair_back", "generic_chair_set", 2, 2, 1, (24, 32), 18, 1),
    SpriteSpec("generic_chair_left", "generic_chair_set", 2, 2, 2, (24, 32), 18, 1),
    SpriteSpec("generic_chair_right", "generic_chair_set", 2, 2, 3, (24, 32), 18, 1),
    SpriteSpec("inn_wall_lake_painting", "inn_wall_decor_set", 5, 1, 0, (48, 32), 22, 0),
    SpriteSpec("inn_wall_town_photo", "inn_wall_decor_set", 5, 1, 1, (32, 24), 20, 0),
    SpriteSpec("inn_wall_license", "inn_wall_decor_set", 5, 1, 2, (24, 24), 14, 0),
    SpriteSpec("inn_key_board", "inn_wall_decor_set", 5, 1, 3, (48, 32), 18, 0),
    SpriteSpec("inn_notice_board_small", "inn_wall_decor_set", 5, 1, 4, (32, 24), 18, 0),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--validate", action="store_true")
    return parser.parse_args()


def harden_alpha(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    rgba.putalpha(rgba.getchannel("A").point(lambda value: 255 if value >= 112 else 0))
    return rgba


def crop_cell(image: Image.Image, spec: SpriteSpec) -> Image.Image:
    column = spec.index % spec.columns
    row = spec.index // spec.columns
    left = round(column * image.width / spec.columns)
    top = round(row * image.height / spec.rows)
    right = round((column + 1) * image.width / spec.columns)
    bottom = round((row + 1) * image.height / spec.rows)
    cell = harden_alpha(image.crop((left, top, right, bottom)))
    bbox = cell.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError(f"{spec.asset_id}: empty generated cell")
    return cell.crop(bbox)


def fit_nearest(content: Image.Image, spec: SpriteSpec) -> Image.Image:
    available = (max(1, spec.size[0] - spec.padding * 2), max(1, spec.size[1] - spec.padding * 2))
    ratio = min(available[0] / content.width, available[1] / content.height)
    size = max(1, round(content.width * ratio)), max(1, round(content.height * ratio))
    resized = content.resize(size, Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", spec.size, (0, 0, 0, 0))
    x = (spec.size[0] - size[0]) // 2
    y = spec.size[1] - spec.padding - size[1]
    canvas.alpha_composite(resized, (x, y))
    return canvas


def limit_palette(image: Image.Image, colors: int) -> Image.Image:
    rgba = harden_alpha(image)
    alpha = rgba.getchannel("A")
    rgb = Image.new("RGB", rgba.size, (0, 0, 0))
    rgb.paste(rgba.convert("RGB"), mask=alpha)
    result = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    result.putalpha(alpha)
    return result


def sanitize_abstract_paper(asset_id: str, image: Image.Image) -> Image.Image:
    """Replace generated pseudo-writing with deliberately abstract pixel marks."""
    if asset_id not in {"inn_wall_license", "inn_notice_board_small"}:
        return image
    result = image.copy()
    draw = ImageDraw.Draw(result)
    if asset_id == "inn_wall_license":
        draw.rectangle((2, 2, 21, 21), fill=(70, 45, 31, 255))
        draw.rectangle((4, 4, 19, 19), fill=(205, 177, 123, 255))
        for y, width in ((7, 9), (11, 11), (15, 7)):
            draw.rectangle((6, y, 5 + width, y + 1), fill=(119, 89, 57, 255))
        draw.rectangle((16, 16, 18, 18), fill=(143, 78, 49, 255))
    else:
        draw.rectangle((1, 2, 30, 23), fill=(69, 45, 31, 255))
        draw.rectangle((3, 4, 28, 21), fill=(133, 94, 62, 255))
        draw.rectangle((6, 7, 14, 13), fill=(213, 191, 146, 255))
        draw.rectangle((18, 9, 25, 16), fill=(191, 171, 129, 255))
        draw.point((8, 8), fill=(150, 69, 45, 255))
        draw.point((21, 10), fill=(71, 112, 102, 255))
    return result


def source_master_path(master_id: str) -> Path:
    return MASTER_ROOT / ("generic_chair_set_v2.png" if master_id == "generic_chair_set" else f"{master_id}.png")


def prepare_all() -> list[dict]:
    opened: dict[str, Image.Image] = {}
    reports: list[dict] = []
    for spec in SPECS:
        if spec.master_id not in opened:
            alpha_path = ALPHA_ROOT / f"{spec.master_id}.png"
            if not alpha_path.is_file():
                raise FileNotFoundError(alpha_path)
            opened[spec.master_id] = Image.open(alpha_path).convert("RGBA")
        content = crop_cell(opened[spec.master_id], spec)
        output = sanitize_abstract_paper(spec.asset_id, limit_palette(fit_nearest(content, spec), spec.palette_colors))
        path = SOURCE_ROOT / f"{spec.asset_id}.png"
        output.save(path, format="PNG", optimize=True)
        master = source_master_path(spec.master_id)
        reports.append({
            "asset_id": spec.asset_id,
            "master": str(master),
            "master_sha256": hashlib.sha256(master.read_bytes()).hexdigest(),
            "normalized_source": str(path),
            "output_size": list(output.size),
            "cell": [spec.columns, spec.rows, spec.index],
            "binary_alpha": True,
            "nearest_neighbour": True,
            "palette_colors_max": spec.palette_colors,
        })
    return reports


def validate() -> list[str]:
    errors: list[str] = []
    for spec in SPECS:
        path = SOURCE_ROOT / f"{spec.asset_id}.png"
        if not path.is_file():
            errors.append(f"{spec.asset_id}: missing normalized source")
            continue
        image = Image.open(path).convert("RGBA")
        if image.size != spec.size:
            errors.append(f"{spec.asset_id}: {image.size} != {spec.size}")
        if image.getchannel("A").getbbox() is None:
            errors.append(f"{spec.asset_id}: empty alpha")
        alpha_channel = image.getchannel("A")
        alpha_values = set(alpha_channel.get_flattened_data() if hasattr(alpha_channel, "get_flattened_data") else alpha_channel.getdata())
        if not alpha_values.issubset({0, 255}):
            errors.append(f"{spec.asset_id}: non-binary alpha")
        pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
        key_pixels = sum(1 for r, g, b, a in pixels if a and ((g > 235 and r < 55 and b < 55) or (r > 235 and b > 225 and g < 55)))
        if key_pixels:
            errors.append(f"{spec.asset_id}: {key_pixels} residual key pixels")
    return errors


def main() -> int:
    args = parse_args()
    if not args.all and not args.validate:
        raise SystemExit("Choose --all and/or --validate")
    if args.all:
        reports = prepare_all()
        review = {
            "masters_overwritten": False,
            "assets": reports,
            "rejected_masters": [{
                "source_master_path": "res://assets/images/source_art/generated/masters/generic_chair_set.png",
                "needs_review": True,
                "integrated": False,
                "reason": "First chair sheet read as park benches at game scale; replaced by generic_chair_set_v2.png.",
            }],
        }
        REPORT_PATH.write_text(json.dumps(review, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"P0 fix sprites prepared: {len(reports)} normalized sources")
    errors = validate() if args.validate else []
    for error in errors:
        print(f"ERROR: {error}")
    if args.validate and not errors:
        print(f"P0 fix sprites valid: {len(SPECS)} sources")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
