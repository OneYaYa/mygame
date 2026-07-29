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
        npc_names = {npc["id"]: npc["name"] for npc in self.world["npcs"]}
        self.assertEqual("阿瑟·默瑟", npc_names["arthur"])
        self.assertEqual("贝娅特丽斯·黑尔", npc_names["beatrice"])
        self.assertEqual("埃利亚斯·奎因", npc_names["elias"])

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

    def test_world_interactions_do_not_bypass_npc_evidence_handoffs(self):
        game_js = (ROOT / "js" / "game.js").read_text(encoding="utf-8")
        self.assertNotIn("identifyPossessedTools", game_js)
        self.assertIn("索引卡不能自己检查你的背包", game_js)
        self.assertIn("把实物交给埃利亚斯并明确请求显影", game_js)

    def test_browser_npc_rules_keep_script_knowledge_boundaries(self):
        game_js = (ROOT / "js" / "game.js").read_text(encoding="utf-8")
        simulation_js = (ROOT / "js" / "simulation.js").read_text(encoding="utf-8")
        ai_js = (ROOT / "js" / "ai.js").read_text(encoding="utf-8")
        self.assertIn("isAssertiveTurn(turn)", game_js)
        self.assertIn("id: adaDutyUnknown ? 'hidden_figure' : npc.id", game_js)
        self.assertIn("主航道光保持不变；维修副光", simulation_js)
        self.assertNotIn("六声报时，第七声结束一项记录", ai_js)
        self.assertIn("collectFacts(npc?.knowledge?.public", ai_js)


if __name__ == "__main__":
    unittest.main()
