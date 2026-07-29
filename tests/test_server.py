import json
import unittest
from pathlib import Path

from server import (
    DEFAULT_MODEL,
    DECISION_SCHEMA,
    SYSTEM_PROMPT,
    ServerConfig,
    _extract_decision,
    _responses_url,
)


ROOT = Path(__file__).resolve().parents[1]


class OpenAIResponsesContractTests(unittest.TestCase):
    def test_openai_environment_is_preferred_and_legacy_names_still_work(self):
        config = ServerConfig.from_env(
            {
                "OPENAI_API_KEY": "test-key",
                "OPENAI_MODEL": "gpt-5.6-luna",
                "OPENAI_REASONING_EFFORT": "low",
            },
            static_root=ROOT,
        )
        self.assertTrue(config.llm_configured)
        self.assertEqual(config.llm_model, "gpt-5.6-luna")
        self.assertEqual(config.llm_reasoning_effort, "low")
        self.assertEqual(config.public_dict()["llm"]["provider"], "openai-responses")

        legacy = ServerConfig.from_env(
            {"LLM_API_KEY": "legacy-key", "LLM_MODEL": "legacy-model"},
            static_root=ROOT,
        )
        self.assertEqual(legacy.llm_model, "legacy-model")

    def test_defaults_and_responses_endpoint(self):
        config = ServerConfig.from_env({}, static_root=ROOT)
        self.assertEqual(config.llm_model, DEFAULT_MODEL)
        self.assertEqual(
            _responses_url("https://api.openai.com/v1"),
            "https://api.openai.com/v1/responses",
        )
        self.assertEqual(
            _responses_url("https://api.openai.com/v1/responses"),
            "https://api.openai.com/v1/responses",
        )

    def test_extracts_structured_responses_output(self):
        decision = {
            "reply": "先把本轮证据放在桌上。",
            "action": "continue_conversation",
            "reason": "只承认共同核验的事实。",
            "memory": "玩家询问了七号房。",
        }
        envelope = {
            "output": [{
                "type": "message",
                "content": [{
                    "type": "output_text",
                    "text": json.dumps(decision, ensure_ascii=False),
                }],
            }],
        }
        self.assertEqual(_extract_decision(envelope), decision)

    def test_schema_is_strict_and_closed(self):
        self.assertFalse(DECISION_SCHEMA["additionalProperties"])
        self.assertEqual(
            set(DECISION_SCHEMA["required"]),
            {"reply", "action", "reason", "memory"},
        )

    def test_npc_prompt_enforces_continuity_and_executable_actions(self):
        self.assertIn("recent_dialogue", SYSTEM_PROMPT)
        self.assertIn("Do not greet again", SYSTEM_PROMPT)
        self.assertIn("Do not ask the player to present", SYSTEM_PROMPT)
        self.assertIn("Possession is not presentation", SYSTEM_PROMPT)
        self.assertIn(
            "A world-changing action that is absent from the list is forbidden",
            SYSTEM_PROMPT.replace("\n", " "),
        )
        self.assertIn("Treat supplied geography and object facts as a closed world", SYSTEM_PROMPT)
        self.assertIn("a key does not prove that a matching visible door exists", SYSTEM_PROMPT)


if __name__ == "__main__":
    unittest.main()
