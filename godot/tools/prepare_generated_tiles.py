#!/usr/bin/env python3
"""Normalize image-generation masters into exact pixel-art atlases.

The image model supplies original texture and material decisions.  This tool
does the production-safe work that a generative image cannot guarantee:
fixed cell grids, hard alpha, integer nearest-neighbour scaling, limited
palettes and direction-aware edge alignment.  Masters are never overwritten.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass, asdict
from pathlib import Path

from PIL import Image, ImageStat


GODOT_ROOT = Path(__file__).resolve().parents[1]
MASTER_ROOT = GODOT_ROOT / "assets" / "images" / "source_art" / "generated" / "masters"
SOURCE_ROOT = GODOT_ROOT / "assets" / "images" / "source_art" / "generated"


@dataclass(frozen=True)
class AtlasSpec:
    asset_id: str
    columns: int
    rows: int
    cell_size: tuple[int, int]
    transparent: bool
    layout: str
    palette_colors: int
    crop_inset: int = 0

    @property
    def output_size(self) -> tuple[int, int]:
        return self.columns * self.cell_size[0], self.rows * self.cell_size[1]


SPECS = {
    spec.asset_id: spec
    for spec in (
        AtlasSpec("grass_base_variants", 4, 4, (32, 32), False, "opaque", 12),
        AtlasSpec("grass_path_edge_set", 4, 4, (32, 32), True, "terrain_4x4", 16),
        AtlasSpec("stone_path_corner_set", 4, 4, (32, 32), False, "opaque", 18, 4),
        AtlasSpec("water_shallow_deep_set", 4, 4, (32, 32), False, "opaque", 14),
        AtlasSpec("natural_shoreline_set", 6, 6, (32, 32), True, "shoreline_6x6", 18),
        AtlasSpec("interior_wall_modular_set", 5, 5, (32, 48), True, "fill", 28),
        AtlasSpec("interior_corner_set", 4, 5, (48, 48), True, "fit", 28),
        AtlasSpec("baseboard_set", 5, 5, (32, 12), True, "fill", 24),
    )
}


TERRAIN_DIRECTIONS = (
    "north", "south", "west", "east",
    "northwest", "northeast", "southwest", "southeast",
    "northwest", "northeast", "southwest", "southeast",
    "north", "south", "west", "east",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset-id", action="append", choices=sorted(SPECS), default=[])
    parser.add_argument("--all", action="store_true", help="Prepare all batch-one atlases.")
    parser.add_argument(
        "--input-root",
        type=Path,
        help="Optional alpha-cleaned overrides; missing files fall back to generated/masters.",
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--validate", action="store_true")
    return parser.parse_args()


def cell_box(size: tuple[int, int], columns: int, rows: int, column: int, row: int, inset: int) -> tuple[int, int, int, int]:
    x0 = round(column * size[0] / columns) + inset
    y0 = round(row * size[1] / rows) + inset
    x1 = round((column + 1) * size[0] / columns) - inset
    y1 = round((row + 1) * size[1] / rows) - inset
    return x0, y0, max(x0 + 1, x1), max(y0 + 1, y1)


def border_key(image: Image.Image) -> tuple[int, int, int]:
    rgb = image.convert("RGB")
    samples: list[tuple[int, int, int]] = []
    step_x = max(1, rgb.width // 128)
    step_y = max(1, rgb.height // 128)
    for x in range(0, rgb.width, step_x):
        samples.append(rgb.getpixel((x, 0)))
        samples.append(rgb.getpixel((x, rgb.height - 1)))
    for y in range(0, rgb.height, step_y):
        samples.append(rgb.getpixel((0, y)))
        samples.append(rgb.getpixel((rgb.width - 1, y)))
    samples.sort(key=lambda color: color[0] + color[1] + color[2])
    mid = len(samples) // 2
    window = samples[max(0, mid - 16):mid + 16] or samples
    return tuple(round(sum(color[channel] for color in window) / len(window)) for channel in range(3))


def hard_remove_key(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    key = border_key(rgba)
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, _alpha = pixels[x, y]
            distance = max(abs(red - key[0]), abs(green - key[1]), abs(blue - key[2]))
            if distance <= 36:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                # Pixel art uses hard alpha.  Chroma-spill is removed by
                # damping the keyed channel only when it dominates strongly.
                if key[1] > 200 and green > red * 1.45 and green > blue * 1.45:
                    green = min(green, max(red, blue))
                if key[0] > 200 and key[2] > 200 and red > green * 1.45 and blue > green * 1.45:
                    red = min(red, green + 16)
                    blue = min(blue, green + 16)
                pixels[x, y] = (red, green, blue, 255)
    return rgba


def harden_alpha(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda value: 255 if value >= 112 else 0)
    rgba.putalpha(alpha)
    return rgba


def limited_palette(image: Image.Image, colors: int) -> Image.Image:
    rgba = harden_alpha(image)
    alpha = rgba.getchannel("A")
    rgb = Image.new("RGB", rgba.size, (0, 0, 0))
    rgb.paste(rgba.convert("RGB"), mask=alpha)
    quantized = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    quantized.putalpha(alpha)
    return quantized


def alpha_content(cell: Image.Image) -> Image.Image:
    bbox = cell.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("atlas cell contains no visible pixels")
    return cell.crop(bbox)


def fit_content(cell: Image.Image, target: tuple[int, int], fill: bool) -> Image.Image:
    content = alpha_content(cell)
    if fill:
        resized = content.resize(target, Image.Resampling.NEAREST)
        return resized
    ratio = min(target[0] / content.width, target[1] / content.height)
    size = max(1, round(content.width * ratio)), max(1, round(content.height * ratio))
    resized = content.resize(size, Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", target, (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((target[0] - size[0]) // 2, target[1] - size[1]))
    return canvas


def normalize_average(image: Image.Image, target: tuple[int, int, int]) -> Image.Image:
    """Bring base tiles to a shared quiet value without flattening their pixel work."""
    rgba = image.convert("RGBA")
    current = ImageStat.Stat(rgba.convert("RGB")).mean
    delta = tuple(max(-48, min(48, round(target[channel] - current[channel]))) for channel in range(3))
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, alpha = pixels[x, y]
            pixels[x, y] = (
                max(0, min(255, red + delta[0])),
                max(0, min(255, green + delta[1])),
                max(0, min(255, blue + delta[2])),
                alpha,
            )
    return rgba


def directional_content(cell: Image.Image, target: tuple[int, int], direction: str) -> Image.Image:
    content = alpha_content(cell)
    horizontal = direction in {"north", "south"}
    vertical = direction in {"west", "east"}
    if horizontal:
        size = target[0], max(4, min(target[1] // 2, round(content.height * target[0] / content.width)))
    elif vertical:
        size = max(4, min(target[0] // 2, round(content.width * target[1] / content.height))), target[1]
    else:
        size = target
    resized = content.resize(size, Image.Resampling.NEAREST)
    if direction == "north":
        position = (0, 0)
    elif direction == "south":
        position = (0, target[1] - size[1])
    elif direction == "west":
        position = (0, 0)
    elif direction == "east":
        position = (target[0] - size[0], 0)
    elif direction == "northwest":
        position = (0, 0)
    elif direction == "northeast":
        position = (target[0] - size[0], 0)
    elif direction == "southwest":
        position = (0, target[1] - size[1])
    else:
        position = (target[0] - size[0], target[1] - size[1])
    canvas = Image.new("RGBA", target, (0, 0, 0, 0))
    canvas.alpha_composite(resized, position)
    return canvas


def normalize_cell(cell: Image.Image, spec: AtlasSpec, index: int) -> Image.Image:
    target = spec.cell_size
    if not spec.transparent:
        resized = cell.convert("RGBA").resize(target, Image.Resampling.NEAREST)
        if spec.asset_id == "grass_base_variants":
            targets = ((98, 121, 84), (100, 123, 85), (97, 120, 83), (96, 119, 85))
            return normalize_average(resized, targets[index // spec.columns])
        if spec.asset_id == "water_shallow_deep_set":
            return normalize_average(resized, (79, 122, 128) if index < 8 else (51, 91, 103))
        return resized
    cell = harden_alpha(cell)
    if spec.layout == "terrain_4x4":
        return directional_content(cell, target, TERRAIN_DIRECTIONS[index])
    if spec.layout == "shoreline_6x6":
        role = index % 12
        direction = TERRAIN_DIRECTIONS[role]
        return directional_content(cell, target, direction)
    return fit_content(cell, target, fill=spec.layout == "fill")


def quiet_seam_borders(atlas: Image.Image, spec: AtlasSpec) -> None:
    if spec.asset_id not in {"grass_base_variants", "water_shallow_deep_set"}:
        return
    width, height = spec.cell_size
    groups = (range(0, 16),) if spec.asset_id == "grass_base_variants" else (range(0, 8), range(8, 16))
    for group in groups:
        colors = []
        for index in group:
            column, row = index % spec.columns, index // spec.columns
            box = (column * width + 2, row * height + 2, column * width + width - 2, row * height + height - 2)
            colors.append(tuple(round(value) for value in ImageStat.Stat(atlas.crop(box).convert("RGB")).median))
        color = tuple(round(sum(sample[channel] for sample in colors) / len(colors)) for channel in range(3)) + (255,)
        for index in group:
            column, row = index % spec.columns, index // spec.columns
            x0, y0 = column * width, row * height
            for x in range(x0, x0 + width):
                atlas.putpixel((x, y0), color)
                atlas.putpixel((x, y0 + height - 1), color)
            for y in range(y0, y0 + height):
                atlas.putpixel((x0, y), color)
                atlas.putpixel((x0 + width - 1, y), color)


def source_for(spec: AtlasSpec, input_root: Path | None) -> Path:
    if input_root is not None:
        override = input_root / f"{spec.asset_id}.png"
        if override.is_file():
            return override
    return MASTER_ROOT / f"{spec.asset_id}.png"


def prepare(spec: AtlasSpec, input_root: Path | None) -> tuple[Image.Image, dict]:
    source = source_for(spec, input_root)
    if not source.is_file():
        raise FileNotFoundError(source)
    with Image.open(source) as opened:
        master = opened.convert("RGBA")
    if spec.transparent and master.getchannel("A").getextrema() == (255, 255):
        master = hard_remove_key(master)
    atlas = Image.new("RGBA", spec.output_size, (0, 0, 0, 0))
    for index in range(spec.columns * spec.rows):
        column, row = index % spec.columns, index // spec.columns
        crop = master.crop(cell_box(master.size, spec.columns, spec.rows, column, row, spec.crop_inset))
        tile = normalize_cell(crop, spec, index)
        atlas.alpha_composite(tile, (column * spec.cell_size[0], row * spec.cell_size[1]))
    atlas = limited_palette(atlas, spec.palette_colors)
    quiet_seam_borders(atlas, spec)
    output = SOURCE_ROOT / f"{spec.asset_id}.png"
    report = {
        "asset_id": spec.asset_id,
        "master": str(source),
        "master_size": list(master.size),
        "output": str(output),
        "output_size": list(atlas.size),
        "grid": [spec.columns, spec.rows],
        "cell_size": list(spec.cell_size),
        "transparent": spec.transparent,
        "palette_colors_max": spec.palette_colors,
        "visible_bbox": list(atlas.getchannel("A").getbbox() or ()),
        "master_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "source_pixel_sha256": hashlib.sha256(atlas.tobytes()).hexdigest(),
    }
    return atlas, report


def validate_output(spec: AtlasSpec) -> list[str]:
    errors: list[str] = []
    path = SOURCE_ROOT / f"{spec.asset_id}.png"
    if not path.is_file():
        return [f"{spec.asset_id}: missing {path}"]
    with Image.open(path) as opened:
        image = opened.convert("RGBA")
    if image.size != spec.output_size:
        errors.append(f"{spec.asset_id}: {image.size} != {spec.output_size}")
    alpha_channel = image.getchannel("A")
    alpha_values = set(alpha_channel.get_flattened_data() if hasattr(alpha_channel, "get_flattened_data") else alpha_channel.getdata())
    if not alpha_values.issubset({0, 255}):
        errors.append(f"{spec.asset_id}: non-binary alpha values")
    pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    magenta = sum(1 for red, green, blue, alpha in pixels if alpha and red >= 235 and blue >= 225 and green <= 55)
    green_key = sum(1 for red, green, blue, alpha in pixels if alpha and green >= 235 and red <= 55 and blue <= 55)
    if magenta or green_key:
        errors.append(f"{spec.asset_id}: residual key pixels magenta={magenta} green={green_key}")
    opaque_colors = {
        (red, green, blue)
        for red, green, blue, alpha in (image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata())
        if alpha
    }
    if len(opaque_colors) > spec.palette_colors + 2:
        errors.append(f"{spec.asset_id}: {len(opaque_colors)} opaque colors exceed limit {spec.palette_colors + 2}")
    width, height = spec.cell_size
    for index in range(spec.columns * spec.rows):
        column, row = index % spec.columns, index // spec.columns
        cell = image.crop((column * width, row * height, (column + 1) * width, (row + 1) * height))
        bbox = cell.getchannel("A").getbbox()
        if bbox is None:
            errors.append(f"{spec.asset_id}[{index}]: empty atlas cell")
            continue
        if not spec.transparent and cell.getchannel("A").getextrema() != (255, 255):
            errors.append(f"{spec.asset_id}[{index}]: opaque tile contains transparency")
        if spec.layout in {"terrain_4x4", "shoreline_6x6"}:
            role_index = index if spec.layout == "terrain_4x4" else index % 12
            direction = TERRAIN_DIRECTIONS[role_index]
            required = {
                "north": bbox[1] == 0,
                "south": bbox[3] == height,
                "west": bbox[0] == 0,
                "east": bbox[2] == width,
                "northwest": bbox[0] == 0 and bbox[1] == 0,
                "northeast": bbox[2] == width and bbox[1] == 0,
                "southwest": bbox[0] == 0 and bbox[3] == height,
                "southeast": bbox[2] == width and bbox[3] == height,
            }[direction]
            if not required:
                errors.append(f"{spec.asset_id}[{index}]: {direction} module does not touch required boundary")
    return errors


def main() -> int:
    args = parse_args()
    selected = list(SPECS) if args.all else args.asset_id
    if not selected and not args.validate:
        raise SystemExit("Choose --all, --asset-id ASSET_ID, or --validate")
    SOURCE_ROOT.mkdir(parents=True, exist_ok=True)
    reports: list[dict] = []
    if selected:
        for asset_id in selected:
            spec = SPECS[asset_id]
            atlas, report = prepare(spec, args.input_root)
            if not args.dry_run:
                atlas.save(SOURCE_ROOT / f"{asset_id}.png", format="PNG", optimize=True)
            reports.append(report)
            print(f"{'dry-run' if args.dry_run else 'written':7} {asset_id:32} {atlas.size} grid={spec.columns}x{spec.rows} cell={spec.cell_size}")
    errors: list[str] = []
    if args.validate:
        for spec in SPECS.values():
            errors.extend(validate_output(spec))
    if reports and not args.dry_run:
        report_path = SOURCE_ROOT / "batch_01_processing_report.json"
        report_path.write_text(json.dumps({"masters_overwritten": False, "nearest_neighbour": True, "assets": reports}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"report  {report_path}")
    for error in errors:
        print(f"ERROR: {error}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
