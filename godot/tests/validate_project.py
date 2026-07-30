"""Dependency-free static validation for the migrated Godot project."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RES_REF = re.compile(r'res://[^"\s)\]]+')


def fail(message: str) -> None:
    print(f"ERROR: {message}")
    global FAILURES
    FAILURES += 1


FAILURES = 0


def is_integer_pair(value: object) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 2
        and all(isinstance(number, (int, float)) and float(number).is_integer() for number in value)
    )


def point_blocked(point: tuple[float, float], collisions: list[list[float]], bounds: tuple[float, float]) -> bool:
    x, y = point
    width, height = bounds
    if x < 8 or y < 8 or x > width - 8 or y > height - 8:
        return True
    return any(cx - 7 <= x <= cx + cw + 7 and cy - 7 <= y <= cy + ch + 7 for cx, cy, cw, ch in collisions)


def reachable_cells(start: tuple[float, float], collisions: list[list[float]], bounds: tuple[float, float], grid: int = 16) -> set[tuple[int, int]]:
    def center(cell: tuple[int, int]) -> tuple[float, float]:
        return ((cell[0] + 0.5) * grid, (cell[1] + 0.5) * grid)

    origin = (int(start[0] // grid), int(start[1] // grid))
    if point_blocked(center(origin), collisions, bounds):
        replacement = None
        for radius in range(1, 12):
            for y in range(origin[1] - radius, origin[1] + radius + 1):
                for x in range(origin[0] - radius, origin[0] + radius + 1):
                    if abs(x - origin[0]) != radius and abs(y - origin[1]) != radius:
                        continue
                    if not point_blocked(center((x, y)), collisions, bounds):
                        replacement = (x, y)
                        break
                if replacement:
                    break
            if replacement:
                break
        if replacement:
            origin = replacement
    visited = {origin}
    frontier = [origin]
    for cell in frontier:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            candidate = (cell[0] + dx, cell[1] + dy)
            if candidate not in visited and not point_blocked(center(candidate), collisions, bounds):
                visited.add(candidate)
                frontier.append(candidate)
    return visited

for path in ROOT.rglob("*"):
    if path.is_file() and path.suffix.lower() in {".gd", ".tscn", ".tres", ".godot", ".md", ".json", ".svg", ".gdshader"}:
        try:
            path.read_text(encoding="utf-8")
        except UnicodeDecodeError as error:
            fail(f"not UTF-8: {path.relative_to(ROOT)}: {error}")

checked_sources = list(ROOT.rglob("*.gd")) + list(ROOT.rglob("*.tscn")) + [ROOT / "project.godot"]
for source in checked_sources:
    text = source.read_text(encoding="utf-8")
    for reference in RES_REF.findall(text):
        reference = reference.rstrip("',;:")
        if "%" in reference:
            continue
        target = ROOT / reference.removeprefix("res://")
        if not target.exists():
            fail(f"missing resource {reference} referenced by {source.relative_to(ROOT)}")

world = json.loads((ROOT / "data" / "world.json").read_text(encoding="utf-8"))
maps = json.loads((ROOT / "data" / "maps.json").read_text(encoding="utf-8"))
scenes = maps["regions"] + maps["places"]
scene_ids = {scene["id"] for scene in scenes}
npc_ids = {npc["id"] for npc in world["npcs"]}

expected_map_ids = [
    "town", "inn-yard", "chapel-hill", "photo-lane", "archive-lane", "harbor",
    "player-room", "inn-lobby", "inn-upstairs", "clock-cabin", "chapel-interior",
    "chapel-belfry", "photo-studio", "archive-room", "harbor-control", "low-tide-cave",
    "clock-basement", "hidden-darkroom",
]
if [scene["id"] for scene in scenes] != expected_map_ids:
    fail("stable 18-map ID order changed")
if maps.get("artLayoutRoot") != "res://data/art_layouts":
    fail("Godot maps do not declare the Godot-only art layout root")

manifest_path = ROOT / "data" / "art_manifest.json"
if not manifest_path.is_file():
    fail("missing data/art_manifest.json")
    manifest = {"assets": []}
else:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
allowed_categories = {
    "building", "character", "furniture", "decoration", "landmark", "ground_texture",
    "path_texture", "water_texture", "wall_texture", "floor_texture", "wall_decoration",
    "architecture", "effect", "ui", "concept_only",
}
asset_ids: set[str] = set()
manifest_assets_by_id: dict[str, dict] = {}
batch_one_ids = {
    "grass_base_variants", "grass_path_edge_set", "stone_path_corner_set",
    "water_shallow_deep_set", "natural_shoreline_set", "interior_wall_modular_set",
    "interior_corner_set", "baseboard_set",
}
p0_fix_atlas_ids = {"harbor_dock_entry_set", "water_transition_patch_set"}
for asset in manifest.get("assets", []):
    asset_id = str(asset.get("asset_id", ""))
    if not asset_id:
        fail("art manifest entry has no asset_id")
    if asset_id in asset_ids:
        fail(f"duplicate art asset_id: {asset_id}")
    asset_ids.add(asset_id)
    manifest_assets_by_id[asset_id] = asset
    if asset.get("category") not in allowed_categories:
        fail(f"asset {asset_id} has invalid category {asset.get('category')}")
    for field in ("runtime_path", "source_path", "perspective", "native_size", "recommended_display_size", "anchor", "sort_anchor", "contexts", "forbidden_contexts", "contains_text", "can_mirror", "pixel_art", "contact_shadow", "collision_preset", "enabled", "needs_review", "notes"):
        if field not in asset:
            fail(f"asset {asset_id} is missing {field}")
    for field in ("runtime_path", "source_path"):
        value = str(asset.get(field, ""))
        must_exist = field == "source_path" or bool(asset.get("enabled", True))
        if not value.startswith("res://") or (must_exist and not (ROOT / value.removeprefix("res://")).is_file()):
            fail(f"asset {asset_id} has missing {field}: {value}")
    if not is_integer_pair(asset.get("native_size")) or not is_integer_pair(asset.get("recommended_display_size")):
        fail(f"asset {asset_id} has invalid size metadata")
    runtime_path = str(asset.get("runtime_path", ""))
    if bool(asset.get("enabled", True)) and "/processed/" in runtime_path and not (ROOT / runtime_path.removeprefix("res://")).is_file():
        fail(f"enabled processed asset is missing: {asset_id}")
    if "source_master_path" in asset:
        master_path = str(asset.get("source_master_path", ""))
        if not master_path.startswith("res://") or not (ROOT / master_path.removeprefix("res://")).is_file():
            fail(f"asset {asset_id} has missing source master: {master_path}")
    if asset_id in batch_one_ids | p0_fix_atlas_ids:
        if not is_integer_pair(asset.get("tile_size")) or not is_integer_pair(asset.get("atlas_grid")):
            fail(f"generated atlas {asset_id} has invalid tile metadata")
        else:
            tile_size = asset["tile_size"]
            grid = asset["atlas_grid"]
            expected = [int(tile_size[0]) * int(grid[0]), int(tile_size[1]) * int(grid[1])]
            if expected != asset.get("recommended_display_size"):
                fail(f"generated atlas {asset_id} grid does not match display size")
if not batch_one_ids.issubset(asset_ids):
    fail(f"missing generated P0 batch-one assets: {sorted(batch_one_ids - asset_ids)}")

semantics_path = ROOT / "data" / "art_atlas_semantics.json"
if not semantics_path.is_file():
    fail("missing data/art_atlas_semantics.json")
    atlas_semantics: dict[str, dict] = {}
else:
    semantics_document = json.loads(semantics_path.read_text(encoding="utf-8"))
    atlas_semantics = semantics_document.get("atlases", {})
    semantic_asset_ids = {
        asset_id for asset_id, asset in manifest_assets_by_id.items()
        if asset.get("semantic_map") == "res://data/art_atlas_semantics.json"
    }
    if set(atlas_semantics) != semantic_asset_ids:
        fail(f"atlas semantic IDs differ from semantic manifest assets: {sorted(set(atlas_semantics) ^ semantic_asset_ids)}")
    for asset_id, semantic in atlas_semantics.items():
        manifest_asset = manifest_assets_by_id.get(asset_id, {})
        if semantic.get("tile_size") != manifest_asset.get("tile_size"):
            fail(f"semantic tile_size mismatch: {asset_id}")
        if semantic.get("grid") != manifest_asset.get("atlas_grid"):
            fail(f"semantic grid mismatch: {asset_id}")
        grid = semantic.get("grid", [0, 0])
        tile_limit = int(grid[0]) * int(grid[1]) if is_integer_pair(grid) else 0
        tiles = semantic.get("tiles", {})
        indexes = list(tiles.values()) if isinstance(tiles, dict) else []
        if not tiles or any(not isinstance(index, int) or index < 0 or index >= tile_limit for index in indexes):
            fail(f"semantic tile index is invalid: {asset_id}")
        if len(indexes) != len(set(indexes)):
            fail(f"semantic tile index is duplicated: {asset_id}")
        if manifest_asset.get("semantic_map") != "res://data/art_atlas_semantics.json":
            fail(f"manifest asset does not declare semantic map: {asset_id}")

world_tile_sources = [
    ROOT / "scripts" / "world" / "world_view.gd",
    ROOT / "scripts" / "world" / "art_tile_layer_builder.gd",
]
magic_tile_index = re.compile(r"get_atlas_tile\([^,\n]+,\s*\d+")
for source in world_tile_sources:
    if magic_tile_index.search(source.read_text(encoding="utf-8")):
        fail(f"map runtime uses a magic atlas index: {source.relative_to(ROOT)}")

missing_assets_path = ROOT / "data" / "missing_assets.json"
if not missing_assets_path.is_file():
    fail("missing data/missing_assets.json")
else:
    missing_assets = json.loads(missing_assets_path.read_text(encoding="utf-8"))
    completed_replacements = {
        str(item.get("replacement_asset_id", ""))
        for item in missing_assets.get("items", [])
        if item.get("status") == "completed"
    }
    if not batch_one_ids.issubset(completed_replacements):
        fail(f"P0 batch-one completion records are incomplete: {sorted(batch_one_ids - completed_replacements)}")

incoming_spawns: dict[str, list[tuple[str, tuple[float, float]]]] = {scene_id: [] for scene_id in scene_ids}
for scene in scenes:
    for portal in scene.get("portals", []):
        spawn = portal.get("spawn", {})
        target_id = str(portal.get("targetPlaceId", ""))
        if target_id in incoming_spawns and isinstance(spawn, dict):
            incoming_spawns[target_id].append((scene["id"], (float(spawn.get("x", 0)), float(spawn.get("y", 0)))))
incoming_spawns["player-room"].append(("new_game", (384.0, 370.0)))

allowed_layers = {"GroundDetails", "ArchitectureBack", "WallDecorations", "WorldObjects", "ArchitectureFront", "Foreground"}
benchmark_atlas_assets = {
    "town": {"grass_base_variants", "grass_path_edge_set", "stone_path_corner_set", "water_shallow_deep_set", "natural_shoreline_set", "water_transition_patch_set"},
    "harbor": {"grass_base_variants", "grass_path_edge_set", "stone_path_corner_set", "water_shallow_deep_set", "natural_shoreline_set", "water_transition_patch_set", "harbor_dock_entry_set"},
    "inn-lobby": {"interior_wall_modular_set", "interior_corner_set", "baseboard_set"},
}
for scene in scenes:
    scene_id = scene["id"]
    layout_path = ROOT / "data" / "art_layouts" / f"{scene_id}.json"
    if not layout_path.is_file():
        fail(f"missing art layout for {scene_id}")
        continue
    layout = json.loads(layout_path.read_text(encoding="utf-8"))
    if layout.get("map_id") != scene_id:
        fail(f"art layout map_id mismatch: {scene_id}")
    atlas_config = layout.get("atlas_tile_art", {})
    if scene_id not in benchmark_atlas_assets and atlas_config:
        fail(f"P0 batch-one atlas art was promoted outside benchmark maps: {scene_id}")
    if scene_id in benchmark_atlas_assets:
        serialized_config = json.dumps(atlas_config, ensure_ascii=False)
        missing_benchmark_assets = {
            asset_id for asset_id in benchmark_atlas_assets[scene_id]
            if asset_id not in serialized_config
        }
        if missing_benchmark_assets:
            fail(f"{scene_id} is missing benchmark atlas references: {sorted(missing_benchmark_assets)}")
        if scene_id == "inn-lobby" and atlas_config.get("interior_shell", {}).get("theme") != "inn_warm":
            fail("inn-lobby benchmark must use only the inn_warm theme")
    for collection in ("ground_shapes", "objects", "collision_rects", "lights"):
        ids: set[str] = set()
        for item in layout.get(collection, []):
            object_id = str(item.get("object_id", ""))
            if not object_id or object_id in ids:
                fail(f"{scene_id}/{collection} has missing or duplicate object_id: {object_id}")
            ids.add(object_id)
    for item in layout.get("objects", []):
        object_id = item.get("object_id", "?")
        if item.get("asset_id") and item.get("asset_id") not in asset_ids:
            fail(f"{scene_id}/{object_id} references unknown asset {item.get('asset_id')}")
        if item.get("layer", "WorldObjects") not in allowed_layers:
            fail(f"{scene_id}/{object_id} has invalid layer")
        if not is_integer_pair(item.get("position")) or not is_integer_pair(item.get("display_size")):
            fail(f"{scene_id}/{object_id} has non-integer position/display size")
    if scene.get("kind") == "interior":
        zone_ids = {zone.get("type") for zone in layout.get("zones", [])}
        required_zones = {"entrance_zone", "movement_zone", "primary_interaction_zone", "secondary_story_zone", "decoration_zone", "blocked_zone"}
        if not required_zones.issubset(zone_ids):
            fail(f"{scene_id} room shell is missing functional zones: {sorted(required_zones - zone_ids)}")
    overrides = layout.get("gameplay_overrides", {})
    collisions = [entry.get("rect", []) for entry in layout.get("collision_rects", [])]
    starts = incoming_spawns.get(scene_id) or [("review", (float(scene["width"]) / 2, float(scene["height"]) * 0.58))]
    for portal in scene.get("portals", []):
        portal_id = portal["id"]
        if portal_id not in overrides or "trigger_rect" not in overrides[portal_id]:
            fail(f"{scene_id}/{portal_id} has no art trigger_rect override")
            continue
        trigger = overrides[portal_id]["trigger_rect"]
        tx, ty, tw, th = (float(value) for value in trigger)
        for source_id, spawn in starts:
            cells = reachable_cells(spawn, collisions, (float(scene["width"]), float(scene["height"])))
            if not any(tx - 10 <= (x + 0.5) * 16 <= tx + tw + 10 and ty - 10 <= (y + 0.5) * 16 <= ty + th + 10 for x, y in cells):
                fail(f"{scene_id}/{portal_id} unreachable from {source_id} spawn {spawn}")

if npc_ids != {"arthur", "beatrice", "conrad", "dorothea", "elias", "florence", "ada"}:
    fail(f"unexpected NPC IDs: {sorted(npc_ids)}")
for scene in scenes:
    for portal in scene.get("portals", []):
        if portal.get("targetPlaceId") not in scene_ids:
            fail(f"portal {portal.get('id')} has invalid target")
        if "spawn" not in portal:
            fail(f"portal {portal.get('id')} has no spawn")

project = (ROOT / "project.godot").read_text(encoding="utf-8")
for action in ("move_up", "move_down", "move_left", "move_right", "interact", "cancel", "journal", "inventory", "pause", "run"):
    if f"{action}={{" not in project:
        fail(f"InputMap action missing: {action}")
for required_asset in ["spr_player.webp", "spr_ada.webp", "time_echo_horizon.webp"]:
    if not (ROOT / "assets" / "images" / required_asset).exists():
        fail(f"required visual missing: {required_asset}")

source_art = ROOT / "assets" / "images" / "source_art"
source_images = [
    path
    for path in source_art.rglob("*")
    if path.is_file() and path.suffix.lower() in {".png", ".webp", ".jpg", ".jpeg", ".svg"}
]
mirrored_source_images = [path for path in source_images if "generated" not in path.relative_to(source_art).parts]
generated_source_images = [path for path in source_images if "generated" in path.relative_to(source_art).parts]
if len(mirrored_source_images) != 147:
    fail(f"expected 147 unchanged mirrored art images, found {len(mirrored_source_images)}")
generated_root = source_art / "generated"
canonical_generated = [path for path in generated_source_images if path.parent == generated_root]
generated_masters = [path for path in generated_source_images if "masters" in path.relative_to(generated_root).parts]
generated_references = [path for path in generated_source_images if "references" in path.relative_to(generated_root).parts]
manifest_generated_sources = {
    ROOT / str(asset.get("source_path", "")).removeprefix("res://")
    for asset in manifest.get("assets", [])
    if str(asset.get("source_path", "")).startswith("res://assets/images/source_art/generated/")
}
missing_manifest_sources = {path for path in manifest_generated_sources if not path.is_file()}
if missing_manifest_sources:
    fail(f"manifest generated sources are missing: {sorted(path.name for path in missing_manifest_sources)}")
required_fix_masters = {
    "inn_staircase.png", "inn_reception_partition.png", "inn_main_door.png", "generic_table_set.png",
    "generic_chair_set_v2.png", "inn_wall_decor_set.png", "harbor_dock_entry_set.png", "water_transition_patch_set.png",
}
if not required_fix_masters.issubset({path.name for path in generated_masters}):
    fail(f"P0 fix masters are incomplete: {sorted(required_fix_masters - {path.name for path in generated_masters})}")
if len(generated_references) != 3:
    fail(f"expected 3 traceable image-generation repair references, found {len(generated_references)}")
for sidecar in source_art.rglob("*.import"):
    sidecar_text = sidecar.read_text(encoding="utf-8")
    if 'source_file="res://assets/images/source_art/' not in sidecar_text:
        fail(f"art import sidecar points outside the migrated source tree: {sidecar.relative_to(ROOT)}")
for surface_name in ("tile_grass.png", "tile_water.png", "tile_cobble.png", "tile_wood.png"):
    if not (source_art / "world" / surface_name).exists():
        fail(f"migrated world surface missing: {surface_name}")

for required_document in (
    "ART_AUDIT.md", "ART_DIRECTION.md", "ART_SCALE_GUIDE.md", "ASSET_USAGE_RULES.md",
    "MAP_ART_REFACTOR_PLAN.md", "MISSING_ASSET_REPORT.md", "ART_INTEGRATION_REPORT.md",
    "P0_BATCH_01_ASSET_SPEC.md", "P0_BATCH_01_VISUAL_AUDIT.md", "P0_BATCH_01_INTEGRATION_REVIEW.md",
    "P0_VISUAL_IMPACT_REVIEW.md",
):
    if not (ROOT / "docs" / required_document).is_file():
        fail(f"missing art document: {required_document}")
if not (ROOT / "scenes" / "tools" / "art_review.tscn").is_file():
    fail("missing Art Review developer scene")
if 'enabled_by_default = true' in (ROOT / "scenes" / "world" / "world_view.tscn").read_text(encoding="utf-8"):
    fail("Art Debug must be disabled by default")

missing_path = ROOT / "data" / "missing_assets.json"
if not missing_path.is_file():
    fail("missing data/missing_assets.json")
else:
    missing = json.loads(missing_path.read_text(encoding="utf-8"))
    required_fields = {
        "asset_id", "中文名称", "category", "target_maps", "recommended_native_size",
        "intended_display_size", "perspective", "palette", "quantity", "priority",
        "current_fallback", "production_notes",
    }
    priorities = {"P0": 0, "P1": 0, "P2": 0}
    missing_ids: set[str] = set()
    for item in missing.get("items", []):
        absent = required_fields - item.keys()
        if absent:
            fail(f"missing asset specification lacks fields {sorted(absent)}")
        item_id = str(item.get("asset_id", ""))
        if not item_id or item_id in missing_ids:
            fail(f"missing asset specification has duplicate/empty ID: {item_id}")
        missing_ids.add(item_id)
        priority = str(item.get("priority", ""))
        if priority not in priorities:
            fail(f"invalid missing asset priority: {priority}")
        else:
            priorities[priority] += 1
    if any(count == 0 for count in priorities.values()):
        fail(f"missing asset report must include P0/P1/P2: {priorities}")

runtime_text = "\n".join(path.read_text(encoding="utf-8") for path in ROOT.rglob("*.gd") if "tests" not in path.parts and "tools" not in path.parts)
for forbidden_reference in ("../data/maps.json", "../data/world.json", "js/renderer.js"):
    if forbidden_reference in runtime_text:
        fail(f"Godot runtime references browser source: {forbidden_reference}")

print(f"Static validation: {len(checked_sources)} source/scene files, {len(scenes)} scenes, {len(npc_ids)} NPCs, {FAILURES} failures")
sys.exit(1 if FAILURES else 0)
