from __future__ import annotations

import json
import math
import re
import unittest
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


PROJECT_ROOT = Path(__file__).resolve().parents[1]
WORLD_PATH = PROJECT_ROOT / "data" / "world.json"
MAPS_PATH = PROJECT_ROOT / "data" / "maps.json"
INDEX_PATH = PROJECT_ROOT / "index.html"

CANVAS_WIDTH = 768
CANVAS_HEIGHT = 480
EXPECTED_REGION_IDS = {"capital", "farm", "mansion", "snow", "desert"}
REQUIRED_ARRAYS = ("timelines", "regions", "npcs", "events", "endings")
ALLOWED_METRICS = {"food", "water", "order", "hope", "aether"}
ALLOWED_FACTIONS = {"crown", "commons", "keepers", "caravan"}
ALLOWED_EFFECT_SECTIONS = {"metrics", "factions", "relationships", "flags"}
ALLOWED_OPERATORS = {">", ">=", "<", "<=", "==", "=", "!=", "includes"}
STATE_PATH_ROOTS = {
    "version",
    "contentVersion",
    "timelineId",
    "timelineName",
    "difficulty",
    "seed",
    "rngState",
    "day",
    "minute",
    "lastProcessedHour",
    "regionId",
    "visitedRegions",
    "player",
    "metrics",
    "factions",
    "npcs",
    "completedEvents",
    "pendingEvents",
    "flags",
    "journal",
    "weather",
    "speed",
    "pausedByModal",
    "endingId",
    "endingShown",
    "statistics",
}
PATH_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_:-]*(?:\.[A-Za-z_][A-Za-z0-9_:-]*)*$")


class DuplicateKeyError(ValueError):
    pass


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_world():
    return json.loads(
        WORLD_PATH.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_keys,
        parse_constant=lambda value: (_ for _ in ()).throw(
            ValueError(f"non-standard JSON number: {value}")
        ),
    )


def load_maps():
    return json.loads(
        MAPS_PATH.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_keys,
        parse_constant=lambda value: (_ for _ in ()).throw(
            ValueError(f"non-standard JSON number: {value}")
        ),
    )


def is_finite_number(value):
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
    )


def rectangles_overlap(left, right):
    return (
        left["x"] < right["x"] + right["w"]
        and left["x"] + left["w"] > right["x"]
        and left["y"] < right["y"] + right["h"]
        and left["y"] + left["h"] > right["y"]
    )


def actor_rectangle(point):
    """Match the 16 x 13 foot collision box used by renderer.movePlayer."""

    return {"x": point["x"] - 8, "y": point["y"] - 7, "w": 16, "h": 13}


def scene_collision_rectangles(scene):
    rectangles = []
    for obstacle in scene.get("obstacles", []):
        if obstacle.get("collision", True) is not False:
            rectangles.append(("obstacle", obstacle))
    for building in scene.get("buildings", []):
        if building.get("collision", True) is False:
            continue
        collision_rectangles = building.get("collisionRects")
        if not collision_rectangles:
            collision_rectangles = [{
                "x": building["x"],
                "y": building["y"] + building["h"] * 0.36,
                "w": building["w"],
                "h": building["h"] * 0.64,
            }]
        rectangles.extend((f"building:{building.get('id', '?')}", rectangle) for rectangle in collision_rectangles)
    for furniture in scene.get("furniture", []):
        if furniture.get("collision", True) is False:
            continue
        inset = min(4, furniture["w"] * 0.12)
        rectangles.append((f"furniture:{furniture.get('type', '?')}", {
            "x": furniture["x"] + inset,
            "y": furniture["y"] + furniture["h"] * 0.35,
            "w": max(2, furniture["w"] - inset * 2),
            "h": max(2, furniture["h"] * 0.65),
        }))
    for zone in scene.get("zones", []):
        if zone.get("collision") is True:
            rectangles.append((f"zone:{zone.get('type', '?')}", zone))
    return rectangles


def item_id(item):
    return item.get("id") if isinstance(item, dict) else None


def region_reference(item):
    if not isinstance(item, dict):
        return None
    return item.get("regionId", item.get("region"))


def iter_coordinate_objects(value, path="world"):
    if isinstance(value, list):
        for index, item in enumerate(value):
            yield from iter_coordinate_objects(item, f"{path}[{index}]")
    elif isinstance(value, dict):
        if "x" in value or "y" in value:
            yield path, value
        for key, item in value.items():
            yield from iter_coordinate_objects(item, f"{path}.{key}")


def condition_rules(container):
    """Yield (path label, rule) pairs consumed by simulation.getByPath."""

    if not isinstance(container, dict):
        return
    for section in ("all", "any"):
        rules = container.get(section, [])
        if isinstance(rules, list):
            for index, rule in enumerate(rules):
                if isinstance(rule, dict):
                    yield f"{section}[{index}]", rule
    flags = container.get("flags", [])
    if isinstance(flags, list):
        for index, flag in enumerate(flags):
            if isinstance(flag, dict):
                key = flag.get("key")
                if key is not None:
                    yield f"flags[{index}]", {
                        "path": f"flags.{key}",
                        "op": flag.get("op", "=="),
                        "value": flag.get("value"),
                    }


class IndexReferenceParser(HTMLParser):
    REFERENCE_ATTRIBUTES = {
        "script": "src",
        "link": "href",
        "img": "src",
        "source": "src",
        "audio": "src",
        "video": "src",
    }

    def __init__(self):
        super().__init__()
        self.references = []

    def handle_starttag(self, tag, attrs):
        attribute = self.REFERENCE_ATTRIBUTES.get(tag.lower())
        if not attribute:
            return
        values = dict(attrs)
        if values.get(attribute):
            self.references.append(values[attribute])


class TestContentFile(unittest.TestCase):
    def test_world_json_exists(self):
        self.assertTrue(WORLD_PATH.is_file(), f"missing content file: {WORLD_PATH}")

    @unittest.skipUnless(WORLD_PATH.is_file(), "world.json has not been generated")
    def test_world_json_is_strict_utf8_json(self):
        try:
            content = load_world()
        except (UnicodeError, json.JSONDecodeError, DuplicateKeyError, ValueError) as error:
            self.fail(f"world.json is not strict UTF-8 JSON: {error}")
        self.assertIsInstance(content, dict, "world.json top level must be an object")

    def test_maps_json_exists_and_is_strict_utf8_json(self):
        self.assertTrue(MAPS_PATH.is_file(), f"missing map file: {MAPS_PATH}")
        try:
            maps = load_maps()
        except (UnicodeError, json.JSONDecodeError, DuplicateKeyError, ValueError) as error:
            self.fail(f"maps.json is not strict UTF-8 JSON: {error}")
        self.assertIsInstance(maps, dict, "maps.json top level must be an object")


@unittest.skipUnless(WORLD_PATH.is_file(), "world.json has not been generated")
class TestWorldContent(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            cls.world = load_world()
        except (OSError, UnicodeError, json.JSONDecodeError, DuplicateKeyError, ValueError) as error:
            raise unittest.SkipTest(f"world.json could not be loaded: {error}") from error

        if not isinstance(cls.world, dict):
            raise unittest.SkipTest("world.json top level is not an object")
        try:
            cls.maps = load_maps()
        except (OSError, UnicodeError, json.JSONDecodeError, DuplicateKeyError, ValueError) as error:
            raise unittest.SkipTest(f"maps.json could not be loaded: {error}") from error
        cls.region_ids = {
            item_id(region)
            for region in cls.world.get("regions", [])
            if isinstance(region, dict) and item_id(region)
        }
        cls.npc_ids = {
            item_id(npc)
            for npc in cls.world.get("npcs", [])
            if isinstance(npc, dict) and item_id(npc)
        }

    def assert_unique_nonempty_ids(self, items, label):
        identifiers = []
        for index, item in enumerate(items):
            self.assertIsInstance(item, dict, f"{label}[{index}] must be an object")
            identifier = item.get("id")
            self.assertIsInstance(identifier, str, f"{label}[{index}].id must be a string")
            self.assertTrue(identifier.strip(), f"{label}[{index}].id must not be empty")
            identifiers.append(identifier)
        self.assertEqual(
            len(identifiers),
            len(set(identifiers)),
            f"{label} IDs must be unique",
        )
        return identifiers

    def assert_numeric_map(self, value, allowed_keys, path):
        self.assertIsInstance(value, dict, f"{path} must be an object")
        unknown = set(value) - allowed_keys
        self.assertFalse(unknown, f"{path} has unsupported keys: {sorted(unknown)}")
        for key, amount in value.items():
            self.assertTrue(
                is_finite_number(amount),
                f"{path}.{key} must be a finite number",
            )

    def assert_effects(self, effects, path):
        self.assertIsInstance(effects, dict, f"{path} must be an object")
        unknown_sections = set(effects) - ALLOWED_EFFECT_SECTIONS
        self.assertFalse(
            unknown_sections,
            f"{path} has unsupported sections: {sorted(unknown_sections)}",
        )
        if "metrics" in effects:
            self.assert_numeric_map(effects["metrics"], ALLOWED_METRICS, f"{path}.metrics")
        if "factions" in effects:
            self.assert_numeric_map(effects["factions"], ALLOWED_FACTIONS, f"{path}.factions")
        if "relationships" in effects:
            self.assertIsInstance(effects["relationships"], dict, f"{path}.relationships must be an object")
            unknown_npcs = set(effects["relationships"]) - self.npc_ids
            self.assertFalse(
                unknown_npcs,
                f"{path}.relationships references unknown NPCs: {sorted(unknown_npcs)}",
            )
            for npc_id, amount in effects["relationships"].items():
                self.assertTrue(
                    is_finite_number(amount),
                    f"{path}.relationships.{npc_id} must be a finite number",
                )
        if "flags" in effects:
            flags = effects["flags"]
            self.assertTrue(
                isinstance(flags, (dict, list)),
                f"{path}.flags must be an object or array",
            )
            if isinstance(flags, list):
                self.assertTrue(
                    all(isinstance(flag, str) and flag for flag in flags),
                    f"{path}.flags array must contain non-empty strings",
                )
            else:
                self.assertTrue(
                    all(isinstance(flag, str) and flag for flag in flags),
                    f"{path}.flags keys must be non-empty strings",
                )

    def assert_condition_rule(self, rule, path):
        self.assertIsInstance(rule, dict, f"{path} must be an object")
        state_path = rule.get("path")
        self.assertIsInstance(state_path, str, f"{path}.path must be a string")
        self.assertRegex(state_path, PATH_PATTERN, f"{path}.path is not parseable: {state_path!r}")
        parts = state_path.split(".")
        self.assertIn(parts[0], STATE_PATH_ROOTS, f"{path}.path has unknown state root: {parts[0]}")
        self.assertIn(rule.get("op", ">="), ALLOWED_OPERATORS, f"{path}.op is unsupported")

        if parts[0] == "metrics" and len(parts) > 1:
            self.assertIn(parts[1], ALLOWED_METRICS, f"{path}.path has unknown metric: {parts[1]}")
        if parts[0] == "factions" and len(parts) > 1:
            self.assertIn(parts[1], ALLOWED_FACTIONS, f"{path}.path has unknown faction: {parts[1]}")
        if parts[0] == "npcs" and len(parts) > 1:
            self.assertIn(parts[1], self.npc_ids, f"{path}.path has unknown NPC: {parts[1]}")

    def test_required_top_level_arrays(self):
        for key in REQUIRED_ARRAYS:
            with self.subTest(key=key):
                self.assertIn(key, self.world, f"missing top-level array: {key}")
                self.assertIsInstance(self.world[key], list, f"top-level {key} must be an array")
                self.assertTrue(self.world[key], f"top-level {key} must not be empty")

    def test_exactly_three_timelines(self):
        timelines = self.world["timelines"]
        self.assertEqual(len(timelines), 3, "world must contain exactly three timelines")
        self.assert_unique_nonempty_ids(timelines, "timelines")
        self.assertEqual(
            [(timeline["id"], timeline["name"]) for timeline in timelines],
            [("drought-embers", "余火"), ("iron-court", "律法"), ("broken-oath", "回响")],
        )
        difficulties = [timeline.get("difficulty", {}) for timeline in timelines]
        self.assertEqual([item.get("rank") for item in difficulties], [1, 2, 3])
        daily_drains = [item.get("dailyDrain") for item in difficulties]
        npc_recoveries = [item.get("npcRecovery") for item in difficulties]
        self.assertTrue(all(is_finite_number(value) and value > 0 for value in daily_drains + npc_recoveries))
        self.assertTrue(all(left < right for left, right in zip(daily_drains, daily_drains[1:])))
        self.assertTrue(all(left > right for left, right in zip(npc_recoveries, npc_recoveries[1:])))

    def test_exactly_five_regions(self):
        regions = self.world["regions"]
        self.assertEqual(len(regions), 5, "world must contain exactly five regions")
        region_ids = set(self.assert_unique_nonempty_ids(regions, "regions"))
        self.assertEqual(
            region_ids,
            EXPECTED_REGION_IDS,
            "region IDs must be capital/farm/mansion/snow/desert",
        )

    def test_at_least_three_npcs_per_region_and_unique_ids(self):
        npcs = self.world["npcs"]
        self.assert_unique_nonempty_ids(npcs, "npcs")
        counts = Counter(region_reference(npc) for npc in npcs)
        for region_id in EXPECTED_REGION_IDS:
            with self.subTest(region_id=region_id):
                self.assertGreaterEqual(
                    counts[region_id],
                    3,
                    f"region {region_id} must contain at least three NPCs",
                )

    def test_region_and_npc_references_are_valid(self):
        game_start = self.world.get("game", {}).get("startRegion")
        if game_start is not None:
            self.assertIn(game_start, self.region_ids, "game.startRegion is unknown")

        for index, timeline in enumerate(self.world["timelines"]):
            start = timeline.get("startRegion")
            if start is not None:
                self.assertIn(start, self.region_ids, f"timelines[{index}].startRegion is unknown")
            relationships = (
                timeline.get("modifiers", timeline.get("initialModifiers", {}))
                .get("relationships", {})
            )
            self.assertFalse(
                set(relationships) - self.npc_ids,
                f"timelines[{index}] modifiers reference unknown NPCs",
            )

        for npc_index, npc in enumerate(self.world["npcs"]):
            self.assertIn(
                region_reference(npc),
                self.region_ids,
                f"npcs[{npc_index}] references an unknown region",
            )
            for slot_index, slot in enumerate(npc.get("schedule", [])):
                slot_region = region_reference(slot)
                if slot_region is not None:
                    self.assertIn(
                        slot_region,
                        self.region_ids,
                        f"npcs[{npc_index}].schedule[{slot_index}] references an unknown region",
                    )

        for event_index, event in enumerate(self.world["events"]):
            self.assertIn(
                region_reference(event),
                self.region_ids,
                f"events[{event_index}] references an unknown region",
            )
            involved = event.get("npcIds", event.get("npcs", []))
            self.assertIsInstance(involved, list, f"events[{event_index}] NPC references must be an array")
            self.assertFalse(
                set(involved) - self.npc_ids,
                f"events[{event_index}] references unknown NPCs: {sorted(set(involved) - self.npc_ids)}",
            )

    def test_day_two_through_eight_have_events_with_three_choices(self):
        events = self.world["events"]
        self.assert_unique_nonempty_ids(events, "events")
        events_by_day = Counter()
        for index, event in enumerate(events):
            day = event.get("day")
            self.assertTrue(
                is_finite_number(day) and int(day) == day,
                f"events[{index}].day must be an integer",
            )
            events_by_day[int(day)] += 1
            choices = event.get("choices")
            self.assertIsInstance(choices, list, f"events[{index}].choices must be an array")
            self.assertGreaterEqual(
                len(choices),
                3,
                f"events[{index}] must offer at least three choices",
            )
            self.assert_unique_nonempty_ids(choices, f"events[{index}].choices")

        for day in range(2, 9):
            with self.subTest(day=day):
                self.assertGreaterEqual(events_by_day[day], 1, f"day {day} must have at least one event")

    def test_choice_effects_use_only_supported_state_sections(self):
        for event_index, event in enumerate(self.world["events"]):
            for choice_index, choice in enumerate(event.get("choices", [])):
                effects = choice.get("effects", {})
                self.assert_effects(
                    effects,
                    f"events[{event_index}].choices[{choice_index}].effects",
                )

        for timeline_index, timeline in enumerate(self.world["timelines"]):
            modifiers = timeline.get("modifiers", timeline.get("initialModifiers", {}))
            self.assertIsInstance(modifiers, dict, f"timelines[{timeline_index}].modifiers must be an object")
            if "metrics" in modifiers:
                self.assert_numeric_map(
                    modifiers["metrics"],
                    ALLOWED_METRICS,
                    f"timelines[{timeline_index}].modifiers.metrics",
                )
            if "factions" in modifiers:
                self.assert_numeric_map(
                    modifiers["factions"],
                    ALLOWED_FACTIONS,
                    f"timelines[{timeline_index}].modifiers.factions",
                )

    def test_requirements_and_ending_condition_paths_are_parseable(self):
        for event_index, event in enumerate(self.world["events"]):
            for choice_index, choice in enumerate(event.get("choices", [])):
                requirements = choice.get("requirements", choice.get("requires"))
                if requirements is None or isinstance(requirements, str):
                    continue
                if isinstance(requirements, list):
                    rules = requirements
                elif isinstance(requirements, dict) and "all" in requirements:
                    rules = requirements["all"]
                else:
                    rules = [requirements]
                self.assertIsInstance(
                    rules,
                    list,
                    f"events[{event_index}].choices[{choice_index}] requirements must resolve to an array",
                )
                for rule_index, rule in enumerate(rules):
                    if isinstance(rule, str):
                        self.assertTrue(rule, "flag requirements must not be empty")
                    else:
                        self.assert_condition_rule(
                            rule,
                            f"events[{event_index}].choices[{choice_index}].requirements[{rule_index}]",
                        )

        for ending_index, ending in enumerate(self.world["endings"]):
            condition = ending.get("condition", ending.get("conditions", {}))
            self.assertIsInstance(condition, dict, f"endings[{ending_index}].condition must be an object")
            for rule_name, rule in condition_rules(condition):
                self.assert_condition_rule(rule, f"endings[{ending_index}].condition.{rule_name}")

    def test_at_least_seven_endings_include_fallback(self):
        endings = self.world["endings"]
        self.assertGreaterEqual(len(endings), 7, "world must define at least seven endings")
        self.assert_unique_nonempty_ids(endings, "endings")
        self.assertTrue(
            any(ending.get("fallback") is True for ending in endings),
            "at least one ending must set fallback to true",
        )

    def map_scenes(self):
        layouts = self.maps.get("regions", {})
        places = self.maps.get("places", [])
        return [
            {"id": region_id, "regionId": region_id, **layout}
            for region_id, layout in layouts.items()
        ] + places

    def test_map_schema_has_five_large_outdoors_and_fifteen_interiors(self):
        layouts = self.maps.get("regions")
        places = self.maps.get("places")
        self.assertIsInstance(layouts, dict)
        self.assertEqual(set(layouts), EXPECTED_REGION_IDS)
        self.assertIsInstance(places, list)
        self.assertEqual(len(places), 15)
        place_ids = self.assert_unique_nonempty_ids(places, "maps.places")
        self.assertEqual(len(place_ids), len(set(place_ids)))
        for region_id, layout in layouts.items():
            with self.subTest(region_id=region_id):
                self.assertGreater(layout.get("width", 0), CANVAS_WIDTH)
                self.assertGreater(layout.get("height", 0), CANVAS_HEIGHT)
                self.assertGreaterEqual(len(layout.get("zones", [])), 5)
                self.assertGreaterEqual(len(layout.get("portals", [])), 5)
                decor = [item for item in layout.get("landmarks", []) if item.get("interactive") is False]
                self.assertGreaterEqual(len(decor), 6, f"{region_id} needs enough ambient props")
                self.assertGreaterEqual(
                    len({item.get("type") for item in decor}),
                    3,
                    f"{region_id} ambient props should not be one repeated object",
                )

    def test_npc_schedule_coordinates_fit_their_places(self):
        scenes = {scene["id"]: scene for scene in self.map_scenes()}
        for npc_index, npc in enumerate(self.world["npcs"]):
            for slot_index, slot in enumerate(npc.get("schedule", [])):
                place_id = slot.get("placeId", slot.get("regionId", npc.get("regionId")))
                scene = scenes.get(place_id)
                path = f"npcs[{npc_index}].schedule[{slot_index}]"
                self.assertIsNotNone(scene, f"{path} references unknown place {place_id}")
                for axis, limit in (("x", scene["width"]), ("y", scene["height"])):
                    value = slot.get(axis)
                    self.assertTrue(is_finite_number(value), f"{path}.{axis} must be finite")
                    self.assertGreaterEqual(value, 0, f"{path}.{axis} is negative")
                    self.assertLessEqual(value, limit, f"{path}.{axis} exceeds {place_id}")

    def test_scene_rectangles_and_portals_are_valid(self):
        scenes = self.map_scenes()
        scene_ids = {scene["id"] for scene in scenes}
        for scene in scenes:
            scene_width = scene.get("width", CANVAS_WIDTH)
            scene_height = scene.get("height", CANVAS_HEIGHT)
            for collection_name in ("paths", "zones", "buildings", "obstacles", "landmarks", "furniture", "portals"):
                collection = scene.get(collection_name, [])
                self.assertIsInstance(collection, list, f"{scene['id']}.{collection_name} must be an array")
                for item_index, rectangle in enumerate(collection):
                    path = f"{scene['id']}.{collection_name}[{item_index}]"
                    self.assertIsInstance(rectangle, dict, f"{path} must be an object")
                    for key in ("x", "y", "w", "h"):
                        self.assertTrue(is_finite_number(rectangle.get(key)), f"{path}.{key} must be finite")
                    self.assertGreater(rectangle["w"], 0, f"{path}.w must be positive")
                    self.assertGreater(rectangle["h"], 0, f"{path}.h must be positive")
                    self.assertGreaterEqual(rectangle["x"], 0, f"{path} starts left of scene")
                    self.assertGreaterEqual(rectangle["y"], 0, f"{path} starts above scene")
                    self.assertLessEqual(rectangle["x"] + rectangle["w"], scene_width, f"{path} exceeds scene width")
                    self.assertLessEqual(rectangle["y"] + rectangle["h"], scene_height, f"{path} exceeds scene height")
                    if collection_name == "portals":
                        target = rectangle.get("target", {})
                        self.assertIn(target.get("regionId"), EXPECTED_REGION_IDS, f"{path} has unknown target region")
                        self.assertIn(target.get("placeId", target.get("regionId")), scene_ids, f"{path} has unknown target place")

    def test_spawns_portal_arrivals_and_npc_schedules_are_walkable(self):
        scenes = {scene["id"]: scene for scene in self.map_scenes()}

        def assert_walkable(scene, point, path, reject_visual_buildings=False):
            actor = actor_rectangle(point)
            self.assertGreaterEqual(actor["x"], 8, f"{path} is too close to the left edge")
            self.assertGreaterEqual(actor["y"], 8, f"{path} is too close to the top edge")
            self.assertLessEqual(actor["x"] + actor["w"], scene["width"] - 8, f"{path} is too close to the right edge")
            self.assertLessEqual(actor["y"] + actor["h"], scene["height"] - 8, f"{path} is too close to the bottom edge")
            for blocker_name, blocker in scene_collision_rectangles(scene):
                self.assertFalse(
                    rectangles_overlap(actor, blocker),
                    f"{path} overlaps {scene['id']} {blocker_name}",
                )
            if reject_visual_buildings:
                for building in scene.get("buildings", []):
                    if building.get("collision", True) is False:
                        continue
                    self.assertFalse(
                        rectangles_overlap(actor, building),
                        f"{path} appears on top of {scene['id']} building:{building.get('id', '?')}",
                    )

        for scene_id, scene in scenes.items():
            assert_walkable(
                scene,
                scene["spawn"],
                f"{scene_id}.spawn",
                reject_visual_buildings=scene.get("kind") != "interior",
            )
            for portal_index, portal in enumerate(scene.get("portals", [])):
                target = portal["target"]
                target_scene_id = target.get("placeId", target["regionId"])
                target_scene = scenes[target_scene_id]
                assert_walkable(
                    target_scene,
                    target,
                    f"{scene_id}.portals[{portal_index}].target",
                    reject_visual_buildings=target_scene.get("kind") != "interior",
                )

        for npc_index, npc in enumerate(self.world["npcs"]):
            for slot_index, slot in enumerate(npc.get("schedule", [])):
                scene_id = slot.get("placeId", slot.get("regionId", npc.get("regionId")))
                scene = scenes[scene_id]
                assert_walkable(
                    scene,
                    slot,
                    f"npcs[{npc_index}].schedule[{slot_index}]",
                    reject_visual_buildings=scene.get("kind") != "interior",
                )


class TestStaticReferences(unittest.TestCase):
    def test_index_local_references_exist(self):
        self.assertTrue(INDEX_PATH.is_file(), f"missing index file: {INDEX_PATH}")
        parser = IndexReferenceParser()
        parser.feed(INDEX_PATH.read_text(encoding="utf-8"))
        self.assertTrue(parser.references, "index.html should reference local CSS or JavaScript")

        missing = []
        for reference in parser.references:
            parsed = urlsplit(reference)
            if parsed.scheme or parsed.netloc or reference.startswith(("#", "data:")):
                continue
            relative = unquote(parsed.path)
            if not relative or relative.startswith("/api/"):
                continue
            target = (
                PROJECT_ROOT / relative.lstrip("/")
                if relative.startswith("/")
                else INDEX_PATH.parent / relative
            ).resolve()
            try:
                target.relative_to(PROJECT_ROOT.resolve())
            except ValueError:
                missing.append(f"{reference} (escapes project root)")
                continue
            if not target.is_file():
                missing.append(reference)
        self.assertFalse(missing, f"index.html has missing local references: {missing}")


if __name__ == "__main__":
    unittest.main()
