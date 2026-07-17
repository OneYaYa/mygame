import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ContentContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.world = json.loads((ROOT / "data" / "world.json").read_text(encoding="utf-8"))
        cls.maps = json.loads((ROOT / "data" / "maps.json").read_text(encoding="utf-8"))
        cls.scenes = cls.maps["regions"] + cls.maps["places"]
        cls.scene_ids = {scene["id"] for scene in cls.scenes}

    def test_exact_cast_and_erased_seventh_witness(self):
        npc_ids = {npc["id"] for npc in self.world["npcs"]}
        self.assertEqual(
            npc_ids,
            {"arthur", "beatrice", "conrad", "dorothea", "elias", "florence", "ada"},
        )

    def test_public_maps_are_larger_than_one_canvas(self):
        for scene_id in {"town", "inn-yard", "chapel-hill", "photo-lane", "archive-lane", "harbor"}:
            scene = next(scene for scene in self.scenes if scene["id"] == scene_id)
            with self.subTest(scene=scene_id):
                self.assertGreater(scene["width"], 768)
                self.assertGreater(scene["height"], 480)

    def test_portal_targets_exist(self):
        for scene in self.scenes:
            for portal in scene.get("portals", []):
                with self.subTest(scene=scene["id"], portal=portal["id"]):
                    self.assertIn(portal["targetPlaceId"], self.scene_ids)
                    self.assertIn("spawn", portal)

    def test_core_hidden_spaces_exist(self):
        required = {
            "clock-basement",
            "hidden-darkroom",
            "low-tide-cave",
            "chapel-belfry",
            "photo-studio",
            "archive-room",
        }
        self.assertTrue(required.issubset(self.scene_ids))

    def test_three_repairs_and_identity_evidence_are_represented(self):
        landmark_ids = {
            landmark["id"]
            for scene in self.scenes
            for landmark in scene.get("landmarks", [])
        }
        self.assertTrue(
            {
                "master_clock_mechanism",
                "chapel_clock_mechanism",
                "tide_clock",
                "identity_fixing_table",
                "witness_slot_seven",
                "red_erase_lever",
                "white_continue_knob",
            }.issubset(landmark_ids)
        )

    def test_secret_portals_require_world_flags(self):
        secret_portals = {
            portal["id"]: portal.get("revealFlag")
            for scene in self.scenes
            for portal in scene.get("portals", [])
            if portal["id"] in {"enter_low_tide_cave", "studio_to_darkroom", "cabin_to_basement"}
        }
        self.assertEqual(secret_portals["enter_low_tide_cave"], "low_tide")
        self.assertEqual(secret_portals["studio_to_darkroom"], "hidden_darkroom_open")
        self.assertEqual(secret_portals["cabin_to_basement"], "basement_open")


if __name__ == "__main__":
    unittest.main()
