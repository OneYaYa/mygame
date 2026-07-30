#!/usr/bin/env python3
"""Compose the 15 remaining map layouts from the full-map dependency matrix.

This is a deterministic authoring helper, not runtime generation.  Stable
gameplay overrides and collision IDs are preserved from each formal layout;
only the Godot art composition, theme, tile references, props, lights, and
review zones are rebuilt.  The three P0 reference layouts are never opened.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


GODOT_ROOT = Path(__file__).resolve().parents[1]
LAYOUT_ROOT = GODOT_ROOT / "data" / "art_layouts"
DEPENDENCY_PATH = GODOT_ROOT / "data" / "map_asset_dependencies.json"
MANIFEST_PATH = GODOT_ROOT / "data" / "art_manifest.json"


SLOTS: dict[str, list[tuple[int, int]]] = {
    "inn-yard": [(956, 360), (884, 391), (300, 338), (276, 488), (329, 492), (1018, 405)],
    "player-room": [(202, 242), (622, 250), (604, 403), (126, 390), (520, 414), (216, 218), (374, 390), (382, 170), (500, 175), (512, 330)],
    "inn-upstairs": [(142, 235), (812, 248), (448, 164), (790, 164), (548, 169), (105, 366), (858, 183)],
    "chapel-hill": [(180, 520), (260, 560), (205, 590), (85, 680), (830, 640), (720, 430)],
    "chapel-interior": [(220, 330), (560, 330), (190, 260), (618, 165), (384, 215), (384, 286), (384, 235), (656, 285), (180, 162), (384, 155)],
    "chapel-belfry": [(680, 365), (210, 245), (432, 250), (432, 310), (675, 330), (430, 405), (660, 165)],
    "photo-lane": [(565, 320), (890, 410), (726, 440), (790, 485), (650, 300)],
    "photo-studio": [(336, 345), (350, 330), (420, 260), (420, 330), (285, 350), (540, 350), (430, 385), (656, 185), (180, 350), (190, 255), (650, 360), (650, 400), (640, 250), (540, 180), (730, 330), (716, 190)],
    "archive-lane": [(815, 390), (915, 400), (800, 290), (730, 340)],
    "archive-room": [(680, 275), (730, 355), (150, 278), (185, 365), (430, 225), (430, 360), (430, 315), (685, 410), (735, 420), (140, 400), (300, 160), (575, 160)],
    "clock-cabin": [(180, 340), (170, 185), (265, 210), (610, 380), (652, 330), (640, 210), (600, 425), (390, 225), (390, 355), (390, 170), (660, 415), (170, 410), (245, 300)],
    "harbor-control": [(220, 360), (285, 165), (520, 350), (610, 225), (520, 190), (610, 355), (635, 405), (565, 410), (670, 300), (390, 165), (490, 165), (170, 410)],
    "clock-basement": [(450, 395), (255, 205), (315, 175), (380, 155), (405, 225), (450, 205), (495, 225), (275, 445), (625, 445), (450, 360), (790, 390), (110, 400), (180, 185)],
    "low-tide-cave": [(210, 390), (725, 405), (655, 330), (425, 410), (505, 425), (690, 265), (720, 315), (560, 230), (520, 390), (100, 350)],
    "hidden-darkroom": [(405, 175), (220, 360), (250, 395), (410, 250), (405, 280), (590, 260), (730, 330), (310, 180), (170, 175), (140, 380), (340, 405), (590, 200)],
}


EXTRA_OBJECTS: dict[str, list[dict]] = {
    "inn-yard": [
        {"object_id": "inn_edge_tree_west", "asset_id": "prop_tree", "position": [82, 392], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "inn_edge_tree_east", "asset_id": "prop_tree", "position": [1080, 650], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "inn_edge_bush_south", "asset_id": "prop_bush", "position": [365, 675], "layer": "WorldObjects", "contact_shadow": True},
    ],
    "player-room": [
        {"object_id": "room_bed_reuse", "asset_id": "prop_bed", "position": [175, 330], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "room_fireplace_reuse", "asset_id": "prop_fireplace", "position": [635, 205], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "room_chair_reuse", "asset_id": "generic_chair_left", "position": [438, 350], "layer": "WorldObjects", "contact_shadow": True},
    ],
    "inn-upstairs": [
        *[{"object_id": f"corridor_door_{index}", "asset_id": "inn_corridor_door_closed", "position": [130 + index * 105, 244], "layer": "WallDecorations", "contact_shadow": False} for index in range(1, 7)],
    ],
    "chapel-hill": [
        {"object_id": "chapel_hill_bench", "asset_id": "prop_bench", "position": [770, 560], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "chapel_tree_cluster_west", "asset_id": "chapel_tree_cluster", "position": [90, 430], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "chapel_tree_cluster_east", "asset_id": "chapel_tree_cluster", "position": [1030, 450], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "chapel_memorial_extra_a", "asset_id": "chapel_small_grave_marker_set", "position": [260, 600], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "chapel_memorial_extra_b", "asset_id": "chapel_memorial_stone_set", "position": [315, 565], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "chapel_foreground_tree_west", "asset_id": "prop_tree", "position": [92, 720], "layer": "Foreground", "contact_shadow": False},
        {"object_id": "chapel_foreground_tree_east", "asset_id": "prop_tree", "position": [1028, 720], "layer": "Foreground", "contact_shadow": False},
    ],
    "photo-lane": [
        {"object_id": "photo_lane_tree_west_edge", "asset_id": "prop_tree", "position": [75, 650], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "photo_lane_bush_east_edge", "asset_id": "prop_bush", "position": [1070, 610], "layer": "WorldObjects", "contact_shadow": True},
    ],
    "archive-lane": [
        {"object_id": "archive_lane_bush_west_edge", "asset_id": "prop_bush", "position": [120, 560], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "archive_lane_bush_east_edge", "asset_id": "prop_bush", "position": [1000, 560], "layer": "WorldObjects", "contact_shadow": True},
    ],
    "chapel-interior": [
        {"object_id": "chapel_pew_left_extra", "asset_id": "chapel_pew_long", "position": [220, 390], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "chapel_pew_right_extra", "asset_id": "chapel_pew_long", "position": [560, 390], "layer": "WorldObjects", "contact_shadow": True},
    ],
    "archive-room": [
        {"object_id": "archive_chair_front", "asset_id": "generic_chair_front", "position": [390, 405], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "archive_chair_back", "asset_id": "generic_chair_back", "position": [470, 305], "layer": "WorldObjects", "contact_shadow": True},
    ],
    "hidden-darkroom": [
        {"object_id": "darkroom_chair", "asset_id": "generic_chair_left", "position": [280, 385], "layer": "WorldObjects", "contact_shadow": True},
    ],
    "clock-basement": [
        {"object_id": "witness_slot_extra_4", "asset_id": "basement_witness_slot_empty", "position": [450, 145], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "witness_slot_extra_5", "asset_id": "basement_witness_slot_empty", "position": [520, 155], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "witness_slot_extra_6", "asset_id": "basement_witness_slot_active", "position": [585, 175], "layer": "WorldObjects", "contact_shadow": True},
        {"object_id": "witness_slot_extra_7", "asset_id": "basement_witness_slot_locked", "position": [645, 205], "layer": "WorldObjects", "contact_shadow": True},
    ],
}


OUTDOOR_KEEP_IDS = {
    "inn-yard": {"inn_main_art", "inn_shed_art", "inn_tree_left", "inn_tree_left_foreground", "pond_bush_inn_a", "pond_bush_inn_b"},
    "chapel-hill": {"chapel_art", "chapel_tree_left", "chapel_tree_right"},
    "photo-lane": {"studio_building_art", "frame_shop_art", "photo_tree_back", "photo_bush_left"},
    "archive-lane": {"archive_building_art", "archive_bush_left", "archive_bush_pond"},
}


THEMES = {
    "player-room": "inn_warm", "inn-upstairs": "inn_warm",
    "chapel-interior": "chapel_archive", "chapel-belfry": "chapel_archive", "archive-room": "chapel_archive",
    "photo-studio": "photo_harbor", "harbor-control": "photo_harbor",
    "clock-cabin": "clock_mechanical", "clock-basement": "clock_mechanical",
    "hidden-darkroom": "hidden_darkroom",
}


TINTS = {
    "inn-yard": "#fff0cf", "player-room": "#ffe3b8", "inn-upstairs": "#e8c99e",
    "chapel-hill": "#dfe0cf", "chapel-interior": "#d7d4c4", "chapel-belfry": "#b9c3bd",
    "photo-lane": "#d9d7c8", "photo-studio": "#d5c4b7", "archive-lane": "#d8d8c8", "archive-room": "#d7d2bb",
    "clock-cabin": "#d7c89c", "harbor-control": "#c6d3cf", "clock-basement": "#c6b982",
    "low-tide-cave": "#9bb5b4", "hidden-darkroom": "#b47a72",
}


LIGHTS = {
    "inn-yard": [([520, 340], "#f3bd68", 0.38, 74), ([650, 342], "#f3bd68", 0.38, 74), ([955, 312], "#e4a95e", 0.26, 58)],
    "player-room": [([632, 180], "#ef9d58", 0.48, 88), ([216, 202], "#f3bd68", 0.38, 62)],
    "inn-upstairs": [([250, 170], "#edb66b", 0.26, 70), ([550, 170], "#edb66b", 0.25, 70), ([790, 166], "#c6b379", 0.18, 62)],
    "chapel-hill": [([720, 405], "#e6b96b", 0.24, 70), ([390, 360], "#d5c48a", 0.18, 74)],
    "chapel-interior": [([190, 245], "#efbc6d", 0.34, 74), ([578, 245], "#efbc6d", 0.34, 74), ([384, 190], "#a9c1c0", 0.20, 92)],
    "chapel-belfry": [([660, 160], "#a8c9ce", 0.34, 98), ([690, 340], "#e3a85c", 0.20, 58)],
    "photo-lane": [([310, 340], "#ecc178", 0.26, 70), ([890, 390], "#d5a767", 0.22, 62)],
    "photo-studio": [([285, 330], "#e6bd78", 0.38, 86), ([540, 330], "#e6bd78", 0.38, 86), ([715, 190], "#bd5049", 0.22, 54)],
    "archive-lane": [([430, 330], "#e1c27c", 0.22, 66), ([675, 330], "#e1c27c", 0.22, 66)],
    "archive-room": [([430, 310], "#e6c87d", 0.36, 76), ([430, 180], "#d3ba78", 0.18, 64)],
    "clock-cabin": [([245, 285], "#e0ad5b", 0.40, 82), ([390, 305], "#c8a95d", 0.20, 70)],
    "harbor-control": [([220, 330], "#e6bd72", 0.34, 82), ([520, 300], "#5ca8a9", 0.18, 70), ([390, 155], "#86aeb2", 0.16, 78)],
    "clock-basement": [([450, 315], "#d2a64e", 0.42, 118), ([275, 410], "#cb5148", 0.36, 76), ([625, 410], "#d9ded5", 0.30, 76)],
    "low-tide-cave": [([720, 285], "#e0a45d", 0.40, 84), ([470, 330], "#6aa3a4", 0.16, 70)],
    "hidden-darkroom": [([405, 170], "#b94b48", 0.50, 104), ([590, 230], "#d56a60", 0.38, 88), ([220, 350], "#a6423f", 0.20, 64)],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--validate", action="store_true")
    return parser.parse_args()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def layer_for(asset_id: str, category: str) -> str:
    if any(word in asset_id for word in ("wall_", "window", "door", "photo_board", "record_board", "notice_board", "number_", "display_wall", "map", "chart", "sconce", "curtain")):
        return "WallDecorations"
    if any(word in asset_id for word in ("rug", "leaf", "reflection", "exposure_mark", "contact_shadow")):
        return "GroundDetails"
    if any(word in asset_id for word in ("foreground", "ceiling")):
        return "Foreground"
    if category == "effect" and "light" not in asset_id:
        return "GroundDetails"
    return "WorldObjects"


def art_object(asset_id: str, position: tuple[int, int], entry: dict, suffix: str = "") -> dict:
    layer = layer_for(asset_id, str(entry.get("category", "furniture")))
    item = {
        "object_id": f"rollout_{asset_id}{suffix}", "asset_id": asset_id,
        "position": list(position), "anchor": entry.get("anchor", [0.5, 1.0]),
        "sort_y": position[1] if layer in {"WorldObjects", "ArchitectureFront"} else 0,
        "layer": layer,
        "contact_shadow": bool(entry.get("contact_shadow", False)) and layer == "WorldObjects",
    }
    if item["contact_shadow"]:
        size = entry.get("recommended_display_size", [56, 48])
        item["shadow_size"] = [max(16, round(size[0] * 0.60)), max(6, round(size[1] * 0.11))]
    return item


def interior_shell(layout: dict, theme: str) -> dict:
    room = [int(value) for value in layout["canvas"]["room_rect"]]
    x, y, width, height = room
    count = max(3, (width - 32) // 32)
    tint = TINTS[layout["map_id"]]
    return {
        "theme": theme,
        "wall_asset": "interior_wall_modular_set", "corner_asset": "interior_corner_set", "baseboard_asset": "baseboard_set",
        "wall_segments": [{"position": [x + 16, y], "count": count, "pattern": ["straight", "panel_light", "straight", "panel_dense"], "tint": tint}],
        "corners": [{"position": [x, y], "tile": "inside_left", "tint": tint}, {"position": [x + width - 48, y], "tile": "inside_right", "tint": tint}],
        "baseboard_segments": [{"position": [x + 16, y + 48], "count": count, "pattern": ["straight", "straight", "worn_straight"], "start": "left_stop", "end": "right_stop"}],
    }


def stamp(asset_id: str, tile: str, cell: tuple[int, int], layer: str = "PathTiles", tint: str = "#ffffff") -> dict:
    return {"layer": layer, "asset_id": asset_id, "tile": tile, "cell": list(cell), "tint": tint}


def atlas_for(map_id: str, layout: dict, tile_sets: list[str]) -> dict:
    result: dict = {"cell_size": [32, 32], "replaced_ground_shapes": [], "terrain_masks": [], "water_masks": [], "shore_stamps": []}
    if map_id == "inn-yard":
        result.update({
            "replaced_ground_shapes": ["inn_entry_path", "inn_front_walk", "inn_kitchen_garden", "inn_pond"],
            "base_fill": {"asset_id": "grass_base_variants", "base_tiles": ["base_a", "base_b", "base_c", "base_d", "base_e", "base_f"], "variation_tiles": ["dense_grass_a", "cool_patch_a"], "variation_ratio": 0.10, "seed": "full:A:inn-yard"},
            "terrain_masks": [
                {"mask_id": "inn_backyard_routes", "asset_id": "inn_backyard_path_set", "rects": [[17, -1, 2, 24], [14, 10, 8, 2], [25, 9, 5, 2]], "center_tiles": ["base_a", "base_b"], "seed": "inn-yard:path"},
                {"mask_id": "inn_garden_soil", "asset_id": "inn_garden_soil_tile_set", "rects": [[25, 14, 7, 5]], "center_tiles": ["base_a", "base_b", "base_c"], "seed": "inn-yard:soil"},
                {"mask_id": "inn_garden_crops", "asset_id": "inn_garden_crop_row_set", "rects": [[26, 15, 5, 3]], "center_tiles": ["base_a", "base_b", "base_c", "base_d"], "seed": "inn-yard:crops"},
            ],
            "water_masks": [{"mask_id": "inn_yard_pond", "asset_id": "water_shallow_deep_set", "rows": [[14, 3, 6], [15, 2, 8], [16, 2, 8], [17, 2, 7], [18, 3, 7]], "shallow_tiles": ["shallow_a", "shallow_b"], "deep_tiles": ["deep_a", "deep_b", "deep_c"], "shore_asset": "natural_shoreline_set", "shore_material": "grass", "use_transitions": True, "transition_asset": "water_transition_patch_set", "seed": "inn-yard:pond"}],
        })
        for x in range(24, 33): result["shore_stamps"].append(stamp("inn_small_fence_set", "base_a", (x, 13), "ShoreTiles"))
        for cell, tile in [((25, 14), "outer_corner_nw"), ((31, 14), "outer_corner_ne"), ((25, 18), "outer_corner_sw"), ((31, 18), "outer_corner_se")]: result["shore_stamps"].append(stamp("inn_garden_edge_set", tile, cell, "ShoreTiles"))
        return result
    if map_id == "chapel-hill":
        result["base_fill"] = {"asset_id": "grass_base_variants", "base_tiles": ["base_a", "base_b", "base_c", "base_d"], "variation_tiles": ["cool_patch_a", "cool_patch_b"], "variation_ratio": 0.08, "seed": "full:B:chapel-hill"}
        result["replaced_ground_shapes"] = ["chapel_main_path", "chapel_entry_plaza"]
        result["terrain_masks"] = [{"mask_id": "chapel_ritual_route", "asset_id": "chapel_path_step_set", "rects": [[16, 10, 3, 14], [14, 9, 7, 4]], "center_tiles": ["base_a", "base_b"], "seed": "chapel:steps"}]
        for x in range(4, 12): result["shore_stamps"].append(stamp("chapel_low_stone_wall_set", "base_a", (x, 14), "ShoreTiles"))
        for x in range(14, 21): result["shore_stamps"].append(stamp("chapel_courtyard_edge_set", "edge_n", (x, 9), "ShoreTiles"))
        return result
    if map_id == "photo-lane":
        result["base_fill"] = {"asset_id": "grass_base_variants", "base_tiles": ["base_a", "base_b", "base_c", "base_d"], "variation_tiles": ["cool_patch_a"], "variation_ratio": 0.06, "seed": "full:C:photo-lane"}
        result["terrain_masks"] = [{"mask_id": "photo_narrow_lane", "asset_id": "photo_lane_ground_detail_set", "rects": [[-1, 11, 38, 2], [8, 9, 2, 3]], "center_tiles": ["base_a", "base_b", "base_c"], "seed": "photo:lane"}]
        for x in list(range(1, 8)) + list(range(28, 35)): result["shore_stamps"].append(stamp("photo_lane_fence_set", "base_a", (x, 18), "ShoreTiles"))
        return result
    if map_id == "archive-lane":
        result["base_fill"] = {"asset_id": "grass_base_variants", "base_tiles": ["base_a", "base_b", "base_c", "base_d"], "variation_tiles": ["cool_patch_a"], "variation_ratio": 0.07, "seed": "full:C:archive-lane"}
        result["terrain_masks"] = [{"mask_id": "archive_steps", "asset_id": "archive_stone_step_set", "rects": [[14, 9, 5, 9], [0, 11, 18, 2]], "center_tiles": ["base_a", "base_b"], "seed": "archive:steps"}]
        for x in range(10, 23): result["shore_stamps"].append(stamp("archive_platform_edge_set", "edge_s", (x, 10), "ShoreTiles"))
        for x in list(range(10, 14)) + list(range(19, 23)): result["shore_stamps"].append(stamp("archive_low_railing_set", "base_a", (x, 11), "ShoreTiles"))
        return result
    if map_id == "low-tide-cave":
        result["replaced_ground_shapes"] = [value.get("object_id") for value in layout.get("ground_shapes", []) if value.get("kind") in {"water", "platform"}]
        for y in range(4, 14):
            for x in range(3 + (y % 2), 26 - (y % 3)):
                result["shore_stamps"].append(stamp("cave_wet_stone_floor_set", ["base_a", "base_b", "base_c", "base_d"][(x + y) % 4], (x, y), "BaseTiles"))
        for x in range(4, 25): result["shore_stamps"].append(stamp("cave_ceiling_foreground_set", "base_a", (x, 2), "ForegroundTiles"))
        for x in range(4, 25, 2): result["shore_stamps"].append(stamp("cave_wall_straight_set", "edge_n", (x, 3), "WallTiles"))
        for cell, asset, tile in [((3, 4), "cave_wall_outer_corner_set", "outer_corner_nw"), ((25, 4), "cave_wall_outer_corner_set", "outer_corner_ne"), ((4, 13), "cave_wall_inner_corner_set", "inner_corner_sw"), ((24, 13), "cave_wall_inner_corner_set", "inner_corner_se")]: result["shore_stamps"].append(stamp(asset, tile, cell, "WallTiles"))
        for cell in [(8, 10), (9, 10), (19, 8), (20, 8)]: result["shore_stamps"].append(stamp("cave_shallow_pool_set", "base_b", cell, "WaterTiles"))
        for cell in [(7, 9), (10, 11), (18, 7), (21, 9)]: result["shore_stamps"].append(stamp("cave_puddle_edge_set", "edge_n", cell, "ShoreTiles"))
        return result
    # Indoor layouts share a modular formal shell except the natural cave.
    theme = THEMES.get(map_id)
    if theme:
        result["interior_shell"] = interior_shell(layout, theme)
    room = [int(value) for value in layout["canvas"].get("room_rect", [48, 48, 672, 400])]
    floor_assets = [asset for asset in tile_sets if "floor" in asset]
    if floor_assets:
        result["floor_fills"] = [{"asset_id": floor_assets[0], "rect": [room[0] + 16, room[1] + 48, room[2] - 32, room[3] - 64], "tiles": ["base_a", "base_b", "base_c", "base_d"], "seed": f"full:{map_id}:floor"}]
    if map_id == "inn-upstairs":
        for x in range(4, 27): result["shore_stamps"].append(stamp("inn_corridor_runner_set", "base_a", (x, 9), "PathTiles"))
        for x in range(3, 28): result["shore_stamps"].append(stamp("inn_corridor_trim_normal", "edge_n", (x, 5), "BaseboardTiles"))
        result["shore_stamps"].append(stamp("inn_corridor_trim_anomaly", "edge_n", (24, 5), "BaseboardTiles"))
    elif map_id == "chapel-interior":
        for y in range(7, 14): result["shore_stamps"].append(stamp("chapel_aisle_runner_set", "base_a", (11, y), "PathTiles"))
    elif map_id == "chapel-belfry":
        for x in range(4, 23): result["shore_stamps"].append(stamp("belfry_timber_beam_set", "base_a", (x, 4), "WallTiles"))
        for x in range(3, 24): result["shore_stamps"].append(stamp("belfry_foreground_beam_set", "base_a", (x, 13), "ForegroundTiles"))
    elif map_id == "clock-basement":
        for x in range(7, 22): result["shore_stamps"].append(stamp("basement_floor_cable_set", "base_a", (x, 12), "PathTiles"))
        for x in range(5, 24, 3): result["shore_stamps"].append(stamp("basement_wall_recess_set", "base_a", (x, 4), "WallTiles"))
        for x in range(7, 22, 2): result["shore_stamps"].append(stamp("basement_contact_shadow_set", "base_a", (x, 13), "GroundDetails"))
    elif map_id == "hidden-darkroom":
        for x in range(3, 23): result["shore_stamps"].append(stamp("darkroom_wall_set", "base_a", (x, 4), "WallTiles"))
        for x in range(2, 24): result["shore_stamps"].append(stamp("darkroom_foreground_shadow_set", "base_a", (x, 14), "ForegroundTiles"))
    return result


def review_zones(layout: dict) -> list[dict]:
    width = int(layout.get("canvas", {}).get("room_rect", [0, 0, 768, 480])[2] if "room_rect" in layout.get("canvas", {}) else  int(layout.get("_scene_width", 768)))
    height = int(layout.get("canvas", {}).get("room_rect", [0, 0, 768, 480])[3] if "room_rect" in layout.get("canvas", {}) else int(layout.get("_scene_height", 480)))
    if "room_rect" in layout.get("canvas", {}):
        x, y, width, height = [int(value) for value in layout["canvas"]["room_rect"]]
    else:
        x, y = 0, 0
    return [
        {"object_id": "zone_primary_center", "type": "primary_visual_center", "rect": [x + width // 3, y + height // 4, width // 3, height // 3]},
        {"object_id": "zone_entrance", "type": "entrance_zone", "rect": [x + width // 3, y + height * 4 // 5, width // 3, height // 5]},
        {"object_id": "zone_movement", "type": "movement_zone", "rect": [x + width // 5, y + height // 3, width * 3 // 5, height // 2]},
        {"object_id": "zone_primary_interaction", "type": "primary_interaction_zone", "rect": [x + width // 3, y + height // 4, width // 3, height // 3]},
        {"object_id": "zone_secondary_story", "type": "secondary_story_zone", "rect": [x + width // 12, y + height // 5, width // 4, height // 3]},
        {"object_id": "zone_decoration", "type": "decoration_zone", "rect": [x + width * 2 // 3, y + height // 5, width // 4, height // 2]},
        {"object_id": "zone_blocked", "type": "blocked_zone", "rect": [x, y, width, max(24, height // 8)]},
        {"object_id": "zone_foreground", "type": "foreground_zone", "rect": [x, y + height * 7 // 8, width, max(24, height // 8)]},
    ]


def rollout() -> None:
    dependency = load_json(DEPENDENCY_PATH)
    manifest = load_json(MANIFEST_PATH)
    manifest_by_id = {entry["asset_id"]: entry for entry in manifest["assets"]}
    for map_entry in dependency["maps"]:
        map_id = map_entry["map_id"]
        path = LAYOUT_ROOT / f"{map_id}.json"
        layout = load_json(path)
        layout["theme_variant"] = f"full_map_rollout_{map_entry['theme']}"
        layout["interaction_distance"] = max(54, int(layout.get("interaction_distance", 54)))
        kept = [item for item in layout.get("objects", []) if item.get("object_id") in OUTDOOR_KEEP_IDS.get(map_id, set())]
        independent = [asset_id for asset_id in map_entry["generate"] if asset_id not in map_entry["tile_sets"]]
        if len(independent) != len(SLOTS[map_id]):
            raise ValueError(f"{map_id}: {len(independent)} assets but {len(SLOTS[map_id])} slots")
        new_objects = [art_object(asset_id, position, manifest_by_id[asset_id]) for asset_id, position in zip(independent, SLOTS[map_id])]
        layout["objects"] = kept + new_objects + EXTRA_OBJECTS.get(map_id, [])
        for item in layout["objects"]:
            asset_id = item.get("asset_id")
            if asset_id in manifest_by_id and "display_size" not in item:
                item["display_size"] = manifest_by_id[asset_id]["recommended_display_size"]
        layout["atlas_tile_art"] = atlas_for(map_id, layout, list(map_entry["tile_sets"]))
        layout["lights"] = [
            {"object_id": f"full_light_{index}", "position": position, "color": color, "energy": energy, "radius": radius}
            for index, (position, color, energy, radius) in enumerate(LIGHTS[map_id])
        ]
        # The cave has an authored irregular spatial shell; all other existing
        # room rectangles remain collision-compatible with the formal map data.
        if map_id == "low-tide-cave":
            layout["canvas"].update({
                "natural_boundary": True,
                "outside_color": "#061013", "floor_color": "#334549", "wall_dark": "#15272b",
                "boundary_points": [[46, 244], [88, 112], [245, 72], [430, 92], [610, 68], [840, 125], [888, 290], [850, 442], [665, 492], [460, 470], [280, 500], [92, 430]],
            })
        elif map_id == "hidden-darkroom":
            layout["canvas"].update({"floor_color": "#432d30", "wall_color": "#533438", "wall_dark": "#20191d", "outside_color": "#08090b"})
        layout["zones"] = review_zones(layout)
        layout["rollout_metadata"] = {
            "batch": map_entry["batch"], "new_asset_ids": map_entry["generate"],
            "primary_visual_center": map_entry["primary_visual_center"],
            "frozen_reference_maps_untouched": ["town", "harbor", "inn-lobby"],
        }
        write_json(path, layout)


def validate() -> list[str]:
    dependency = load_json(DEPENDENCY_PATH)
    errors: list[str] = []
    referenced: set[str] = set()
    for map_entry in dependency["maps"]:
        map_id = map_entry["map_id"]
        layout = load_json(LAYOUT_ROOT / f"{map_id}.json")
        if layout.get("map_id") != map_id: errors.append(f"{map_id}: layout id mismatch")
        object_ids = [item.get("object_id") for item in layout.get("objects", [])]
        if len(object_ids) != len(set(object_ids)): errors.append(f"{map_id}: duplicate object_id")
        referenced.update(item.get("asset_id") for item in layout.get("objects", []) if item.get("asset_id"))
        atlas = layout.get("atlas_tile_art", {})
        for group in ("floor_fills", "terrain_masks", "water_masks", "shore_stamps"):
            referenced.update(item.get("asset_id") for item in atlas.get(group, []) if item.get("asset_id"))
        if len(layout.get("zones", [])) < 8: errors.append(f"{map_id}: incomplete review zones")
        if not layout.get("rollout_metadata"): errors.append(f"{map_id}: missing rollout metadata")
    required = {asset for entry in dependency["maps"] for asset in entry["generate"]}
    missing = required - referenced
    if missing: errors.append(f"unreferenced generated assets: {', '.join(sorted(missing))}")
    for frozen in ("town", "harbor", "inn-lobby"):
        if load_json(LAYOUT_ROOT / f"{frozen}.json").get("rollout_metadata"):
            errors.append(f"frozen layout modified by rollout: {frozen}")
    return errors


def main() -> int:
    args = parse_args()
    if not args.all and not args.validate:
        raise SystemExit("Choose --all and/or --validate")
    if args.all:
        rollout()
        print("Full-map layouts composed: 15")
    errors = validate() if args.validate else []
    for error in errors: print(f"ERROR: {error}")
    if args.validate and not errors: print("Full-map layouts valid: all 178 generated assets referenced")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
