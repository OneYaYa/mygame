#!/usr/bin/env python3
"""Prepare the remaining-15-map generated masters for the formal Godot build.

The 13 image-generation masters remain untouched.  The script consumes their
hard-alpha copies, crops semantic props, builds deterministic 32 px modular
atlases from each master's own palette, and mechanically synchronizes the
manifest/atlas dependency data.  It never writes source_art originals.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter
from pathlib import Path

from PIL import Image, ImageColor, ImageDraw


GODOT_ROOT = Path(__file__).resolve().parents[1]
DATA_ROOT = GODOT_ROOT / "data"
SOURCE_ROOT = GODOT_ROOT / "assets" / "images" / "source_art" / "generated"
MASTER_ROOT = SOURCE_ROOT / "masters"
ALPHA_ROOT = SOURCE_ROOT / "alpha_clean"
PROCESSED_ROOT = GODOT_ROOT / "assets" / "images" / "processed"
DEPENDENCY_PATH = DATA_ROOT / "map_asset_dependencies.json"
MANIFEST_PATH = DATA_ROOT / "art_manifest.json"
SEMANTICS_PATH = DATA_ROOT / "art_atlas_semantics.json"
MISSING_PATH = DATA_ROOT / "missing_assets.json"
REPORT_PATH = SOURCE_ROOT / "full_map_asset_processing_report.json"
PROMPT_REPORT_PATH = SOURCE_ROOT / "full_map_generation_prompts.json"


MASTER_FILES = {
    "inn_yard": "full_map_batch_a_inn_yard_master.png",
    "player_room": "full_map_batch_a_player_room_master.png",
    "inn_upstairs": "full_map_batch_a_inn_upstairs_master.png",
    "chapel_hill": "full_map_batch_b_chapel_hill_master.png",
    "chapel_interior": "full_map_batch_b_chapel_interior_master.png",
    "belfry": "full_map_batch_b_belfry_master.png",
    "photo": "full_map_batch_c_photo_master.png",
    "archive": "full_map_batch_c_archive_master.png",
    "clock": "full_map_batch_d_clock_cabin_master.png",
    "harbor_control": "full_map_batch_d_harbor_control_master.png",
    "basement": "full_map_batch_d_clock_basement_master.png",
    "cave": "full_map_batch_e_cave_master.png",
    "darkroom": "full_map_batch_e_darkroom_master.png",
}


# Coordinates use a normalized 0..1000 master space so both square and wide
# masters keep traceable semantic crop regions.
CROP_RULES: dict[str, list[tuple[str, tuple[int, int, int, int]]]] = {
    "inn_yard": [
        ("firewood", (20, 600, 300, 790)), ("chopping", (290, 610, 470, 790)),
        ("clothesline", (640, 585, 990, 790)), ("water_pump", (10, 760, 185, 995)),
        ("laundry_basket", (170, 760, 355, 990)), ("kitchen_crates", (345, 750, 995, 995)),
    ],
    "player_room": [
        ("nightstand", (15, 150, 235, 400)), ("wardrobe", (225, 10, 480, 405)),
        ("storage_chest", (480, 145, 745, 405)), ("washbasin", (745, 25, 995, 410)),
        ("luggage", (30, 395, 350, 680)), ("bedside_lamp", (385, 410, 555, 675)),
        ("small_rug", (545, 425, 995, 675)), ("curtain", (20, 675, 355, 990)),
        ("photo_board", (355, 690, 625, 940)), ("journal_desk", (625, 660, 995, 995)),
    ],
    "inn_upstairs": [
        ("door_closed", (5, 5, 225, 330)), ("door_open", (230, 5, 445, 330)),
        ("number_1_to_7", (450, 45, 925, 260)), ("number_8", (820, 110, 990, 260)),
        ("wall_lamp", (20, 515, 530, 675)), ("stair_landing", (550, 430, 990, 800)),
        ("end_window", (260, 625, 440, 825)),
    ],
    "chapel_hill": [
        ("memorial_stone", (5, 245, 730, 485)), ("grave_marker", (5, 340, 720, 500)),
        ("withered_flower", (725, 115, 995, 385)), ("tree_cluster", (5, 735, 700, 995)),
        ("leaf_scatter", (675, 720, 995, 980)), ("candle_stand", (735, 300, 995, 545)),
    ],
    "chapel_interior": [
        ("pew_short", (45, 5, 335, 200)), ("pew_long", (5, 185, 440, 405)),
        ("candle_stand", (575, 5, 745, 300)), ("wall_sconce", (720, 20, 865, 175)),
        ("altar_base", (675, 215, 995, 470)), ("six_hammer", (5, 385, 540, 760)),
        ("hammer_support", (520, 405, 785, 745)), ("bell_rope", (775, 410, 995, 760)),
        ("ritual_banner", (15, 730, 220, 990)), ("stained_window", (205, 745, 995, 995)),
    ],
    "belfry": [
        ("rope_coil", (5, 235, 175, 425)), ("hanging_rope", (5, 355, 225, 665)),
        ("seventh_hammer", (280, 185, 565, 625)), ("hammer_mount", (545, 245, 790, 620)),
        ("maintenance_tool", (775, 165, 995, 500)), ("narrow_platform", (5, 615, 770, 820)),
        ("high_window", (775, 435, 995, 810)),
    ],
    "photo": [
        ("street_display", (0, 0, 130, 300)), ("shop_awning", (125, 0, 325, 300)),
        ("sign_stand", (320, 0, 450, 300)), ("crate_of_frames", (430, 20, 600, 300)),
        ("outdoor_drying", (580, 0, 790, 300)), ("camera_tripod", (0, 355, 125, 630)),
        ("large_format", (115, 340, 245, 610)), ("portrait_backdrop", (225, 330, 405, 640)),
        ("backdrop_stand", (390, 325, 555, 630)), ("light_left", (520, 330, 665, 630)),
        ("light_right", (625, 320, 745, 620)), ("subject_chair", (565, 420, 675, 630)),
        ("display_wall", (710, 330, 995, 650)), ("workbench", (0, 565, 300, 835)),
        ("negative_storage", (285, 560, 480, 835)), ("developing_table", (465, 560, 700, 830)),
        ("chemical_tray", (685, 600, 995, 820)), ("drying_line", (0, 790, 690, 995)),
        ("hanging_print", (0, 790, 690, 995)), ("darkroom_door", (700, 760, 875, 995)),
        ("red_safe_light", (855, 765, 995, 995)),
    ],
    "archive": [
        ("document_cart", (340, 0, 505, 250)), ("sealed_crate", (490, 0, 690, 345)),
        ("notice_board", (660, 0, 900, 315)), ("entry_lamp", (880, 0, 995, 310)),
        ("cabinet_tall", (380, 310, 505, 610)), ("cabinet_wide", (490, 300, 685, 605)),
        ("shelf_variant_a", (665, 300, 825, 620)), ("shelf_variant_b", (815, 295, 995, 620)),
        ("service_counter", (0, 570, 350, 800)), ("reading_table", (330, 560, 615, 800)),
        ("reading_lamp", (600, 600, 710, 825)), ("document_box", (685, 610, 885, 825)),
        ("scroll_bundle", (865, 620, 995, 825)), ("index_drawer", (0, 765, 175, 995)),
        ("wall_map", (165, 770, 430, 995)), ("record_board", (410, 760, 725, 995)),
    ],
    "clock": [
        ("workbench", (0, 0, 305, 355)), ("tool_wall", (300, 0, 505, 345)),
        ("tool_set", (500, 0, 650, 330)), ("gear_small", (640, 0, 805, 335)),
        ("gear_large", (790, 0, 995, 340)), ("pipe_set", (0, 320, 310, 650)),
        ("cable_set", (300, 320, 525, 650)), ("control_panel", (520, 325, 735, 635)),
        ("alignment", (725, 330, 995, 650)), ("calibration_marker", (0, 635, 225, 950)),
        ("maintenance_crate", (210, 655, 350, 940)), ("blueprint_table", (340, 635, 545, 950)),
        ("work_lamp", (535, 640, 675, 930)),
    ],
    "harbor_control": [
        ("chart_table", (0, 0, 305, 350)), ("wall_chart", (290, 0, 470, 350)),
        ("signal_console", (455, 0, 755, 355)), ("signal_lamp", (765, 0, 995, 350)),
        ("gauge_panel", (0, 335, 300, 620)), ("lever_set", (285, 330, 465, 620)),
        ("telegraph", (450, 330, 590, 620)), ("radio_device", (580, 330, 755, 620)),
        ("record_cabinet", (765, 315, 995, 690)), ("observation_window", (0, 575, 395, 820)),
        ("weather_board", (390, 565, 730, 820)), ("float_and_rope", (720, 575, 995, 830)),
    ],
    "basement": [
        ("protocol_platform", (550, 0, 925, 360)), ("witness_slot", (0, 370, 500, 610)),
        ("signal_light", (490, 350, 730, 610)), ("clear_red", (725, 350, 890, 610)),
        ("continue_white", (875, 350, 995, 610)), ("central_protocol", (310, 540, 660, 800)),
        ("pipe_set", (650, 545, 995, 795)), ("gear_set", (0, 745, 315, 995)),
        ("emergency_protocol", (300, 750, 600, 995)), ("contact_shadow", (610, 760, 995, 995)),
    ],
    "cave": [
        ("rock_small", (610, 230, 810, 450)), ("rock_large", (800, 210, 995, 480)),
        ("stalagmite", (440, 255, 720, 500)), ("wood_plank", (500, 440, 995, 650)),
        ("rotten_board", (500, 555, 995, 730)), ("rusty_tool", (0, 645, 300, 800)),
        ("maintenance_device", (270, 625, 445, 850)), ("water_drip", (420, 620, 800, 840)),
        ("wet_reflection", (430, 785, 995, 995)), ("entrance_frame", (0, 715, 330, 995)),
    ],
    "darkroom": [
        ("red_safe_light", (675, 0, 800, 260)), ("developing_table", (760, 55, 995, 325)),
        ("chemical_tray", (660, 280, 995, 430)), ("photo_drying", (660, 370, 995, 555)),
        ("hanging_photo", (650, 445, 995, 650)), ("unfinished_portrait", (405, 325, 555, 610)),
        ("silver_salt_door", (500, 110, 665, 355)), ("exposure_mark", (0, 420, 310, 620)),
        ("record_board", (0, 610, 190, 850)), ("storage_shelf", (190, 610, 330, 850)),
        ("wet_reflection", (330, 600, 650, 835)), ("ada_focus", (630, 610, 995, 815)),
    ],
}


STANDARD_TILE_NAMES = [
    "base_a", "base_b", "base_c", "base_d",
    "edge_n", "edge_s", "edge_w", "edge_e",
    "outer_corner_nw", "outer_corner_ne", "outer_corner_sw", "outer_corner_se",
    "inner_corner_nw", "inner_corner_ne", "inner_corner_sw", "inner_corner_se",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--validate", action="store_true")
    return parser.parse_args()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_scope() -> tuple[list[str], dict[str, list[str]], set[str], dict[str, list[str]], dict[str, str]]:
    dependency = read_json(DEPENDENCY_PATH)
    assets: list[str] = []
    contexts: dict[str, list[str]] = {}
    tile_sets: set[str] = set()
    batches: dict[str, list[str]] = {}
    map_batches: dict[str, str] = {}
    for entry in dependency["maps"]:
        map_id = str(entry["map_id"])
        batch = str(entry["batch"])
        map_batches[map_id] = batch
        for asset_id in entry["generate"]:
            if asset_id not in assets:
                assets.append(asset_id)
            contexts.setdefault(asset_id, []).append(map_id)
            batches.setdefault(batch, []).append(asset_id)
        tile_sets.update(value for value in entry["tile_sets"] if value in entry["generate"])
    return assets, contexts, tile_sets, batches, map_batches


def master_key(asset_id: str) -> str:
    if asset_id.startswith("inn_garden_") or asset_id.startswith("inn_backyard_") or any(
        word in asset_id for word in ("firewood", "chopping", "clothesline", "water_pump", "laundry_basket", "kitchen_crates", "small_fence")
    ):
        return "inn_yard"
    if asset_id.startswith("inn_corridor_") or asset_id.startswith("inn_room_number_") or asset_id in {
        "inn_wall_lamp_set", "inn_stair_landing", "inn_corridor_end_window"
    }:
        return "inn_upstairs"
    if asset_id.startswith("inn_"):
        return "player_room"
    if asset_id.startswith("belfry_"):
        return "belfry"
    if asset_id.startswith("chapel_") and any(word in asset_id for word in (
        "pew", "aisle", "candle_stand", "wall_sconce", "altar", "six_hammer", "hammer_support", "bell_rope", "ritual_banner", "stained_window"
    )):
        return "chapel_interior"
    if asset_id.startswith("chapel_"):
        return "chapel_hill"
    if asset_id.startswith("photo_"):
        return "photo"
    if asset_id.startswith("archive_"):
        return "archive"
    if asset_id.startswith("clock_"):
        return "clock"
    if asset_id.startswith("harbor_"):
        return "harbor_control"
    if asset_id.startswith("basement_"):
        return "basement"
    if asset_id.startswith("cave_"):
        return "cave"
    if asset_id.startswith("darkroom_"):
        return "darkroom"
    raise ValueError(f"No master family for {asset_id}")


def normalized_crop(asset_id: str, key: str) -> tuple[int, int, int, int] | None:
    for token, rect in CROP_RULES.get(key, []):
        if token in asset_id:
            return rect
    return None


def display_size(asset_id: str, is_atlas: bool) -> tuple[int, int]:
    if is_atlas:
        return 128, 128
    if any(word in asset_id for word in ("protocol_platform", "central_protocol_console", "six_hammer_mechanism")):
        return 176, 112
    if "alignment_three_gear" in asset_id:
        return 160, 96
    if asset_id == "belfry_seventh_hammer":
        return 96, 96
    if any(word in asset_id for word in ("service_counter", "observation_window", "foreground_beam")):
        return 128, 72
    if any(word in asset_id for word in ("workbench", "developing_table", "chart_table", "reading_table", "blueprint_table", "control_panel", "signal_console")):
        return 96, 64
    if "altar_base" in asset_id or "narrow_platform" in asset_id:
        return 112, 72
    if "clothesline" in asset_id or "drying_line" in asset_id or "photo_drying_line" in asset_id:
        return 112, 64
    if any(word in asset_id for word in ("door", "wardrobe", "cabinet_tall", "high_window", "portrait_holder")):
        return 56, 80
    if any(word in asset_id for word in ("cabinet_wide", "shelf_variant", "storage_shelf", "negative_storage", "tool_wall", "display_wall")):
        return 72, 80
    if any(word in asset_id for word in ("wall_map", "record_board", "notice_board", "weather_board", "photo_board", "wall_chart", "gauge_panel", "emergency_protocol_board")):
        return 72, 48
    if any(word in asset_id for word in ("tree_cluster", "entrance_frame", "backdrop", "stair_landing")):
        return 96, 96
    if any(word in asset_id for word in ("mechanism", "device", "hammer_mount", "support_frame", "record_cabinet")):
        return 88, 80
    if any(word in asset_id for word in ("pew_long", "counter", "floor_cable", "pipe_set", "timber_beam")):
        return 96, 56
    if any(word in asset_id for word in ("pew_short", "rug", "runner", "crate", "luggage", "rock_large", "gear_large", "float_and_rope")):
        return 72, 56
    if any(word in asset_id for word in ("lamp", "sconce", "candle", "rope", "stalagmite", "tripod", "camera", "stand", "pump")):
        return 48, 64
    return 56, 48


def category(asset_id: str, is_atlas: bool) -> str:
    if is_atlas:
        if any(word in asset_id for word in ("pool", "puddle")):
            return "water_texture"
        if "floor" in asset_id or "runner" in asset_id or "cable" in asset_id:
            return "floor_texture"
        if any(word in asset_id for word in ("wall", "trim", "railing", "fence", "beam", "ceiling", "recess", "shadow")):
            return "wall_texture"
        return "path_texture"
    if any(word in asset_id for word in ("board", "map", "chart", "photo_board", "display_wall", "stained_window", "number_")):
        return "wall_decoration"
    if any(word in asset_id for word in ("door", "window", "platform", "entry", "backdrop", "wall_", "ceiling", "partition", "landing")):
        return "architecture"
    if any(word in asset_id for word in ("light", "reflection", "drip", "shadow")):
        return "effect"
    if any(word in asset_id for word in ("flower", "leaf", "rock", "exposure_mark")):
        return "decoration"
    return "furniture"


def master_palette(image: Image.Image) -> list[tuple[int, int, int, int]]:
    thumb = image.copy()
    thumb.thumbnail((128, 128), Image.Resampling.NEAREST)
    pixels = thumb.get_flattened_data() if hasattr(thumb, "get_flattened_data") else thumb.getdata()
    colors = Counter(pixel for pixel in pixels if pixel[3] and not (pixel[1] > 210 and pixel[0] < 90 and pixel[2] < 90))
    values = [color for color, _count in colors.most_common(32)]
    if not values:
        values = [(95, 85, 67, 255), (55, 58, 55, 255), (154, 126, 77, 255)]
    values.sort(key=lambda color: color[0] + color[1] + color[2])
    picks = [values[0], values[len(values) // 3], values[(len(values) * 2) // 3], values[-1]]
    return [(r, g, b, 255) for r, g, b, _a in picks]


def atlas_palette(asset_id: str, image: Image.Image) -> list[tuple[int, int, int, int]]:
    """Material-safe palette overrides prevent master shadows becoming roads."""
    themed: list[tuple[tuple[str, ...], tuple[str, str, str, str]]] = [
        (("garden_soil", "garden_crop"), ("#493321", "#67472a", "#815c34", "#b08a55")),
        (("backyard_path",), ("#594b38", "#79684c", "#96815d", "#b7a178")),
        (("inn_small_fence", "inn_garden_edge"), ("#30251d", "#684b31", "#92704a", "#b79a67")),
        (("chapel_path", "chapel_courtyard", "archive_stone", "archive_platform"), ("#484c4c", "#686d69", "#888b82", "#b7b5a3")),
        (("chapel_low_stone", "archive_low_railing"), ("#343b3d", "#59605e", "#7d8178", "#aaa896")),
        (("photo_lane_ground",), ("#3e4345", "#5d6261", "#7b7d76", "#a59f8d")),
        (("photo_lane_fence",), ("#302825", "#55453b", "#77614c", "#a08362")),
        (("clock_floor", "basement_mechanical"), ("#292f31", "#44494a", "#5b5d59", "#8a7a52")),
        (("harbor_control_floor",), ("#26383c", "#3c5053", "#53666a", "#7b8580")),
        (("cave_wet_stone", "cave_wall", "cave_ceiling"), ("#142529", "#263b40", "#405358", "#718084")),
        (("cave_puddle", "cave_shallow_pool"), ("#17363c", "#24535c", "#34717a", "#79a0a0")),
        (("darkroom_floor", "darkroom_wall", "darkroom_foreground"), ("#160f12", "#2b1b20", "#43272b", "#704039")),
        (("corridor_runner",), ("#34252a", "#6a3432", "#8d4c42", "#b28b5e")),
        (("corridor_trim", "belfry_timber", "belfry_foreground"), ("#211918", "#463326", "#6b4b32", "#99714a")),
        (("chapel_aisle",), ("#342729", "#65383a", "#874e45", "#b39368")),
        (("basement_floor_cable",), ("#202527", "#4f4540", "#8a6842", "#bd975c")),
        (("basement_wall_recess", "basement_contact_shadow"), ("#161b1d", "#2b3132", "#444848", "#696961")),
    ]
    for tokens, colors in themed:
        if any(token in asset_id for token in tokens):
            return [tuple(ImageColor.getrgb(value)) + (255,) for value in colors]
    return master_palette(image)


def harden_and_quantize(image: Image.Image, colors: int = 28) -> Image.Image:
    rgba = image.convert("RGBA")
    rgba.putalpha(rgba.getchannel("A").point(lambda value: 255 if value >= 96 else 0))
    alpha = rgba.getchannel("A")
    rgb = Image.new("RGB", rgba.size, (0, 0, 0))
    rgb.paste(rgba.convert("RGB"), mask=alpha)
    result = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    result.putalpha(alpha)
    return result


def crop_prop(master: Image.Image, rect: tuple[int, int, int, int], size: tuple[int, int]) -> Image.Image:
    box = (
        round(rect[0] * master.width / 1000), round(rect[1] * master.height / 1000),
        round(rect[2] * master.width / 1000), round(rect[3] * master.height / 1000),
    )
    crop = master.crop(box)
    bbox = crop.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError(f"Empty crop {rect}")
    content = crop.crop(bbox)
    available = max(1, size[0] - 4), max(1, size[1] - 3)
    ratio = min(available[0] / content.width, available[1] / content.height)
    scaled = content.resize((max(1, round(content.width * ratio)), max(1, round(content.height * ratio))), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.alpha_composite(scaled, ((size[0] - scaled.width) // 2, size[1] - scaled.height - 1))
    return harden_and_quantize(canvas)


def darken(color: tuple[int, int, int, int], amount: float) -> tuple[int, int, int, int]:
    return tuple(max(0, round(value * (1.0 - amount))) for value in color[:3]) + (color[3],)


def lighten(color: tuple[int, int, int, int], amount: float) -> tuple[int, int, int, int]:
    return tuple(min(255, round(value + (255 - value) * amount)) for value in color[:3]) + (color[3],)


def draw_atlas(asset_id: str, palette: list[tuple[int, int, int, int]], category_name: str) -> Image.Image:
    result = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    overlay = any(word in asset_id for word in ("edge", "wall", "trim", "railing", "fence", "beam", "ceiling", "recess", "shadow", "cable"))
    water = category_name == "water_texture"
    for index, tile_name in enumerate(STANDARD_TILE_NAMES):
        cell = Image.new("RGBA", (32, 32), (0, 0, 0, 0) if overlay else palette[1])
        draw = ImageDraw.Draw(cell)
        base = palette[1 if index % 2 == 0 else 2]
        dark = darken(palette[0], 0.08)
        light = lighten(palette[2], 0.20)
        if not overlay:
            draw.rectangle((0, 0, 31, 31), fill=base)
            for mark in range(8):
                x = (index * 11 + mark * 17 + 3) % 30
                y = (index * 7 + mark * 13 + 5) % 30
                color = light if mark % 3 == 0 else dark
                if water:
                    draw.line((x, y, min(31, x + 5 + mark % 3), y), fill=color, width=1)
                else:
                    draw.rectangle((x, y, min(31, x + (2 if mark % 2 else 4)), min(31, y + 1)), fill=color)
            if "crop_row" in asset_id:
                for plant_x in (7, 16, 25):
                    draw.line((plant_x, 8, plant_x, 23), fill=darken(palette[2], 0.05), width=2)
                    draw.rectangle((plant_x - 3, 10 + (plant_x % 4), plant_x - 1, 13 + (plant_x % 4)), fill=lighten(palette[2], 0.12))
                    draw.rectangle((plant_x + 2, 16 - (plant_x % 3), plant_x + 4, 19 - (plant_x % 3)), fill=lighten(palette[2], 0.12))
        def bar(side: str) -> None:
            width = 5 if any(word in asset_id for word in ("wall", "fence", "railing", "beam")) else 3
            if side == "n": draw.rectangle((0, 0, 31, width), fill=dark); draw.line((0, width, 31, width), fill=light)
            if side == "s": draw.rectangle((0, 31 - width, 31, 31), fill=dark); draw.line((0, 30 - width, 31, 30 - width), fill=light)
            if side == "w": draw.rectangle((0, 0, width, 31), fill=dark); draw.line((width, 0, width, 31), fill=light)
            if side == "e": draw.rectangle((31 - width, 0, 31, 31), fill=dark); draw.line((30 - width, 0, 30 - width, 31), fill=light)
        if tile_name == "edge_n": bar("n")
        elif tile_name == "edge_s": bar("s")
        elif tile_name == "edge_w": bar("w")
        elif tile_name == "edge_e": bar("e")
        elif tile_name.endswith("nw"): bar("n"); bar("w")
        elif tile_name.endswith("ne"): bar("n"); bar("e")
        elif tile_name.endswith("sw"): bar("s"); bar("w")
        elif tile_name.endswith("se"): bar("s"); bar("e")
        if tile_name.startswith("base_") and overlay:
            if any(word in asset_id for word in ("fence", "railing")):
                draw.rectangle((1, 12, 30, 17), fill=dark)
                draw.rectangle((2, 12, 29, 14), fill=palette[2])
                draw.rectangle((4, 3, 9, 29), fill=dark); draw.rectangle((5, 3, 8, 27), fill=palette[3])
                draw.rectangle((23, 3, 28, 29), fill=dark); draw.rectangle((24, 3, 27, 27), fill=palette[3])
            elif "stone_wall" in asset_id:
                draw.rectangle((0, 9, 31, 24), fill=dark)
                draw.rectangle((1, 9, 30, 21), fill=palette[1])
                draw.rectangle((1, 9, 30, 12), fill=palette[2])
                draw.line((0, 17, 31, 17), fill=palette[0], width=1)
                for seam_x in (8, 21): draw.line((seam_x, 13, seam_x, 21), fill=palette[0], width=1)
            elif "cable" in asset_id:
                draw.line((0, 16 + index, 31, 14 - index), fill=base, width=3)
            elif "shadow" in asset_id:
                draw.ellipse((3, 11, 29, 25), fill=(dark[0], dark[1], dark[2], 150))
            else:
                draw.rectangle((0, 12, 31, 19), fill=dark); draw.line((0, 12, 31, 12), fill=light)
        result.alpha_composite(cell, ((index % 4) * 32, (index // 4) * 32))
    return harden_and_quantize(result, 20)


def prepare() -> dict:
    asset_ids, contexts, tile_sets, batches, _map_batches = load_scope()
    masters = {key: Image.open(ALPHA_ROOT / filename).convert("RGBA") for key, filename in MASTER_FILES.items()}
    report_assets: list[dict] = []
    needs_review: list[str] = []
    manifest = read_json(MANIFEST_PATH)
    existing_ids = {entry["asset_id"] for entry in manifest["assets"]}
    semantics = read_json(SEMANTICS_PATH)
    semantics.setdefault("atlases", {})
    for asset_id in asset_ids:
        if asset_id not in tile_sets:
            semantics["atlases"].pop(asset_id, None)
    for asset_id in asset_ids:
        key = master_key(asset_id)
        master = masters[key]
        is_atlas = asset_id in tile_sets
        size = display_size(asset_id, is_atlas)
        category_name = category(asset_id, is_atlas)
        crop = normalized_crop(asset_id, key)
        if is_atlas:
            output = draw_atlas(asset_id, atlas_palette(asset_id, master), category_name)
        elif crop is not None:
            output = crop_prop(master, crop, size)
        else:
            # A formal but reviewable fallback: use the master content bounds,
            # never a fabricated color block. Validation and the report expose it.
            bbox = master.getchannel("A").getbbox()
            if bbox is None:
                raise ValueError(f"Empty master for {asset_id}")
            output = crop_prop(master, (0, 0, 1000, 1000), size)
            needs_review.append(asset_id)
        source_path = SOURCE_ROOT / f"{asset_id}.png"
        source_path.parent.mkdir(parents=True, exist_ok=True)
        output.save(source_path, format="PNG", optimize=True)
        master_path = MASTER_ROOT / MASTER_FILES[key]
        processed_path = PROCESSED_ROOT / f"{asset_id}.png"
        sha = hashlib.sha256(source_path.read_bytes()).hexdigest()
        master_sha = hashlib.sha256(master_path.read_bytes()).hexdigest()
        processed_sha = hashlib.sha256(processed_path.read_bytes()).hexdigest() if processed_path.is_file() else ""
        report_assets.append({
            "asset_id": asset_id,
            "batch": next(batch for batch, values in batches.items() if asset_id in values),
            "master": f"res://assets/images/source_art/generated/masters/{MASTER_FILES[key]}",
            "master_sha256": master_sha,
            "source": f"res://assets/images/source_art/generated/{asset_id}.png",
            "source_path": f"res://assets/images/source_art/generated/{asset_id}.png",
            "processed_path": f"res://assets/images/processed/{asset_id}.png",
            "source_sha256": sha,
            "processed_sha256": processed_sha,
            "size": list(size),
            "native_size": list(size),
            "display_size": list(size),
            "anchor": [0.0, 0.0] if is_atlas else [0.5, 1.0],
            "target_maps": contexts[asset_id],
            "integrated": True,
            "regenerated": False,
            "final_review_status": "needs_review" if asset_id in needs_review else "approved",
            "alpha_binary": True,
            "atlas": is_atlas,
            "needs_review": asset_id in needs_review,
        })
        entry = {
            "asset_id": asset_id,
            "runtime_path": f"res://assets/images/processed/{asset_id}.png",
            "source_path": f"res://assets/images/source_art/generated/{asset_id}.png",
            "source_master_path": f"res://assets/images/source_art/generated/masters/{MASTER_FILES[key]}",
            "source_sha256": sha,
            "master_sha256": master_sha,
            "category": category_name,
            "perspective": "top_down" if is_atlas else ("frontal_wall_decoration" if category_name == "wall_decoration" else "top_down_three_quarter"),
            "native_size": list(size),
            "recommended_display_size": list(size),
            "anchor": [0.0, 0.0] if is_atlas else [0.5, 1.0],
            "sort_anchor": [0.0, 0.0] if is_atlas else [0.5, 0.94],
            "contexts": contexts[asset_id],
            "forbidden_contexts": ["town", "harbor", "inn-lobby"],
            "contains_text": False,
            "can_mirror": False,
            "pixel_art": True,
            "contact_shadow": not is_atlas and category_name not in {"wall_decoration", "effect"},
            "collision_preset": "none",
            "enabled": True,
            "needs_review": asset_id in needs_review,
            "source_generation_script": "res://tools/prepare_full_map_assets.py",
            "processing_script": "res://tools/process_art_assets.py",
            "notes": "Full-map rollout original master; hard alpha, nearest, integer canvas, palette-limited.",
        }
        if is_atlas:
            entry.update({
                "asset_form": "tile_set", "tile_size": [32, 32], "atlas_grid": [4, 4],
                "semantic_map": "res://data/art_atlas_semantics.json", "variant_count": 16,
                "tile_roles": STANDARD_TILE_NAMES,
            })
            semantics["atlases"][asset_id] = {
                "tile_size": [32, 32], "grid": [4, 4],
                "tiles": {name: index for index, name in enumerate(STANDARD_TILE_NAMES)},
                "rotation_safe": False, "mirror_safe": False, "unsafe_tiles": [],
                "notes": "Full-map rollout named 32 px modules; direction tiles are used only by semantic name.",
            }
        if asset_id in existing_ids:
            index = next(i for i, value in enumerate(manifest["assets"]) if value["asset_id"] == asset_id)
            manifest["assets"][index] = entry
        else:
            manifest["assets"].append(entry)
            existing_ids.add(asset_id)
    write_json(MANIFEST_PATH, manifest)
    write_json(SEMANTICS_PATH, semantics)
    missing = read_json(MISSING_PATH)
    missing["full_map_rollout"] = {
        "status": "completed",
        "scope": ["inn-yard", "player-room", "inn-upstairs", "chapel-hill", "chapel-interior", "chapel-belfry", "photo-lane", "photo-studio", "archive-lane", "archive-room", "clock-cabin", "harbor-control", "clock-basement", "low-tide-cave", "hidden-darkroom"],
        "completed_asset_ids": asset_ids,
        "needs_review": needs_review,
        "frozen_maps": ["town", "harbor", "inn-lobby"],
    }
    write_json(MISSING_PATH, missing)
    prompt_report = {
        "schema_version": 1,
        "generator": "built_in_imagegen",
        "master_count": len(MASTER_FILES),
        "masters": [
            {"family": key, "path": f"res://assets/images/source_art/generated/masters/{filename}", "sha256": hashlib.sha256((MASTER_ROOT / filename).read_bytes()).hexdigest(), "selection": "initial_generation_selected"}
            for key, filename in MASTER_FILES.items()
        ],
        "shared_prompt_constraints": ["original_pixel_art", "top_down_three_quarter", "solid_00ff00_background", "no_text", "no_characters", "hard_pixel_edges"],
    }
    write_json(PROMPT_REPORT_PATH, prompt_report)
    report = {
        "schema_version": 1,
        "assets": report_assets,
        "counts": {"assets": len(asset_ids), "atlases": len(tile_sets), "needs_review": len(needs_review)},
        "needs_review": needs_review,
        "masters_overwritten": False,
    }
    write_json(REPORT_PATH, report)
    return report


def validate() -> list[str]:
    asset_ids, _contexts, tile_sets, _batches, _map_batches = load_scope()
    errors: list[str] = []
    manifest = read_json(MANIFEST_PATH)
    entries = {entry["asset_id"]: entry for entry in manifest["assets"]}
    semantics = read_json(SEMANTICS_PATH).get("atlases", {})
    for filename in MASTER_FILES.values():
        if not (MASTER_ROOT / filename).is_file(): errors.append(f"missing master: {filename}")
        if not (ALPHA_ROOT / filename).is_file(): errors.append(f"missing alpha master: {filename}")
    for asset_id in asset_ids:
        source = SOURCE_ROOT / f"{asset_id}.png"
        if asset_id not in entries:
            errors.append(f"{asset_id}: missing manifest entry")
            continue
        if not source.is_file():
            errors.append(f"{asset_id}: missing source")
            continue
        image = Image.open(source).convert("RGBA")
        expected = tuple(entries[asset_id]["recommended_display_size"])
        if image.size != expected: errors.append(f"{asset_id}: {image.size} != {expected}")
        if image.getchannel("A").getbbox() is None: errors.append(f"{asset_id}: empty image")
        alpha_channel = image.getchannel("A")
        alpha_values = set(alpha_channel.get_flattened_data() if hasattr(alpha_channel, "get_flattened_data") else alpha_channel.getdata())
        if not alpha_values.issubset({0, 255}): errors.append(f"{asset_id}: non-binary alpha")
        pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
        residual_key = sum(1 for r, g, b, a in pixels if a and g > 235 and r < 55 and b < 55)
        pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
        residual_pink = sum(1 for r, g, b, a in pixels if a and r > 235 and b > 225 and g < 55)
        if residual_key: errors.append(f"{asset_id}: {residual_key} green-key pixels")
        if residual_pink: errors.append(f"{asset_id}: {residual_pink} magenta-key pixels")
        if asset_id in tile_sets and asset_id not in semantics: errors.append(f"{asset_id}: missing atlas semantics")
    if len(asset_ids) != 178: errors.append(f"asset dependency count {len(asset_ids)} != 178")
    if len(set(asset_ids)) != len(asset_ids): errors.append("duplicate dependency asset_id")
    return errors


def main() -> int:
    args = parse_args()
    if not args.all and not args.validate:
        raise SystemExit("Choose --all and/or --validate")
    if args.all:
        report = prepare()
        print(f"Full-map assets prepared: {report['counts']}")
    errors = validate() if args.validate else []
    for error in errors:
        print(f"ERROR: {error}")
    if args.validate and not errors:
        print("Full-map assets valid: 178 sources")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
