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

if npc_ids != {"arthur", "beatrice", "conrad", "dorothea", "elias", "florence", "ada"}:
    fail(f"unexpected NPC IDs: {sorted(npc_ids)}")
for scene in scenes:
    for portal in scene.get("portals", []):
        if portal.get("targetPlaceId") not in scene_ids:
            fail(f"portal {portal.get('id')} has invalid target")
        if "spawn" not in portal:
            fail(f"portal {portal.get('id')} has no spawn")

project = (ROOT / "project.godot").read_text(encoding="utf-8")
for action in ("move_up", "move_down", "move_left", "move_right", "interact", "cancel", "journal", "inventory", "pause"):
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
if len(source_images) != 147:
    fail(f"expected 147 mirrored art images, found {len(source_images)}")
for sidecar in source_art.rglob("*.import"):
    sidecar_text = sidecar.read_text(encoding="utf-8")
    if 'source_file="res://assets/images/source_art/' not in sidecar_text:
        fail(f"art import sidecar points outside the migrated source tree: {sidecar.relative_to(ROOT)}")
for surface_name in ("tile_grass.png", "tile_water.png", "tile_cobble.png", "tile_wood.png"):
    if not (source_art / "world" / surface_name).exists():
        fail(f"migrated world surface missing: {surface_name}")

print(f"Static validation: {len(checked_sources)} source/scene files, {len(scenes)} scenes, {len(npc_ids)} NPCs, {FAILURES} failures")
sys.exit(1 if FAILURES else 0)
