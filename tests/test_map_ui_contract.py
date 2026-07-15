import json
import re
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
UI_PATH = PROJECT_ROOT / "js" / "ui.js"
CSS_PATH = PROJECT_ROOT / "styles.css"
INDEX_PATH = PROJECT_ROOT / "index.html"
MAPS_PATH = PROJECT_ROOT / "data" / "maps.json"

EXPECTED_REGION_IDS = {"capital", "farm", "mansion", "snow", "desert"}
EXPECTED_CONNECTIONS = {
    ("capital", "farm"): "road",
    ("capital", "mansion"): "carriage",
    ("capital", "snow"): "lift",
    ("desert", "farm"): "caravan",
    ("farm", "mansion"): "road",
    ("desert", "snow"): "trail",
}


def read(path):
    return path.read_text(encoding="utf-8")


class IllustratedWorldMapContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ui = read(UI_PATH)
        cls.css = read(CSS_PATH)
        cls.index = read(INDEX_PATH)
        cls.maps = json.loads(read(MAPS_PATH))

    def test_world_map_uses_original_artwork_and_landmark_icons(self):
        self.assertIn('class="world-map-art"', self.ui)
        self.assertIn("renderWorldMapArtwork(points)", self.ui)
        self.assertIn("mapRegionIcon(region.id)", self.ui)
        for region_id in EXPECTED_REGION_IDS:
            self.assertIn(f'regionId === "{region_id}"', self.ui)

        self.assertIn(".world-map-art", self.css)
        self.assertIn(".map-region__icon", self.css)
        self.assertIn(".map-art__farm", self.css)
        self.assertIn(".map-art__snow", self.css)
        self.assertIn(".map-art__sand", self.css)

        region_rule = re.search(r"\.map-region\s*\{(?P<body>[^}]*)\}", self.css, re.DOTALL)
        self.assertIsNotNone(region_rule)
        body = region_rule.group("body")
        self.assertIn("background: transparent", body)
        self.assertIn("border: 0", body)
        self.assertNotIn("background: var(--region-color", body)

    def test_drawn_routes_are_derived_from_actual_portals(self):
        self.assertIn("this.regionConnections(region.id)", self.ui)
        self.assertIn("mapRouteEdges()", self.ui)
        self.assertIn("this.mapRouteEdges().map", self.ui)
        for kind in {"road", "carriage", "lift", "caravan", "trail"}:
            self.assertIn(f"world-route--{kind}", self.css)

        connections = {}
        for source_id, region in self.maps["regions"].items():
            for portal in region.get("portals", []):
                target_id = portal.get("target", {}).get("regionId")
                if target_id not in EXPECTED_REGION_IDS or target_id == source_id:
                    continue
                edge = tuple(sorted((source_id, target_id)))
                connections.setdefault(edge, set()).add(portal.get("kind", "road"))

        self.assertEqual(set(connections), set(EXPECTED_CONNECTIONS))
        for edge, kind in EXPECTED_CONNECTIONS.items():
            self.assertIn(kind, connections[edge])

    def test_map_nodes_preserve_observer_controls_and_player_read_only_accessibility(self):
        self.assertIn('document.createElement(observer ? "button" : "article")', self.ui)
        self.assertIn('entry.setAttribute("aria-current", "location")', self.ui)
        self.assertIn('entry.setAttribute("aria-label"', self.ui)
        self.assertIn("entry.tabIndex = 0", self.ui)
        self.assertIn("this.callbacks.onTravel?.(region.id)", self.ui)
        self.assertIn("entry.disabled = current && !currentInterior", self.ui)
        self.assertNotIn("固定事件发生时，时间会自动暂停", self.index)


if __name__ == "__main__":
    unittest.main()
