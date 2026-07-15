import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def read(relative_path):
    return (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")


class VisualPolishContractTests(unittest.TestCase):
    def test_ambient_decorations_render_without_becoming_interactions(self):
        renderer = read("js/renderer.js")
        game = read("js/game.js")
        self.assertIn("const decorations = scene.decorations || []", renderer)
        self.assertIn('actors.push({ kind: "decoration"', renderer)
        self.assertIn('actors.push({ kind: "landmark"', renderer)
        self.assertIn('actor.kind === "decoration"', renderer)
        self.assertIn("this.drawDecoration(ctx, actor.state, palette)", renderer)
        self.assertIn("supportedObjectY(item)", renderer)
        self.assertIn("rectanglesOverlap(rect, normalizeRect(furniture))", renderer)
        self.assertNotIn("scene.decorations || []), ...getStoryLandmarks", renderer)
        self.assertIn("nearestLandmark(this.state, scene, 48, this.content)", game)

    def test_semantic_props_layers_and_sparse_signposts_have_dedicated_rendering(self):
        renderer = read("js/renderer.js")
        game = read("js/game.js")

        self.assertIn("drawDecoration(ctx, item, palette)", renderer)
        self.assertIn("drawPathsideDetails(ctx, scene, region, palette, visible, seed)", renderer)
        self.assertIn("drawSignpost(ctx, item, palette)", renderer)
        self.assertIn('type === "signpost"', renderer)
        for layer in ('"background"', '"wall"', '"foreground"'):
            self.assertIn(layer, renderer)
        self.assertIn('signpost: "阅读"', game)
        self.assertIn("landmark.destinations", game)

    def test_visual_landmarks_can_supply_precise_collision_footprints(self):
        renderer = read("js/renderer.js")

        self.assertIn("item.collisionRects", renderer)
        self.assertIn("item.collisionRect", renderer)
        self.assertIn("scene?.landmarks || []", renderer)
        self.assertIn("scene?.decorations || []", renderer)

    def test_pathside_props_are_kept_out_of_crossing_roads(self):
        renderer = read("js/renderer.js")

        self.assertIn("otherIndex !== pathIndex", renderer)
        self.assertIn("rectIntersects(footprint, normalizeRect(otherPath), 5)", renderer)

    def test_interiors_use_distinct_authored_shells(self):
        renderer = read("js/renderer.js")

        self.assertIn('"tower"', renderer)
        self.assertIn('"tent"', renderer)
        self.assertIn('"hall"', renderer)
        self.assertIn('"workshop"', renderer)
        self.assertIn('"home"', renderer)
        self.assertIn("authored shells", renderer)

    def test_player_has_original_traveler_details_and_run_feedback(self):
        renderer = read("js/renderer.js")
        self.assertIn('case "traveler"', renderer)
        self.assertIn('accessory: "traveler"', renderer)
        self.assertIn("drawRunDust(ctx, x, y, motion)", renderer)
        self.assertIn("if (!motion.running || !motion.moving) return", renderer)
        self.assertNotIn("stardew", renderer.lower())

    def test_ui_portraits_keep_cast_specific_identity(self):
        ui = read("js/ui.js")
        css = read("styles.css")
        self.assertIn("const PORTRAIT_SKINS", ui)
        self.assertIn("portraitAttributes(npc, known = true)", ui)
        self.assertIn("dataset.portrait = npc.id", ui)
        self.assertIn("var(--skin-color, #efbf87)", css)
        self.assertIn('[data-portrait="aveline"]', css)
        self.assertIn('[data-portrait="garrick"]', css)

    def test_contextual_landmark_verbs_are_available(self):
        game = read("js/game.js")
        for verb in ("阅读", "查看", "检查", "触碰", "端详", "观察", "探看"):
            self.assertIn(f'"{verb}"', game)


if __name__ == "__main__":
    unittest.main()
