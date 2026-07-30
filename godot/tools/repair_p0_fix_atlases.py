#!/usr/bin/env python3
"""Build only the atlas cells required by the P0 benchmark-fix pass.

The accepted v2 cells remain the source of truth.  This script creates v3
siblings and replaces only the shoreline/path/water cells named by the review,
plus the two new harbor-specific atlases.  Existing source files are untouched.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

from repair_p0_benchmark_tiles import (
    BANK,
    BANK_DARK,
    DEEP,
    DEEP_LIGHT,
    DIRT,
    DIRT_DARK,
    GRASS,
    GRASS_DARK,
    SHALLOW,
    SHALLOW_LIGHT,
    STONE,
    STONE_DARK,
    build_shore_tile,
    path_mask,
    soften,
    textured_fill,
    vary,
)


GODOT_ROOT = Path(__file__).resolve().parents[1]
SOURCE = GODOT_ROOT / "assets" / "images" / "source_art" / "generated"
PROCESSED = GODOT_ROOT / "assets" / "images" / "processed"
MASTER = SOURCE / "masters"
REPORT = SOURCE / "p0_fix_atlas_report.json"

OUTPUTS = {
    "natural_shoreline_set_v3": (192, 192),
    "stone_path_corner_set_v3": (256, 256),
    "water_shallow_deep_set_v3": (128, 128),
    "harbor_dock_entry_set": (128, 64),
    "water_transition_patch_set": (160, 128),
}

SHORE_ROLES = (
    "edge_n", "edge_s", "edge_w", "edge_e",
    "outer_corner_nw", "outer_corner_ne", "outer_corner_sw", "outer_corner_se",
    "inner_corner_nw", "inner_corner_ne", "inner_corner_sw", "inner_corner_se",
)

# Every changed index is required by town/harbor or explicitly called out by
# the review. Dirt outer SW and the two unused dirt inner corners stay byte-for-
# byte inherited from v2 instead of regenerating the complete 36-cell atlas.
SHORE_PATCH_INDICES = set(range(0, 18)) | {19, 21, 23} | set(range(24, 36))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--validate", action="store_true")
    return parser.parse_args()


def shoreline_signed(role: str, x: int, y: int) -> float:
    wave = (0, 0, 1, 0, -1, 0, 1, 0)
    boundary = 10
    if role == "edge_n":
        return y - (boundary + wave[x % len(wave)])
    if role == "edge_s":
        return (31 - y) - (boundary + wave[x % len(wave)])
    if role == "edge_w":
        return x - (boundary + wave[y % len(wave)])
    if role == "edge_e":
        return (31 - x) - (boundary + wave[y % len(wave)])
    if role.startswith("outer_corner_"):
        sx = x if role.endswith(("nw", "sw")) else 31 - x
        sy = y if role.endswith(("nw", "ne")) else 31 - y
        return 21.0 - math.hypot(31 - sx, 31 - sy)
    sx = x if role.endswith(("nw", "sw")) else 31 - x
    sy = y if role.endswith(("nw", "ne")) else 31 - y
    return math.hypot(sx, sy) - 10.0


def build_overlay_shore_tile(material: str, role: str, seed: str) -> Image.Image:
    """Keep land/bank opaque but let the map's water show beyond a 4px shallows lip."""
    tile = build_shore_tile(material, role, seed)
    pixels = tile.load()
    for y in range(32):
        for x in range(32):
            signed = shoreline_signed(role, x, y)
            if signed > 8.0:
                pixels[x, y] = (0, 0, 0, 0)
            elif signed >= 5.0:
                color = SHALLOW_LIGHT if (x * 11 + y * 7 + len(role)) % 31 == 0 else SHALLOW
                pixels[x, y] = color
    return tile


def build_shoreline_v3() -> Image.Image:
    v2 = Image.open(SOURCE / "natural_shoreline_set_v2.png").convert("RGBA")
    atlas = v2.copy()
    for index in sorted(SHORE_PATCH_INDICES):
        material_index = index // 12
        material = ("grass", "dirt", "stone")[material_index]
        role = SHORE_ROLES[index % 12]
        tile = build_overlay_shore_tile(material, role, f"p0-fix:{material}:{role}")
        atlas.paste(tile, ((index % 6) * 32, (index // 6) * 32))
    return atlas


def quiet_stone_tile(seed: str, gravel: bool = False) -> Image.Image:
    rng = random.Random(seed)
    base = DIRT if gravel else (151, 143, 119, 255)
    tile = textured_fill((32, 32), base, seed, 0.035 if not gravel else 0.07)
    draw = ImageDraw.Draw(tile)
    count = 13 if gravel else 20
    for _ in range(count):
        x = rng.randrange(2, 29)
        y = rng.randrange(2, 29)
        w = rng.choice((2, 3, 4))
        color = (125, 119, 101, 255) if not gravel else (112, 103, 82, 255)
        draw.line((x, y, min(30, x + w), y), fill=color, width=1)
        if not gravel and rng.random() < 0.45:
            draw.point((x, min(30, y + 1)), fill=(169, 157, 128, 255))
    return tile


def wide_path_tile(role: str, center: Image.Image) -> Image.Image:
    grass = Image.open(PROCESSED / "grass_base_variants.png").convert("RGBA").crop((0, 0, 32, 32))
    tile = grass.copy()
    for y in range(32):
        for x in range(32):
            if path_mask(role, x, y):
                pixel = soften(center.getpixel((x, y)), (150, 141, 116, 255), 0.34)
                tile.putpixel((x, y), pixel)
    return tile


def branch_narrow_to_wide(center: Image.Image) -> Image.Image:
    grass = Image.open(PROCESSED / "grass_base_variants.png").convert("RGBA").crop((0, 0, 32, 32))
    tile = grass.copy()
    for y in range(32):
        half = 7 + round(5 * y / 31)
        for x in range(16 - half, 17 + half):
            tile.putpixel((x, y), soften(center.getpixel((x, y)), (150, 141, 116, 255), 0.36))
    return tile


def transparent_edge_detail(kind: str, seed: str) -> Image.Image:
    tile = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    rng = random.Random(seed)
    if kind == "clean":
        draw.line((2, 28, 29, 28), fill=(104, 100, 84, 255), width=1)
    elif kind.startswith("grass"):
        for _ in range(5 if kind.endswith("a") else 7):
            x = rng.randrange(3, 29)
            y = rng.randrange(25, 31)
            draw.line((x, y, x + rng.choice((-1, 0, 1)), y - rng.randrange(2, 5)), fill=GRASS_DARK, width=1)
    else:
        for x, y in ((3, 27), (7, 29), (23, 28), (27, 26)):
            draw.rectangle((x, y, x + 2, y + 1), fill=(112, 106, 88, 255))
    return tile


def directional_broken_edge(direction: str) -> Image.Image:
    tile = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    fragments = ((3, 1), (9, 2), (21, 2), (27, 1))
    for offset, length in fragments:
        if direction == "n":
            draw.rectangle((offset, 1, offset + length, 2), fill=(112, 106, 88, 255))
        elif direction == "s":
            draw.rectangle((offset, 29, offset + length, 30), fill=(112, 106, 88, 255))
        elif direction == "w":
            draw.rectangle((1, offset, 2, offset + length), fill=(112, 106, 88, 255))
        else:
            draw.rectangle((29, offset, 30, offset + length), fill=(112, 106, 88, 255))
    return tile


def doorway_platform() -> Image.Image:
    """A small grounded sill; it must never read as a full rectangular slab."""
    tile = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    draw.polygon([(3, 21), (28, 21), (30, 25), (27, 29), (5, 29), (2, 26)], fill=(142, 132, 108, 255))
    draw.line((4, 21, 28, 21), fill=(184, 170, 137, 255), width=1)
    draw.line((5, 29, 27, 29), fill=(92, 88, 74, 255), width=2)
    for x, y in ((8, 24), (16, 22), (23, 26)):
        draw.line((x, y, x + 3, y), fill=(113, 106, 88, 255), width=1)
    return tile


def material_path_tile(role: str, center: Image.Image) -> Image.Image:
    """Apply an alternate material without changing any directional topology."""
    grass = Image.open(PROCESSED / "grass_base_variants.png").convert("RGBA").crop((0, 0, 32, 32))
    tile = grass.copy()
    for y in range(32):
        for x in range(32):
            if path_mask(role, x, y):
                tile.putpixel((x, y), center.getpixel((x, y)))
    return tile


def build_stone_v3() -> Image.Image:
    v2 = Image.open(SOURCE / "stone_path_corner_set_v2.png").convert("RGBA")
    atlas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    for index in range(16):
        old_x, old_y = (index % 4) * 32, (index // 4) * 32
        tile = v2.crop((old_x, old_y, old_x + 32, old_y + 32))
        atlas.paste(tile, ((index % 8) * 32, (index // 8) * 32))
    center = v2.crop((0, 0, 32, 32))
    additions = [
        wide_path_tile("t_junction", center),
        wide_path_tile("cross_junction", center),
        branch_narrow_to_wide(center),
        transparent_edge_detail("clean", "stone-clean"),
        transparent_edge_detail("grass_a", "stone-grass-a"),
        transparent_edge_detail("grass_b", "stone-grass-b"),
        transparent_edge_detail("broken", "stone-broken"),
        quiet_stone_tile("town-main-worn"),
        quiet_stone_tile("town-branch-gravel", True),
        directional_broken_edge("n"),
        directional_broken_edge("s"),
        directional_broken_edge("w"),
        directional_broken_edge("e"),
        doorway_platform(),
    ]
    while len(additions) < 16:
        additions.append(quiet_stone_tile(f"reserved-{len(additions)}"))
    for offset, tile in enumerate(additions):
        index = 16 + offset
        atlas.paste(tile, ((index % 8) * 32, (index // 8) * 32), tile if tile.getchannel("A").getextrema()[0] == 0 else None)
    material_roles = SHORE_ROLES
    worn = quiet_stone_tile("town-main-worn-family")
    gravel = quiet_stone_tile("town-branch-gravel-family", True)
    for offset, role in enumerate(material_roles):
        atlas.paste(material_path_tile(role, worn), (((32 + offset) % 8) * 32, ((32 + offset) // 8) * 32))
        atlas.paste(material_path_tile(role, gravel), (((44 + offset) % 8) * 32, ((44 + offset) // 8) * 32))
    return atlas


def hard_transition(role: str, variant: int = 0) -> Image.Image:
    tile = Image.new("RGBA", (32, 32), DEEP)
    shallow = textured_fill((32, 32), SHALLOW, f"{role}:{variant}:shallow", 0.05)
    deep = textured_fill((32, 32), DEEP, f"{role}:{variant}:deep", 0.05)
    wiggles = (0, 0, 1, 2, 1, 0, -1, -2, -1, 0, 1, 0, -1, 0, 1, 0,
               0, -1, -2, -1, 0, 1, 2, 1, 0, -1, 0, 1, 0, -1, 0, 0)
    for y in range(32):
        for x in range(32):
            suffix = role.rsplit("_", 1)[-1]
            if role.startswith("straight_"):
                if suffix == "n": metric, contour = y, 12 + wiggles[(x + variant * 7) % 32]
                elif suffix == "s": metric, contour = 31 - y, 12 + wiggles[(x + variant * 7) % 32]
                elif suffix == "w": metric, contour = x, 12 + wiggles[(y + variant * 7) % 32]
                else: metric, contour = 31 - x, 12 + wiggles[(y + variant * 7) % 32]
                shallow_here = metric <= contour
                band = abs(metric - contour) <= 1
            else:
                corner = suffix
                sx = x if corner.endswith("w") else 31 - x
                sy = y if corner.startswith("n") else 31 - y
                radius = math.hypot(sx, sy)
                contour = 17 + wiggles[(x + y + variant * 5) % 32]
                shallow_here = radius <= contour if role.startswith("outer_") else radius >= contour
                band = abs(radius - contour) <= 1.3
            color = shallow.getpixel((x, y)) if shallow_here else deep.getpixel((x, y))
            if band:
                color = (56, 101, 111, 255)
            tile.putpixel((x, y), color)
    return tile


def irregular_patch(kind: str, variant: int) -> Image.Image:
    shallow_base = kind == "shallow"
    tile = textured_fill((32, 32), SHALLOW if shallow_base else DEEP, f"{kind}:{variant}", 0.055)
    draw = ImageDraw.Draw(tile)
    points = [(5, 15), (8, 9), (14, 7), (19, 9), (25, 7), (28, 14), (25, 21), (19, 23), (14, 27), (8, 23)]
    if variant:
        points = [(31 - x, y + (1 if i % 2 else -1)) for i, (x, y) in enumerate(points)]
    fill = DEEP if shallow_base else SHALLOW
    draw.polygon(points, fill=fill)
    outline = (56, 101, 111, 255)
    draw.line(points + [points[0]], fill=outline, width=1)
    return tile


def quiet_deep_water(seed: str) -> Image.Image:
    tile = textured_fill((32, 32), DEEP, seed, 0.035)
    draw = ImageDraw.Draw(tile)
    rng = random.Random(seed)
    for _ in range(7):
        x = rng.randrange(2, 27)
        y = rng.randrange(3, 29)
        length = rng.choice((2, 3, 4))
        draw.line((x, y, x + length, y), fill=(45, 87, 99, 255), width=1)
    return tile


def build_transition_patch_set() -> Image.Image:
    roles: list[tuple[str, int]] = [
        ("straight_n", 0), ("straight_n", 1), ("straight_s", 0), ("straight_s", 1),
        ("straight_w", 0), ("straight_w", 1), ("straight_e", 0), ("straight_e", 1),
        ("outer_nw", 0), ("outer_ne", 0), ("outer_sw", 0), ("outer_se", 0),
        ("inner_nw", 0), ("inner_ne", 0), ("inner_sw", 0), ("inner_se", 0),
    ]
    tiles = [hard_transition(role, variant) for role, variant in roles]
    tiles.extend([irregular_patch("shallow", 0), irregular_patch("shallow", 1), irregular_patch("deep", 0), irregular_patch("deep", 1)])
    atlas = Image.new("RGBA", (160, 128), DEEP)
    for index, tile in enumerate(tiles):
        atlas.paste(tile, ((index % 5) * 32, (index // 5) * 32))
    return atlas


def build_water_v3() -> Image.Image:
    atlas = Image.open(SOURCE / "water_shallow_deep_set_v2.png").convert("RGBA").copy()
    replacements = [
        hard_transition("straight_n"), hard_transition("straight_s"),
        hard_transition("straight_w"), hard_transition("straight_e"),
        hard_transition("outer_nw"), hard_transition("outer_ne"),
        hard_transition("outer_sw"), hard_transition("outer_se"),
    ]
    for offset, tile in enumerate(replacements):
        index = 4 + offset
        atlas.paste(tile, ((index % 4) * 32, (index // 4) * 32))
    # v2's third deep variant had a centered shallow blob; when selected at
    # tile frequency it became a checkerboard.  Keep the two accepted base
    # tiles and replace only deep_c with sparse, non-central current marks.
    atlas.paste(quiet_deep_water("p0-fix:deep-c"), (3 * 32, 3 * 32))
    return atlas


def dock_surface(seed: str, side: str = "center") -> Image.Image:
    tile = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    rng = random.Random(seed)
    for x in range(0, 14):
        base = (130 + rng.randrange(-5, 6), 120 + rng.randrange(-5, 6), 98 + rng.randrange(-4, 5), 255)
        draw.line((x, 0, x, 31), fill=base)
    draw.rectangle((13, 0, 16, 31), fill=(75, 72, 61, 255))
    draw.rectangle((17, 0, 31, 31), fill=(102, 72, 48, 255))
    for y in (4, 11, 18, 25):
        draw.line((17, y, 31, y), fill=(62, 48, 38, 255), width=1)
        draw.line((18, y + 1, 30, y + 1), fill=(132, 92, 58, 255), width=1)
    if side == "north":
        draw.line((14, 1, 31, 1), fill=(52, 39, 31, 255), width=3)
    elif side == "south":
        draw.line((14, 30, 31, 30), fill=(52, 39, 31, 255), width=3)
    return tile


def dock_pile(mirror: bool = False) -> Image.Image:
    tile = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    x = 23 if mirror else 8
    draw.ellipse((x - 4, 2, x + 4, 9), fill=(137, 96, 55, 255), outline=(55, 41, 31, 255))
    draw.rectangle((x - 3, 7, x + 3, 30), fill=(102, 68, 44, 255), outline=(55, 41, 31, 255))
    draw.line((x - 4, 15, x + 4, 17), fill=(44, 47, 43, 255), width=2)
    return tile


def build_dock_entry_set() -> Image.Image:
    atlas = Image.new("RGBA", (128, 64), (0, 0, 0, 0))
    tiles = [dock_surface("center"), dock_surface("north", "north"), dock_surface("south", "south"), dock_surface("threshold")]
    shadow = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    for y, inset in ((12, 2), (16, 5), (20, 8)):
        draw.line((inset, y, 31 - inset, y), fill=(27, 57, 67, 255), width=2)
    disturbance = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disturbance)
    for x, y, length in ((3, 8, 7), (17, 12, 9), (8, 20, 11), (21, 25, 6)):
        dd.line((x, y, x + length, y), fill=(86, 139, 142, 255), width=1)
    tiles.extend([dock_pile(False), dock_pile(True), shadow, disturbance])
    for index, tile in enumerate(tiles):
        atlas.paste(tile, ((index % 4) * 32, (index // 4) * 32), tile)
    return atlas


def validate_image(path: Path, size: tuple[int, int], allow_alpha: bool) -> list[str]:
    errors: list[str] = []
    if not path.is_file():
        return [f"missing {path}"]
    image = Image.open(path).convert("RGBA")
    if image.size != size:
        errors.append(f"{path.name}: {image.size} != {size}")
    values = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    if any(r < 4 and g < 4 and b < 4 and a for r, g, b, a in values):
        errors.append(f"{path.name}: opaque pure-black artifact")
    if not allow_alpha and image.getchannel("A").getextrema() != (255, 255):
        errors.append(f"{path.name}: unexpected alpha")
    return errors


def build_all() -> dict[str, Image.Image]:
    return {
        "natural_shoreline_set_v3": build_shoreline_v3(),
        "stone_path_corner_set_v3": build_stone_v3(),
        "water_shallow_deep_set_v3": build_water_v3(),
        "harbor_dock_entry_set": build_dock_entry_set(),
        "water_transition_patch_set": build_transition_patch_set(),
    }


def main() -> int:
    args = parse_args()
    if not args.all and not args.validate:
        raise SystemExit("Choose --all and/or --validate")
    reports: list[dict] = []
    if args.all:
        for asset_id, image in build_all().items():
            path = SOURCE / f"{asset_id}.png"
            image.save(path, format="PNG", optimize=True)
            master = MASTER / (f"{asset_id.removesuffix('_v3')}.png" if asset_id.endswith("_v3") else f"{asset_id}.png")
            reports.append({
                "asset_id": asset_id,
                "output": str(path),
                "output_size": list(image.size),
                "master": str(master),
                "master_sha256": hashlib.sha256(master.read_bytes()).hexdigest() if master.is_file() else "",
                "nearest_neighbour": True,
                "hard_pixel_edges": True,
            })
        REPORT.write_text(json.dumps({"preserved_v2_sources": True, "assets": reports}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"P0 fix atlases written: {len(reports)}")
    errors: list[str] = []
    if args.validate:
        for asset_id, size in OUTPUTS.items():
            errors.extend(validate_image(SOURCE / f"{asset_id}.png", size, asset_id in {"natural_shoreline_set_v3", "stone_path_corner_set_v3", "harbor_dock_entry_set"}))
        if not errors:
            print("P0 fix atlases valid: 5 normalized sources")
    for error in errors:
        print(f"ERROR: {error}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
