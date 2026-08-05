from __future__ import annotations

import io
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


PROJECT_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_DIR))

import server  # noqa: E402


class FakeResponse:
    def __init__(self, payload: dict):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self) -> bytes:
        return json.dumps(self.payload).encode("utf-8")


class ServerTests(unittest.TestCase):
    def test_take_action_matches_godot_core_vocabulary(self) -> None:
        context = server.sanitize_request(
            {
                "player_text": "拿起保险芯",
                "valid_actions": [
                    {
                        "action": "take",
                        "target": "phase_fuse",
                        "label": "拾取相位保险芯",
                    }
                ],
            }
        )

        self.assertEqual(context["valid_actions"][0]["action"], "take")

    def setUp(self) -> None:
        self.settings = server.Settings(
            api_key="test-key",
            base_url="https://api.openai.com/v1",
            model="gpt-5.6-luna",
            reasoning_effort="low",
            host="127.0.0.1",
            port=8787,
        )
        self.payload = {
            "player_text": "检查现在的房间，然后报告出口。",
            "state": {"room": "airlock", "oxygen": 88, "power": 61},
            "visible_observations": ["你在气闸室。", "东侧门通往维修廊。"],
            "valid_actions": [
                {"action": "inspect", "target": "airlock", "label": "检查气闸室"},
                {"action": "move", "target": "maintenance", "label": "前往维修廊"},
            ],
            "history": [{"role": "npc", "content": "中继建立。"}],
        }

    def test_sanitize_request_rejects_empty_text(self) -> None:
        bad = dict(self.payload)
        bad["player_text"] = "  "
        with self.assertRaises(ValueError):
            server.sanitize_request(bad)

    def test_sanitize_request_keeps_operator_telemetry_out_of_model_context(self) -> None:
        payload = dict(self.payload)
        payload["state"] = {
            "room_id": "power_bay",
            "oxygen": 72,
            "stress": "tense",
            "physical_state": "左肩挫伤、抬臂受限；仍能行走和单手操作。",
            "operator_telemetry": ["正确答案是 blue_cable"],
            "puzzles": {"power": "unsolved"},
        }
        context = server.sanitize_request(payload)
        self.assertIn("local_state", context)
        self.assertNotIn("operator_telemetry", context["local_state"])
        self.assertNotIn("puzzles", context["local_state"])
        self.assertIn("physical_state", context["local_state"])

    def test_request_uses_responses_structured_output(self) -> None:
        context = server.sanitize_request(self.payload)
        body = server.build_openai_body(context, self.settings)
        self.assertEqual(body["model"], "gpt-5.6-luna")
        self.assertFalse(body["store"])
        self.assertEqual(body["reasoning"]["effort"], "low")
        self.assertEqual(body["text"]["format"]["type"], "json_schema")
        self.assertTrue(body["text"]["format"]["strict"])
        self.assertIsInstance(body["input"], list)
        self.assertEqual(body["input"][-1]["role"], "user")
        self.assertIn("第一人称", body["instructions"])
        self.assertIn("不要写成医疗报告", body["instructions"])
        self.assertIn("不知道自己在游戏中", body["instructions"])
        self.assertIn("不要主动讲操作教程", body["instructions"])
        self.assertIn("你别断线，让我缓口气", body["instructions"])
        self.assertNotIn("左肩挫伤", body["instructions"])
        self.assertIn("男性维护技术员", body["instructions"])

    def test_call_openai_extracts_decision(self) -> None:
        model_decision = {
            "reply": "我先检查气闸室，确认东侧门是否安全。",
            "intent": "propose_action",
            "action": "inspect",
            "target": "airlock",
            "mood": "focused",
        }
        upstream_payload = {
            "status": "completed",
            "output": [
                {
                    "type": "message",
                    "content": [{"type": "output_text", "text": json.dumps(model_decision)}],
                }
            ],
        }
        captured = {}

        def fake_open(request, timeout):
            captured["request"] = request
            captured["timeout"] = timeout
            return FakeResponse(upstream_payload)

        context = server.sanitize_request(self.payload)
        result = server.call_openai(context, self.settings, fake_open)
        self.assertEqual(result["action"], "inspect")
        self.assertEqual(result["target"], "airlock")
        self.assertEqual(captured["timeout"], 30)
        sent = json.loads(captured["request"].data.decode("utf-8"))
        self.assertEqual(sent["model"], "gpt-5.6-luna")

    def test_invalid_model_action_is_downgraded(self) -> None:
        context = server.sanitize_request(self.payload)
        result = server.normalize_decision(
            {
                "reply": "我去反应堆。",
                "intent": "propose_action",
                "action": "move",
                "target": "reactor",
                "mood": "focused",
            },
            context["valid_actions"],
        )
        self.assertEqual(result["action"], "none")
        self.assertEqual(result["intent"], "clarify")
        self.assertNotIn("安全清单", result["reply"])
        self.assertIn("我现在做不了", result["reply"])

    def test_literal_action_label_is_resolved_locally(self) -> None:
        context = server.sanitize_request(self.payload)
        result = server.match_explicit_action("请先检查气闸室。", context["valid_actions"])
        self.assertIsNotNone(result)
        self.assertEqual(result["action"], "inspect")
        self.assertEqual(result["target"], "airlock")

    def test_ambiguous_puzzle_command_cannot_be_solved_by_model(self) -> None:
        payload = {
            "player_text": "该接哪一根？",
            "state": {"room_id": "power_bay", "oxygen": 70, "stress": "tense"},
            "visible_observations": ["三只接头的用途标签烧毁。"],
            "valid_actions": [
                {"action": "connect", "target": "blue_cable", "label": "连接蓝色套管接头"},
                {"action": "connect", "target": "red_cable", "label": "连接红色陶瓷接头"},
                {"action": "connect", "target": "yellow_cable", "label": "连接黄色编织接头"},
            ],
        }
        guessed = {
            "reply": "我建议蓝色。",
            "intent": "propose_action",
            "action": "connect",
            "target": "blue_cable",
            "mood": "nervous",
        }
        upstream_payload = {
            "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(guessed)}]}]
        }

        def fake_open(_request, timeout):
            self.assertEqual(timeout, 30)
            return FakeResponse(upstream_payload)

        result = server.decide(payload, self.settings, fake_open)["decision"]
        self.assertEqual(result["action"], "none")
        self.assertEqual(result["intent"], "clarify")
        self.assertIn("我不敢蒙", result["reply"])
        self.assertNotIn("I/B/P", result["reply"])

    def test_explicit_chinese_target_maps_deterministically(self) -> None:
        actions = [
            {"action": "connect", "target": "blue_cable", "label": "连接蓝色套管接头"},
            {"action": "connect", "target": "red_cable", "label": "连接红色陶瓷接头"},
        ]
        result = server.match_explicit_action("请连接蓝色接头", actions)
        self.assertIsNotNone(result)
        self.assertEqual(result["target"], "blue_cable")
        self.assertIsNone(server.match_explicit_action("连接一根接头", actions))

    def test_negated_conditional_and_question_actions_never_execute(self) -> None:
        actions = [
            {"action": "connect", "target": "blue_cable", "label": "连接蓝色套管接头"},
            {"action": "connect", "target": "red_cable", "label": "连接红色陶瓷接头"},
        ]
        for text in (
            "不要连接红色接头",
            "先别连接蓝色接头",
            "如果安全就连接红色接头",
            "可以连接蓝色接头吗",
            "我不是让你连接红色接头",
        ):
            self.assertIsNone(server.match_explicit_action(text, actions), text)

    def test_model_action_is_cleared_for_negated_single_target_request(self) -> None:
        payload = {
            "player_text": "先别去维修廊",
            "state": {"room_id": "airlock", "oxygen": 82},
            "visible_observations": ["东侧门通往维修廊。"],
            "valid_actions": [
                {"action": "move", "target": "maintenance", "label": "前往维修廊"}
            ],
        }
        guessed = {
            "reply": "我去维修廊。",
            "intent": "propose_action",
            "action": "move",
            "target": "maintenance",
            "mood": "focused",
        }
        upstream_payload = {
            "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(guessed)}]}]
        }

        def fake_open(_request, timeout):
            self.assertEqual(timeout, 30)
            return FakeResponse(upstream_payload)

        result = server.decide(payload, self.settings, fake_open)["decision"]
        self.assertEqual(result["action"], "none")
        self.assertEqual(result["intent"], "refuse")
        self.assertIn("我不动", result["reply"])

    def test_conversation_memory_is_bounded_and_forwarded(self) -> None:
        payload = dict(self.payload)
        payload["history"] = [
            {"role": "player", "content": "我叫陈锋。"},
            {"role": "npc", "content": "记住了。"},
        ]
        payload["conversation_memory"] = {
            "player_name": "陈锋",
            "promises": ["我会保持通讯。"],
            "hidden": "must not pass",
        }
        context = server.sanitize_request(payload)
        self.assertEqual(context["conversation_memory"]["player_name"], "陈锋")
        self.assertNotIn("hidden", context["conversation_memory"])
        body = server.build_openai_body(context, self.settings)
        self.assertEqual([item["role"] for item in body["input"][:2]], ["user", "assistant"])

    def test_explicit_name_recall_uses_deterministic_memory(self) -> None:
        payload = dict(self.payload)
        payload["player_text"] = "我叫什么？"
        payload["conversation_memory"] = {"player_name": "陈锋", "promises": []}

        with patch.object(server, "call_openai") as mocked_openai:
            result = server.decide(payload, self.settings)

        mocked_openai.assert_not_called()
        self.assertEqual(result["provider"], "memory")
        self.assertEqual(result["decision"]["action"], "none")
        self.assertIn("陈锋", result["decision"]["reply"])

    def test_explicit_action_reply_stays_in_character(self) -> None:
        actions = [
            {"action": "connect", "target": "blue_cable", "label": "连接蓝色套管接头"},
            {"action": "connect", "target": "red_cable", "label": "连接红色陶瓷接头"},
        ]
        payload = {
            "player_text": "请连接蓝色接头",
            "state": {"room_id": "power_bay", "oxygen": 70},
            "visible_observations": ["三只接头的用途标签烧毁。"],
            "valid_actions": actions,
        }
        model_decision = {
            "reply": "收到。",
            "intent": "conversation",
            "action": "none",
            "target": "",
            "mood": "nervous",
        }
        upstream_payload = {
            "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(model_decision)}]}]
        }

        def fake_open(_request, timeout):
            self.assertEqual(timeout, 30)
            return FakeResponse(upstream_payload)

        result = server.decide(payload, self.settings, fake_open)["decision"]
        self.assertEqual(result["action"], "connect")
        self.assertEqual(result["target"], "blue_cable")
        self.assertNotIn("复述", result["reply"])
        self.assertNotIn("授权", result["reply"])
        self.assertIn("等你这边确认", result["reply"])

    def test_decide_does_not_expose_key(self) -> None:
        model_decision = {
            "reply": "收到。",
            "intent": "report",
            "action": "none",
            "target": "",
            "mood": "steady",
        }
        upstream_payload = {
            "output": [
                {
                    "type": "message",
                    "content": [{"type": "output_text", "text": json.dumps(model_decision)}],
                }
            ]
        }

        def fake_open(_request, timeout):
            self.assertEqual(timeout, 30)
            return FakeResponse(upstream_payload)

        result = server.decide(self.payload, self.settings, fake_open)
        self.assertNotIn("api_key", result)
        self.assertEqual(result["provider"], "openai")


if __name__ == "__main__":
    unittest.main()
