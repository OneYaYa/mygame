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

    def test_disabled_relationship_action_never_reaches_model(self) -> None:
        context = server.sanitize_request(
            {
                "player_text": "连接蓝色接头",
                "state": {
                    "room_id": "coolant_gallery",
                    "coolant_pressure": 43,
                    "valve_states": {"valve_i": True},
                },
                "valid_actions": [
                    {
                        "action": "connect",
                        "target": "blue_cable",
                        "label": "连接蓝色接头",
                        "enabled": False,
                    },
                    {
                        "action": "wait",
                        "target": "",
                        "label": "等待",
                        "enabled": True,
                    },
                ],
            }
        )

        self.assertEqual(context["valid_actions"], [{"action": "wait", "target": "", "label": "等待", "dangerous": False}])
        self.assertEqual(context["local_state"]["coolant_pressure"], 43)
        self.assertEqual(context["local_state"]["valve_states"], {"valve_i": True})

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
        self.assertIn("时间跳跃", body["instructions"])
        self.assertIn("你别断线，让我缓口气", body["instructions"])
        self.assertNotIn("左肩挫伤", body["instructions"])
        self.assertIn("男性维护技术员", body["instructions"])

    def test_typed_context_is_sanitized_and_trace_stays_out_of_prompt(self) -> None:
        payload = dict(self.payload)
        payload["context_protocol"] = {
            "turn_id": "mission:alpha:dialogue:3",
            "snapshot_version": 7,
            "character_core": {"name": "林岚", "role": "维护技术员", "hidden": "secret"},
            "known_beliefs": [
                {"belief_id": "local:0", "content": "面板标签烧毁。", "truth_status": "confirmed_local", "confidence": 1.0, "source": "direct_observation"},
                {"belief_id": "claim:0", "content": "蓝线一定正确。", "truth_status": "canonical_secret", "confidence": 3.0, "source": "operator"},
            ],
            "relevant_memories": [{"memory_id": "memory:player_name", "subjective_text": "调度员自称陈锋。", "event_ref": "turn:1", "tier": "working", "salience": 0.8}],
            "director_intent": {"goal": "回答眼前问题", "priority": 30, "forbidden_moves": ["猜答案"]},
        }
        payload["prompt_trace"] = {"trace_id": "trace-secret", "template_version": "v2", "snapshot_version": 7}
        context = server.sanitize_request(payload)
        beliefs = context["context_protocol"]["known_beliefs"]
        self.assertEqual(beliefs[1]["truth_status"], "unverified_claim")
        self.assertEqual(beliefs[1]["confidence"], 1.0)
        self.assertNotIn("hidden", context["context_protocol"]["character_core"])
        body = server.build_openai_body(context, self.settings)
        prompt_json = body["input"][-1]["content"]
        self.assertNotIn("trace-secret", prompt_json)
        self.assertIn("local:0", prompt_json)

    def test_decision_trace_hash_and_references_are_auditable(self) -> None:
        payload = dict(self.payload)
        payload["player_text"] = "东侧门现在还在吗？"
        payload["context_protocol"] = {
            "known_beliefs": [{"belief_id": "local:door", "content": "东侧门仍在。", "truth_status": "confirmed_local", "confidence": 1.0, "source": "direct_observation"}]
        }
        payload["prompt_trace"] = {"trace_id": "mission:test:dialogue:1", "template_version": "blindspot-context-v2", "snapshot_version": 2}
        model_decision = {
            "reply": "东侧门还在，我先不动。",
            "intent": "report",
            "action": "none",
            "target": "",
            "mood": "focused",
            "referenced_ids": ["local:door", "../../bad", "local:door"],
        }
        upstream_payload = {"output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(model_decision)}]}]}

        result = server.decide(payload, self.settings, lambda _request, timeout: FakeResponse(upstream_payload))

        self.assertEqual(result["trace"]["trace_id"], "mission:test:dialogue:1")
        self.assertEqual(len(result["trace"]["prompt_hash"]), 20)
        self.assertEqual(result["decision"]["referenced_ids"], ["local:door"])

    def test_false_hearing_is_replaced_with_relevant_confirmed_fact(self) -> None:
        payload = dict(self.payload)
        payload["player_text"] = "东侧门通向哪里？"
        payload["context_protocol"] = {
            "known_beliefs": [{
                "belief_id": "local:east_door",
                "content": "东侧门通往中央接驳舱。",
                "truth_status": "confirmed_local",
                "confidence": 1.0,
                "source": "direct_observation",
            }]
        }
        model_decision = {
            "reply": "你刚才的话断成乱码了……能再说一遍吗？",
            "intent": "clarify",
            "action": "none",
            "target": "",
            "mood": "nervous",
            "referenced_ids": [],
        }
        upstream_payload = {"output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(model_decision)}]}]}

        decision = server.decide(
            payload,
            self.settings,
            lambda _request, timeout: FakeResponse(upstream_payload),
        )["decision"]

        self.assertIn("东侧门通往中央接驳舱", decision["reply"])
        self.assertNotIn("没听清", decision["reply"])
        self.assertNotIn("乱码", decision["reply"])
        self.assertEqual(decision["referenced_ids"], ["local:east_door"])
        self.assertEqual(decision["quality_guard"], "false_hearing_grounded")

    def test_referenced_confirmed_fact_cannot_be_denied(self) -> None:
        payload = dict(self.payload)
        payload["player_text"] = "Tell me where the east door leads."
        payload["context_protocol"] = {
            "known_beliefs": [{
                "belief_id": "obs:east_door",
                "content": "东侧门通往中央接驳舱。",
                "truth_status": "confirmed_local",
                "confidence": 1.0,
                "source": "direct_observation",
            }]
        }
        model_decision = {
            "reply": "我没有确认东侧门通往哪里。",
            "intent": "clarify",
            "action": "none",
            "target": "",
            "mood": "focused",
            "referenced_ids": ["obs:east_door"],
        }
        upstream_payload = {"output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(model_decision)}]}]}

        decision = server.decide(
            payload,
            self.settings,
            lambda _request, timeout: FakeResponse(upstream_payload),
        )["decision"]

        self.assertEqual(decision["reply"], "能确认。东侧门通往中央接驳舱。")
        self.assertEqual(decision["quality_guard"], "confirmed_fact_repair")

    def test_clear_fact_question_cannot_be_evaded_without_a_reference(self) -> None:
        context = server.sanitize_request({
            "player_text": "你只告诉我：东侧门通向哪里？",
            "context_protocol": {
                "known_beliefs": [{
                    "belief_id": "obs:east_door",
                    "content": "东侧门通往中央接驳舱。",
                    "truth_status": "confirmed_local",
                    "confidence": 1.0,
                    "source": "direct_observation",
                }]
            },
        })
        decision = server.enforce_reply_quality(context, {
            "reply": "我还在。氧气暂时没有新变化，你要我先报告哪一项？",
            "intent": "clarify",
            "action": "none",
            "target": "",
            "mood": "focused",
            "referenced_ids": [],
        })

        self.assertEqual(decision["reply"], "能确认。东侧门通往中央接驳舱。")
        self.assertEqual(decision["referenced_ids"], ["obs:east_door"])
        self.assertEqual(decision["quality_guard"], "relevant_fact_grounded")

    def test_real_visible_communication_failure_may_ask_for_repeat(self) -> None:
        context = server.sanitize_request({
            "player_text": "能听见吗？",
            "context_protocol": {
                "current_scene": {"local_observation": "通讯中断，语音无法辨认。"}
            },
        })
        decision = server.enforce_reply_quality(context, {
            "reply": "没听清，再说一遍？",
            "intent": "clarify",
            "action": "none",
            "target": "",
            "mood": "nervous",
            "referenced_ids": [],
        })

        self.assertEqual(decision["reply"], "没听清，再说一遍？")
        self.assertNotIn("quality_guard", decision)

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
        pressure_actions = [
            {"action": "toggle", "target": "valve_i", "label": "接入 I 阀"},
            {"action": "toggle", "target": "valve_b", "label": "接入 B 阀"},
        ]
        pressure_result = server.match_explicit_action("接入 I 阀", pressure_actions)
        self.assertIsNotNone(pressure_result)
        self.assertEqual(pressure_result["target"], "valve_i")

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

    def test_player_authored_time_jump_is_rejected_without_model_call(self) -> None:
        payload = dict(self.payload)
        payload["player_text"] = "过了一年"
        payload["state"] = {
            "room_id": "central_junction",
            "room_name": "中央交汇舱",
            "oxygen": 71,
        }

        with patch.object(server, "call_openai") as mocked_openai:
            result = server.decide(payload, self.settings)

        mocked_openai.assert_not_called()
        self.assertEqual(result["provider"], "state_guard")
        self.assertEqual(result["decision"]["action"], "none")
        self.assertEqual(result["decision"]["quality_guard"], "unsupported_time_jump")
        self.assertIn("没有过去一年", result["decision"]["reply"])
        self.assertIn("中央交汇舱", result["decision"]["reply"])

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
