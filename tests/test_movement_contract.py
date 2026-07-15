from __future__ import annotations

import re
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")


class MovementContractTests(unittest.TestCase):
    def test_shift_sprint_is_player_only_and_uses_a_bounded_multiplier(self):
        game = read("js/game.js")

        multiplier = re.search(r"PLAYER_SPRINT_MULTIPLIER\s*=\s*([\d.]+)", game)
        self.assertIsNotNone(multiplier)
        self.assertGreaterEqual(float(multiplier.group(1)), 1.5)
        self.assertLessEqual(float(multiplier.group(1)), 2.0)
        self.assertIn('"shift"].includes(key)', game)
        self.assertIn('!observer && canMove && moving && this.keys.has("shift")', game)
        self.assertIn("sprinting ? PLAYER_SPRINT_MULTIPLIER : 1", game)

    def test_real_displacement_drives_steps_and_renderer_motion(self):
        game = read("js/game.js")

        self.assertIn("playerMoved = movePlayer", game)
        self.assertIn("if (playerMoved)", game)
        self.assertIn("sprinting ? RUN_STEP_INTERVAL : WALK_STEP_INTERVAL", game)
        self.assertIn("this.renderer.setMoving(playerMoved, sprinting)", game)
        self.assertIn("this.stepTimer = 0", game)
        self.assertLess(game.index("if (playerMoved)"), game.index('this.audio.play("step")'))

    def test_collision_motion_is_substepped_and_reports_real_movement(self):
        renderer = read("js/renderer.js")

        max_step = re.search(r"MAX_COLLISION_STEP\s*=\s*([\d.]+)", renderer)
        self.assertIsNotNone(max_step)
        self.assertLessEqual(float(max_step.group(1)), 5.0)
        self.assertIn("Math.ceil(Math.max(Math.abs(dx), Math.abs(dy)) / MAX_COLLISION_STEP)", renderer)
        self.assertIn("for (let step = 0; step < steps; step += 1)", renderer)
        self.assertIn("Math.hypot(player.x - startX, player.y - startY) > .01", renderer)

    def test_npcs_use_cached_collision_safe_routes_instead_of_straight_line_motion(self):
        renderer = read("js/renderer.js")

        self.assertIn("const NPC_ROUTE_CACHE = new Map()", renderer)
        self.assertIn("export function planNpcRoute", renderer)
        self.assertIn("getCollisionRects(scene)", renderer)
        self.assertIn("actorFootRect(x, y)", renderer)
        self.assertIn("segmentWalkable(scene", renderer)
        self.assertIn("moveNpcWithCollision(npcState, scene", renderer)
        self.assertIn("route.key !== routeKey", renderer)
        self.assertIn("routeDiscontinuous", renderer)
        self.assertIn("route.waypoints[route.index]", renderer)
        self.assertNotIn("npcState.x += dx / length * travel", renderer)

    def test_running_has_a_distinct_faster_and_wider_animation(self):
        renderer = read("js/renderer.js")

        frame_count = int(re.search(r"MOTION_FRAME_COUNT\s*=\s*(\d+)", renderer).group(1))
        walk_rate = float(re.search(r"WALK_FRAME_RATE\s*=\s*([\d.]+)", renderer).group(1))
        run_rate = float(re.search(r"RUN_FRAME_RATE\s*=\s*([\d.]+)", renderer).group(1))
        self.assertGreaterEqual(frame_count, 6)
        self.assertGreater(run_rate, walk_rate)
        self.assertIn("running ? RUN_FRAME_RATE : WALK_FRAME_RATE", renderer)
        self.assertIn("const strideScale = running ? 1.65 : 1", renderer)
        self.assertIn("[0, 1, 2, 0, -1, -2][frame]", renderer)
        self.assertIn("frame === 2 || frame === 5", renderer)
        self.assertIn("running: motion.running", renderer)

    def test_idle_blink_and_sprint_dust_follow_the_six_phase_gait(self):
        renderer = read("js/renderer.js")

        self.assertIn("const blink = !moving", renderer)
        self.assertIn("const blink = Boolean(style.blink)", renderer)
        self.assertIn("motion.walkFrame % MOTION_FRAME_COUNT", renderer)
        self.assertIn("phase !== 2 && phase !== 5", renderer)

    def test_sprint_help_is_consistent(self):
        index = read("index.html")
        ui = read("js/ui.js")
        readme = read("README.md")

        self.assertIn("<kbd>Shift</kbd><span>按住疾跑</span>", index)
        self.assertIn("按住 Shift 疾跑", ui)
        self.assertIn("| 疾跑 |", readme)
        self.assertIn("1.75 倍", readme)


if __name__ == "__main__":
    unittest.main()
