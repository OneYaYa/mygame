from __future__ import annotations

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
    match = re.search(rf"(?:export\s+)?function\s+{re.escape(name)}\s*\(", source)
    if not match:
        raise AssertionError(f"function {name} not found")
    parameter_start = match.end() - 1
    parameter_depth = 0
    parameter_end = None
    for index in range(parameter_start, len(source)):
        if source[index] == "(":
            parameter_depth += 1
        elif source[index] == ")":
            parameter_depth -= 1
            if parameter_depth == 0:
                parameter_end = index
                break
    if parameter_end is None:
        raise AssertionError(f"function {name} has no closing parenthesis")
    start = source.find("{", parameter_end)
    if start < 0:
        raise AssertionError(f"function {name} has no opening brace")
    depth = 0
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:index]
    raise AssertionError(f"function {name} has no closing brace")


def method_body(source: str, name: str) -> str:
    match = re.search(rf"(?:async\s+)?{re.escape(name)}\s*\([^)]*\)\s*\{{", source)
    if not match:
        raise AssertionError(f"method {name} not found")
    start = match.end() - 1
    depth = 0
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:index]
    raise AssertionError(f"method {name} has no closing brace")


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

    def test_journal_rendering_cannot_consume_simulation_rng(self):
        simulation = read("js/simulation.js")
        body = function_body(simulation, "addJournal")

        self.assertNotIn("nextRandom", body)
        self.assertIn("state.journalSequence", body)
        self.assertIn("hashString(text)", body)

    def test_key_events_have_no_forced_choice_surface(self):
        index = read("index.html")
        ui = read("js/ui.js")
        game = read("js/game.js")
        styles = read("styles.css")
        combined_runtime = "\n".join((ui, game))

        for forbidden_dom_id in ("event-modal", "event-title", "event-choices", "event-countdown"):
            self.assertNotIn(f'id="{forbidden_dom_id}"', index)
        for forbidden_runtime_name in (
            "showEvent",
            "closeEvent",
            "onEventChoice",
            "processPendingEvents",
            "resolveEventAutonomously",
            "eventOpen",
            "eventAutoSeconds",
        ):
            self.assertNotIn(forbidden_runtime_name, combined_runtime)
        self.assertNotIn(".event-modal", styles)

    def test_story_process_activates_and_resolves_inside_world_time(self):
        simulation = read("js/simulation.js")
        advance_story = function_body(simulation, "advanceStoryEvents")
        resolve_story = function_body(simulation, "resolveStoryEvent")
        advance_world = function_body(simulation, "advanceWorld")

        self.assertIn('story.status === "dormant"', advance_story)
        self.assertIn("eventStartClock(event)", advance_story)
        self.assertIn('story.status = "active"', advance_story)
        self.assertIn("eventResolutionClock(event)", advance_story)
        self.assertIn("resolveStoryEvent(state, content, event)", advance_story)
        self.assertIn("npcSupportsChoice", resolve_story)
        self.assertIn("story.influencedNpcs", resolve_story)
        self.assertIn('actor: "world"', resolve_story)
        self.assertIn("applyEventChoice", resolve_story)
        self.assertIn("advanceStoryEvents(state, content", advance_world)
        self.assertIn("events: []", advance_world)
        self.assertNotIn("pendingEvents.push", advance_world)

    def test_refused_social_proposals_become_causal_memories(self):
        simulation = read("js/simulation.js")
        game = read("js/game.js")
        fresh = function_body(simulation, "freshStoryState")
        eligible = function_body(simulation, "eligibleSocialChoices")
        commit = function_body(simulation, "commitNpcStoryProposal")
        resolve_story = function_body(simulation, "resolveStoryEvent")
        history = function_body(simulation, "historicalChoiceScore")

        self.assertIn("rejectedNpcs: {}", fresh)
        self.assertIn("story.rejectedNpcs", eligible)
        self.assertIn("uniquePush(story.rejectedNpcs[npcId], match.choice.id)", commit)
        self.assertIn("accepted: false", commit)
        self.assertIn("state.statistics.rejections", commit)
        self.assertIn("rejectingParticipants.length * 1.75", resolve_story)
        self.assertIn("item.accepted !== false", history)
        self.assertIn("item.accepted === false", history)
        self.assertIn("hasAnotherApproach", game)
        self.assertRegex(game, r"storyButton\s*&&\s*!hasAnotherApproach")
        self.assertIn('"refusal",', game)

    def test_player_evidence_does_not_make_society_depend_on_player_presence(self):
        simulation = read("js/simulation.js")
        availability = function_body(simulation, "choiceAvailableToSociety")

        self.assertIn('choice.requirementsScope !== "player-evidence"', availability)
        self.assertIn("story.influencedNpcs", availability)
        self.assertIn("story.autonomousDiscoveries.includes(choice.id)", availability)
        self.assertIn("npc-discovery", availability)
        self.assertIn("uniquePush(story.autonomousDiscoveries, choice.id)", availability)

    def test_observer_is_read_only_while_the_same_world_process_runs(self):
        game = read("js/game.js")
        simulation = read("js/simulation.js")

        self.assertRegex(game, r'interact\(\)\s*\{\s*if \(!this\.state \|\| this\.state\.mode === "observer"\) return;')
        self.assertRegex(game, r'openConversation\([^)]*\)\s*\{\s*if \(this\.state\?\.mode === "observer"\) return;')
        self.assertRegex(game, r'async talk\([^)]*\)\s*\{\s*if \(this\.state\?\.mode === "observer"')
        self.assertRegex(game, r'inspectLandmark\([^)]*\)\s*\{\s*if \(this\.state\?\.mode === "observer"\) return;')
        self.assertRegex(game, r'usePortal\([^)]*\)\s*\{\s*if \(!this\.state \|\| this\.state\.mode === "observer"')
        self.assertIn('story: Object.fromEntries((content.events || []).map((event) => [event.id, freshStoryState(event, isObserver)]))', simulation)
        self.assertIn("story.discovered = true", function_body(simulation, "advanceStoryEvents"))

    def test_core_memories_survive_routine_memory_rotation(self):
        simulation = read("js/simulation.js")
        game = read("js/game.js")
        initial_npc = function_body(simulation, "initialNpcState")
        remember = function_body(simulation, "remember")

        self.assertIn("coreMemories: []", initial_npc)
        self.assertIn("Number(importance) >= 3", remember)
        self.assertIn("npcState.coreMemories", remember)
        self.assertRegex(remember, r"coreMemories.*\.slice\(0,\s*\d+\)")
        self.assertIn("coreMemories: npcState.coreMemories", game)
        self.assertIn("...(npcState?.coreMemories || [])", game)

    def test_npc_ai_receives_filtered_story_knowledge(self):
        simulation = read("js/simulation.js")
        game = read("js/game.js")
        story_context = function_body(simulation, "getNpcStoryContext")

        self.assertIn("rumor.npcId === npcId", story_context)
        self.assertIn("requirementsMet(rumor, state).ok", story_context)
        self.assertIn("storyParticipants(event).includes(npcId)", story_context)
        self.assertIn("publicFlagIds", game)
        self.assertIn("Object.entries(this.state.flags).filter", game)
        self.assertNotIn("flags: deepClone(this.state.flags)", game)
        self.assertIn("story_context: npcId ? getNpcStoryContext", game)

    def test_process_and_outcome_knowledge_are_independent(self):
        simulation = read("js/simulation.js")
        fresh = function_body(simulation, "freshStoryState")
        discover = function_body(simulation, "discoverStoryClue")
        reveal = function_body(simulation, "revealNpcStoryKnowledge")
        eligible = function_body(simulation, "eligibleSocialChoices")
        resolve_story = function_body(simulation, "resolveStoryEvent")

        self.assertIn("processKnown: observer", fresh)
        self.assertIn("outcomeKnown: false", fresh)
        self.assertIn('const learningOutcome = story.status === "resolved"', discover)
        self.assertIn("if (learningOutcome) story.outcomeKnown = true", discover)
        self.assertIn("else story.processKnown = true", discover)
        self.assertIn("story.processKnown = true", reveal)
        self.assertIn("!story.outcomeKnown", reveal)
        self.assertIn("story.outcomeKnown = true", reveal)
        self.assertIn("!story.processKnown", eligible)
        self.assertNotIn("!story.discovered", eligible)
        self.assertIn("!story.processKnown", resolve_story)
        self.assertIn("outcomeKnown: story.outcomeKnown", resolve_story)

    def test_story_followups_do_not_expose_authored_choice_lines(self):
        simulation = read("js/simulation.js")
        ui = read("js/ui.js")
        topics = function_body(simulation, "getStoryConversationTopics")
        open_conversation = method_body(ui, "openConversation")

        self.assertIn("byEvent", topics)
        self.assertIn("choiceId: null", topics)
        self.assertIn('intent: "custom"', topics)
        for forbidden in ("choice.label", "social.topic", "social.playerLine", "social.keywords"):
            self.assertNotIn(forbidden, topics)
        self.assertIn("topic.label", open_conversation)
        self.assertIn("topic.message", open_conversation)
        self.assertNotIn("topic.choiceId", open_conversation)

    def test_story_actions_are_bounded_and_backend_actions_are_revalidated(self):
        game = read("js/game.js")
        ai = read("js/ai.js")
        server = read("server.py")
        talk = method_body(game, "talk")
        local_brain = method_body(ai, "_localBrain")
        ask_backend = method_body(ai, "_askBackend")

        self.assertIn('`endorse:${actionSuffix}`', talk)
        self.assertIn('`refuse:${actionSuffix}`', talk)
        self.assertIn('id: "continue_conversation"', talk)
        self.assertIn("candidateByAction.get(String(result.action", talk)
        self.assertIn('startsWith("endorse:")', local_brain)
        self.assertIn('`refuse:${suffix}`', local_brain)
        self.assertIn('item.id === "continue_conversation"', local_brain)
        self.assertIn("allowedIds", ask_backend)
        self.assertIn("allowedIds.includes(action)", ask_backend)
        self.assertIn('throw new Error("decision_action_not_allowed")', ask_backend)
        self.assertIn("If npc_profile.allowed_actions is present", server)
        self.assertIn("choose continue_conversation", server)

    def test_conversation_session_guards_stale_replies_and_saves_disclosures(self):
        game = read("js/game.js")
        constructor = method_body(game, "constructor")
        open_conversation = method_body(game, "openConversation")
        talk = method_body(game, "talk")
        modal_change = method_body(game, "onModalChange")

        self.assertIn("this.conversationSession = 0", constructor)
        self.assertIn("const session = ++this.conversationSession", open_conversation)
        self.assertIn("this.activeConversation = { npc, npcState, session }", open_conversation)
        self.assertIn("const { npc, npcState, session } = this.activeConversation", talk)
        self.assertIn("this.activeConversation.session !== session", talk)
        self.assertIn("finally", talk)
        self.assertIn("this.activeConversation?.session === session", talk)
        self.assertIn('id === "conversation-modal" && !open', modal_change)
        self.assertIn("this.conversationSession += 1", modal_change)
        self.assertIn("this.activeConversation = null", modal_change)

        disclosure_start = open_conversation.index("if (disclosure)")
        disclosure_end = open_conversation.index("this.audio.play", disclosure_start)
        disclosure_block = open_conversation[disclosure_start:disclosure_end]
        self.assertIn("remember(this.state, npc.id, disclosure.memory", disclosure_block)
        self.assertIn("this.save(false)", disclosure_block)

    def test_legacy_v2_saves_migrate_core_memory_and_story_knowledge(self):
        game = read("js/game.js")
        migration = method_body(game, "normalizeLoadedState")

        self.assertIn("legacyCore", migration)
        self.assertIn("Number(memory?.importance || 0) >= 3", migration)
        self.assertIn("coreMemories: npcState.coreMemories || legacyCore", migration)
        self.assertIn("Number(saved.version || 2) < 3", migration)
        self.assertIn("const completed = new Set(saved.completedEvents || [])", migration)
        self.assertIn("const pending = new Set(saved.pendingEvents || [])", migration)
        self.assertIn("story.processKnown = true", migration)
        self.assertIn("story.outcomeKnown = true", migration)
        self.assertIn("merged.version = 3", migration)

    def test_portal_access_is_checked_before_transition(self):
        game = read("js/game.js")
        use_portal = method_body(game, "usePortal")

        self.assertIn("portal.access", use_portal)
        self.assertIn("portal.access.all", use_portal)
        self.assertIn("portal.access.any", use_portal)
        self.assertIn("requirementsMet", use_portal)
        self.assertIn("portal.access.denied", use_portal)
        self.assertLess(use_portal.index("portal.access"), use_portal.index("this.setTransitionLock(true)"))


if __name__ == "__main__":
    unittest.main()
