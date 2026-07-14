from __future__ import annotations

import json
import re
import unittest
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]


class IdCollector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids: list[str] = []

    def handle_starttag(self, _tag, attrs):
        values = dict(attrs)
        if values.get("id"):
            self.ids.append(values["id"])


def read(relative_path: str) -> str:
    return (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")


def function_body(source: str, name: str) -> str:
    match = re.search(rf"(?:export\s+)?function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{", source)
    if not match:
        raise AssertionError(f"function {name} not found")
    start = match.end() - 1
    depth = 0
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:index]
    raise AssertionError(f"function {name} has no closing brace")


class ObserverModeContractTests(unittest.TestCase):
    def test_observer_dom_contract_is_complete_and_unique(self):
        parser = IdCollector()
        index = read("index.html")
        parser.feed(index)
        counts = Counter(parser.ids)
        required = {
            "observe-game-button",
            "mode-chip",
            "observer-badge",
            "observer-modal",
            "observer-name",
            "observer-goal",
            "observer-reflection",
            "observer-memories",
            "observer-knowledge",
        }
        self.assertTrue(required.issubset(counts), required - set(counts))
        self.assertFalse({item for item, count in counts.items() if count > 1})
        self.assertIn('class="timeline-difficulty-flow"', index)

    def test_mode_is_forwarded_from_entry_to_world_state(self):
        ui = read("js/ui.js")
        game = read("js/game.js")
        simulation = read("js/simulation.js")
        self.assertIn('prepareTimelineSelection("observer")', ui)
        self.assertIn("onNewGame?.(timeline.id, this.startMode)", ui)
        self.assertRegex(game, r"onNewGame:\s*\(timelineId,\s*mode\)\s*=>\s*this\.startNewGame\(timelineId,\s*mode\)")
        self.assertRegex(game, r"startNewGame\(timelineId,\s*mode\s*=\s*\"player\"\)")
        self.assertIn("createInitialState(this.content, timelineId, mode)", game)
        self.assertRegex(simulation, r"createInitialState\(content,\s*timelineId,\s*mode\s*=\s*\"player\"\)")
        self.assertIn('mode: gameMode', simulation)
        self.assertIn('present: !isObserver', simulation)
        self.assertIn("difficulty: getTimelineDifficulty(content, timeline.id)", simulation)
        self.assertIn("difficulty.npcRecovery", simulation)
        self.assertIn(".dailyDrain", simulation)
        self.assertIn('class="timeline-difficulty"', ui)

    def test_legacy_saves_explicitly_default_to_player(self):
        game = read("js/game.js")
        self.assertIn('const mode = saved.mode === "observer" ? "observer" : "player";', game)
        self.assertIn('merged.player.present = mode !== "observer";', game)
        self.assertIn('merged.flags.playerArrived = mode !== "observer";', game)
        self.assertIn("merged.timelineName = fresh.timelineName;", game)
        self.assertIn("merged.difficulty = fresh.difficulty;", game)

    def test_observe_region_has_no_travel_or_time_side_effects(self):
        simulation = read("js/simulation.js")
        body = function_body(simulation, "observeRegion")
        self.assertIn("state.regionId = regionId", body)
        for forbidden in ("advanceWorld", "addJournal", "state.player", "journeys", "rngState", "nextRandom"):
            self.assertNotIn(forbidden, body)

    def test_observer_camera_cannot_change_simulation_rng(self):
        simulation = read("js/simulation.js")
        body = function_body(simulation, "runAutonomousHour")
        self.assertNotIn("state.regionId", body)
        self.assertNotIn("nextRandom(state)", body)
        self.assertIn('hashString(`${state.seed}:${hourIndex}:${npc.id}:log`)', body)

    def test_observer_event_choices_are_read_only_and_world_resolved(self):
        ui = read("js/ui.js")
        game = read("js/game.js")
        self.assertIn("button.disabled = observer || !status.ok", ui)
        self.assertIn('if (!observer) button.addEventListener("click"', ui)
        self.assertIn('this.state?.mode === "observer" && options.actor !== "world"', game)
        self.assertIn('this.eventAutoSeconds = observer ? 5 : 30', game)
        self.assertIn('{ actor: "world" }', game)

    def test_every_event_has_an_autonomous_candidate(self):
        world = json.loads(read("data/world.json"))
        for event in world["events"]:
            candidates = [
                choice for choice in event.get("choices", [])
                if not choice.get("requirements") and not choice.get("requires")
            ]
            self.assertTrue(candidates, f'{event["id"]} has no unconditional autonomous choice')


if __name__ == "__main__":
    unittest.main()
