#!/usr/bin/env python3
"""Deterministically repair only the P0 atlases used by benchmark maps.

The image-generation outputs in source_art/generated/references are visual
references. Runtime atlases are reconstructed at exact pixel scale so their
grid, edge closure and semantic order stay machine-verifiable.
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image


GODOT_ROOT = Path(__file__).resolve().parents[1]
SOURCE = GODOT_ROOT / "assets" / "images" / "source_art" / "generated"
PROCESSED = GODOT_ROOT / "assets" / "images" / "processed"

OUTPUTS = {
    "natural_shoreline_set_v2": (192, 192),
    "stone_path_corner_set_v2": (128, 128),
    "water_shallow_deep_set_v2": (128, 128),
}

GRASS = (91, 116, 75, 255)
GRASS_DARK = (76, 98, 65, 255)
DIRT = (126, 105, 78, 255)
DIRT_DARK = (91, 77, 62, 255)
STONE = (118, 126, 111, 255)
STONE_DARK = (79, 87, 79, 255)
BANK = (103, 94, 70, 255)
BANK_DARK = (75, 81, 64, 255)
SHALLOW = (67, 112, 121, 255)
SHALLOW_LIGHT = (83, 132, 138, 255)
DEEP = (39, 78, 92, 255)
DEEP_LIGHT = (52, 96, 108, 255)


def clamp_channel(value: int) -> int:
    return max(0, min(255, value))


def vary(color: tuple[int, int, int, int], amount: int) -> tuple[int, int, int, int]:
    return tuple(clamp_channel(channel + amount) for channel in color[:3]) + (color[3],)


def textured_fill(size: tuple[int, int], base: tuple[int, int, int, int], seed: str, density: float = 0.10) -> Image.Image:
    image = Image.new("RGBA", size, base)
    rng = random.Random(seed)
    pixels = image.load()
    for y in range(1, size[1] - 1):
        for x in range(1, size[0] - 1):
            if rng.random() < density:
                pixels[x, y] = vary(base, rng.choice((-7, -5, 5, 7)))
    return image


def wave(position: int) -> int:
    return (0, 0, 1, 0, -1, 0, 1, 0)[position % 8]


def shoreline_classes(role: str) -> list[list[int]]:
    """Return 0 land, 1 dark lip, 2 exposed bank, 3 shallow water."""
    result = [[0 for _ in range(32)] for _ in range(32)]
    for y in range(32):
        for x in range(32):
            boundary = 10
            signed = -99
            if role == "edge_n":
                signed = y - (boundary + wave(x))
            elif role == "edge_s":
                signed = (31 - y) - (boundary + wave(x))
            elif role == "edge_w":
                signed = x - (boundary + wave(y))
            elif role == "edge_e":
                signed = (31 - x) - (boundary + wave(y))
            elif role.startswith("outer_corner_"):
                sx = x if role.endswith(("nw", "sw")) else 31 - x
                sy = y if role.endswith(("nw", "ne")) else 31 - y
                # A quarter-circle joins the adjacent straight banks exactly
                # at (10, 31) and (31, 10), eliminating visible line breaks.
                signed = 21.0 - math.hypot(31 - sx, 31 - sy)
            elif role.startswith("inner_corner_"):
                sx = x if role.endswith(("nw", "sw")) else 31 - x
                sy = y if role.endswith(("nw", "ne")) else 31 - y
                # Complementary inner arc joins the same 10px straight-bank
                # endpoints; land occupies only the named corner.
                signed = math.hypot(sx, sy) - 10.0
            if signed >= 5:
                result[y][x] = 3
            elif signed >= 1:
                result[y][x] = 2
            elif signed >= 0:
                result[y][x] = 1
            else:
                result[y][x] = 0
    return result


def build_shore_tile(material: str, role: str, seed: str) -> Image.Image:
    land_color = {"grass": GRASS, "dirt": DIRT, "stone": STONE}[material]
    land_dark = {"grass": GRASS_DARK, "dirt": DIRT_DARK, "stone": STONE_DARK}[material]
    land = textured_fill((32, 32), land_color, seed + ":land", 0.08 if material != "stone" else 0.14)
    shallow = textured_fill((32, 32), SHALLOW, seed + ":water", 0.08)
    result = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    classes = shoreline_classes(role)
    for y in range(32):
        for x in range(32):
            cls = classes[y][x]
            if cls == 0:
                color = land.getpixel((x, y))
            elif cls == 1:
                color = BANK_DARK if material == "grass" else land_dark
            elif cls == 2:
                if material == "grass":
                    color = vary(BANK, 6 if (x * 3 + y) % 5 == 0 else 0)
                elif material == "dirt":
                    color = vary(DIRT_DARK, 8 if (x + y * 2) % 5 == 0 else 0)
                else:
                    color = vary(STONE_DARK, 10 if (x * 2 + y) % 5 == 0 else 0)
            else:
                color = shallow.getpixel((x, y))
                if (x * 3 + y * 5) % 29 == 0:
                    color = SHALLOW_LIGHT
            result.putpixel((x, y), color)
    # A sparse one-pixel fringe breaks ruler-straight banks without increasing
    # high-frequency ground noise. It is deterministic and material-specific.
    for y in range(1, 31):
        for x in range(1, 31):
            if material != "grass" or classes[y][x] != 0:
                continue
            touches_lip = any(classes[ny][nx] == 1 for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))
            if touches_lip and (x * 17 + y * 11 + len(role)) % 19 == 0:
                result.putpixel((x, y), land_dark)
    return result


def build_shoreline_atlas() -> Image.Image:
    atlas = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    roles = [
        "edge_n", "edge_s", "edge_w", "edge_e",
        "outer_corner_nw", "outer_corner_ne", "outer_corner_sw", "outer_corner_se",
        "inner_corner_nw", "inner_corner_ne", "inner_corner_sw", "inner_corner_se",
    ]
    for material_index, material in enumerate(("grass", "dirt", "stone")):
        for role_index, role in enumerate(roles):
            index = material_index * 12 + role_index
            x = (index % 6) * 32
            y = (index // 6) * 32
            atlas.paste(build_shore_tile(material, role, f"{material}:{role}"), (x, y))
    return atlas


def soften(pixel: tuple[int, int, int, int], target: tuple[int, int, int, int], mix: float) -> tuple[int, int, int, int]:
    return tuple(round(pixel[i] * (1.0 - mix) + target[i] * mix) for i in range(3)) + (255,)


def path_mask(role: str, x: int, y: int) -> bool:
    edge = 5 + wave(x if role in {"edge_n", "edge_s"} else y)
    if role == "center_a": return True
    if role == "edge_n": return y >= edge
    if role == "edge_s": return y <= 31 - edge
    if role == "edge_w": return x >= edge
    if role == "edge_e": return x <= 31 - edge
    if role == "outer_corner_nw": return x >= 5 and y >= 5
    if role == "outer_corner_ne": return x <= 26 and y >= 5
    if role == "outer_corner_sw": return x >= 5 and y <= 26
    if role == "outer_corner_se": return x <= 26 and y <= 26
    if role == "inner_corner_nw": return x + y >= 8
    if role == "inner_corner_ne": return (31 - x) + y >= 8
    if role == "inner_corner_sw": return x + (31 - y) >= 8
    if role == "inner_corner_se": return (31 - x) + (31 - y) >= 8
    if role == "t_junction": return (4 <= y <= 27) or (4 <= x <= 27 and y <= 20)
    if role == "cross_junction": return (4 <= y <= 27) or (4 <= x <= 27)
    if role == "small_platform": return 3 <= x <= 28 and 3 <= y <= 28
    return False


def build_stone_path_atlas() -> Image.Image:
    source = Image.open(SOURCE / "stone_path_corner_set.png").convert("RGBA")
    grass = Image.open(PROCESSED / "grass_base_variants.png").convert("RGBA").crop((0, 0, 32, 32))
    center = source.crop((0, 0, 32, 32))
    roles = [
        "center_a", "edge_n", "edge_s", "edge_w", "edge_e",
        "outer_corner_nw", "outer_corner_ne", "outer_corner_sw", "outer_corner_se",
        "inner_corner_nw", "inner_corner_ne", "inner_corner_sw", "inner_corner_se",
        "t_junction", "cross_junction", "small_platform",
    ]
    atlas = Image.new("RGBA", (128, 128), GRASS)
    for index, role in enumerate(roles):
        tile = grass.copy()
        mask = [[path_mask(role, x, y) for x in range(32)] for y in range(32)]
        for y in range(32):
            for x in range(32):
                if mask[y][x]:
                    stone_pixel = soften(center.getpixel((x, y)), (157, 145, 116, 255), 0.22)
                    adjacent_grass = any(
                        0 <= nx < 32 and 0 <= ny < 32 and not mask[ny][nx]
                        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                    )
                    tile.putpixel((x, y), soften(stone_pixel, (80, 79, 66, 255), 0.25) if adjacent_grass else stone_pixel)
        atlas.paste(tile, ((index % 4) * 32, (index // 4) * 32))
    return atlas


def water_base(color: tuple[int, int, int, int], seed: str, highlight: bool = False) -> Image.Image:
    tile = textured_fill((32, 32), color, seed, 0.13)
    if highlight:
        rng = random.Random(seed + ":highlight")
        for _ in range(5):
            x = rng.randrange(3, 25)
            y = rng.randrange(3, 29)
            length = rng.randrange(3, 7)
            for dx in range(length):
                tile.putpixel((x + dx, y), SHALLOW_LIGHT if color == SHALLOW else DEEP_LIGHT)
    # Normalize every tile boundary so matching semantic strips never crack.
    for x in range(32):
        tile.putpixel((x, 0), color)
        tile.putpixel((x, 31), color)
    for y in range(32):
        tile.putpixel((0, y), color)
        tile.putpixel((31, y), color)
    return tile


def transition_tile(role: str, seed: str) -> Image.Image:
    shallow = water_base(SHALLOW, seed + ":shallow")
    deep = water_base(DEEP, seed + ":deep")
    tile = Image.new("RGBA", (32, 32), DEEP)
    for y in range(32):
        for x in range(32):
            if role == "shallow_to_deep_n": metric = y
            elif role == "shallow_to_deep_s": metric = 31 - y
            elif role == "shallow_to_deep_w": metric = x
            elif role == "shallow_to_deep_e": metric = 31 - x
            elif role == "transition_corner_nw": metric = (x + y) // 2
            elif role == "transition_corner_ne": metric = ((31 - x) + y) // 2
            elif role == "transition_corner_sw": metric = (x + (31 - y)) // 2
            else: metric = ((31 - x) + (31 - y)) // 2
            boundary = 13 + wave(x + y)
            if metric <= boundary:
                color = shallow.getpixel((x, y))
            elif metric <= boundary + 5:
                depth = metric - boundary
                color = soften(SHALLOW, DEEP, depth / 6.0)
            else:
                color = deep.getpixel((x, y))
            tile.putpixel((x, y), color)
    return tile


def build_water_atlas() -> Image.Image:
    roles = [
        "shallow_a", "shallow_b", "deep_a", "deep_b",
        "shallow_to_deep_n", "shallow_to_deep_s", "shallow_to_deep_w", "shallow_to_deep_e",
        "transition_corner_nw", "transition_corner_ne", "transition_corner_sw", "transition_corner_se",
        "deep_highlight_a", "deep_highlight_b", "shallow_highlight", "deep_c",
    ]
    atlas = Image.new("RGBA", (128, 128), DEEP)
    for index, role in enumerate(roles):
        if role.startswith("shallow_to") or role.startswith("transition_corner"):
            tile = transition_tile(role, role)
        elif role.startswith("shallow"):
            tile = water_base(SHALLOW, role, role == "shallow_highlight")
        else:
            tile = water_base(DEEP, role, role.startswith("deep_highlight"))
        atlas.paste(tile, ((index % 4) * 32, (index // 4) * 32))
    return atlas


def validate_image(path: Path, expected: tuple[int, int]) -> None:
    if not path.is_file():
        raise SystemExit(f"Missing repaired atlas: {path}")
    with Image.open(path) as image:
        rgba = image.convert("RGBA")
        if rgba.size != expected:
            raise SystemExit(f"Wrong repaired atlas size: {path}: {rgba.size} != {expected}")
        colors = rgba.get_flattened_data()
        if any(r > 245 and b > 245 and g < 20 for r, g, b, _ in colors):
            raise SystemExit(f"Residual magenta in repaired atlas: {path}")
        if any(r < 4 and g < 4 and b < 4 and a > 0 for r, g, b, a in colors):
            raise SystemExit(f"Opaque pure-black artifact in repaired atlas: {path}")


def validate() -> None:
    for asset_id, size in OUTPUTS.items():
        validate_image(SOURCE / f"{asset_id}.png", size)
        validate_image(PROCESSED / f"{asset_id}.png", size)
    print("P0 benchmark atlas repairs: 3 source + 3 processed images valid")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--validate", action="store_true")
    args = parser.parse_args()
    if args.validate:
        validate()
        return
    atlases = {
        "natural_shoreline_set_v2": build_shoreline_atlas(),
        "stone_path_corner_set_v2": build_stone_path_atlas(),
        "water_shallow_deep_set_v2": build_water_atlas(),
    }
    if args.dry_run:
        for asset_id, image in atlases.items():
            print(asset_id, image.size)
        return
    SOURCE.mkdir(parents=True, exist_ok=True)
    for asset_id, image in atlases.items():
        image.save(SOURCE / f"{asset_id}.png", optimize=True)
    print("Wrote repaired P0 benchmark source atlases; run process_art_assets.py after manifest update")


if __name__ == "__main__":
    main()
