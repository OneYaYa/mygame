from __future__ import annotations

import json
import socket
import sys
import threading
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest import mock
from urllib import error as client_error
from urllib import request as client_request


PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import server  # noqa: E402


def make_config(
    *, api_key=None, max_request_bytes=server.DEFAULT_MAX_REQUEST_BYTES, timeout=1.0
):
    return server.ServerConfig(
        static_root=PROJECT_ROOT,
        llm_api_key=api_key,
        llm_base_url="https://llm.example.test/v1",
        llm_model="test-model",
        max_request_bytes=max_request_bytes,
        llm_timeout_seconds=timeout,
    )


@contextmanager
def running_server(config):
    httpd = server.create_server("127.0.0.1", 0, config)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        host, port = httpd.server_address[:2]
        yield f"http://{host}:{port}"
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=2)


def http_json(base_url, path, *, method="GET", body=None, raw_body=None):
    headers = {"Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    elif raw_body is not None:
        data = raw_body
        headers["Content-Type"] = "application/json"
    request = client_request.Request(
        base_url + path, data=data, headers=headers, method=method
    )
    try:
        response = client_request.urlopen(request, timeout=2)
    except client_error.HTTPError as exc:
        with exc:
            return exc.code, json.loads(exc.read().decode("utf-8"))
    with response:
        return response.status, json.loads(response.read().decode("utf-8"))


VALID_REQUEST = {
    "npc_profile": {"name": "Mira", "role": "farmer"},
    "world_state": {"area": "farm", "time": "08:00"},
    "player_message": "早上好",
    "memories": ["The player helped repair the well."],
}


class ConfigTests(unittest.TestCase):
    def test_environment_configuration_and_public_allow_list(self):
        secret = "never-send-this-to-the-browser"
        config = server.ServerConfig.from_env(
            {
                "LLM_API_KEY": secret,
                "LLM_BASE_URL": "https://provider.example/v1/",
                "LLM_MODEL": "story-model",
                "MAX_REQUEST_BYTES": "12345",
                "LLM_TIMEOUT_SECONDS": "3.5",
            },
            static_root=PROJECT_ROOT,
        )
        self.assertTrue(config.llm_configured)
        self.assertEqual(config.llm_model, "story-model")
        self.assertEqual(config.max_request_bytes, 12345)
        self.assertEqual(config.llm_timeout_seconds, 3.5)

        public_json = json.dumps(config.public_dict())
        self.assertNotIn(secret, public_json)
        self.assertNotIn("LLM_API_KEY", public_json)
        self.assertNotIn("provider.example", public_json)
        self.assertEqual(config.public_dict()["llm"]["configured"], True)

    def test_invalid_base_url_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "absolute http"):
            server.ServerConfig.from_env(
                {"LLM_BASE_URL": "file:///tmp/model"}, static_root=PROJECT_ROOT
            )


class ApiTests(unittest.TestCase):
    def test_health_and_config_are_safe_without_a_key(self):
        with running_server(make_config()) as base_url:
            status, health = http_json(base_url, "/api/health")
            self.assertEqual(status, 200)
            self.assertEqual(health["status"], "healthy")
            self.assertFalse(health["llm_configured"])

            status, public_config = http_json(base_url, "/api/config")
            self.assertEqual(status, 200)
            self.assertFalse(public_config["llm"]["configured"])
            self.assertNotIn("api_key", json.dumps(public_config).lower())

    def test_static_server_blocks_environment_and_backend_files(self):
        with running_server(make_config()) as base_url:
            for private_path in ("/.env.example", "/SERVER.PY", "/tests/test_server.py"):
                with self.subTest(path=private_path):
                    with self.assertRaises(client_error.HTTPError) as raised:
                        client_request.urlopen(base_url + private_path, timeout=2)
                    self.assertEqual(raised.exception.code, 404)
                    raised.exception.close()

    def test_missing_key_returns_recognizable_rules_fallback(self):
        with running_server(make_config()) as base_url:
            status, result = http_json(
                base_url, "/api/npc/decide", method="POST", body=VALID_REQUEST
            )
        self.assertEqual(status, 503)
        self.assertEqual(result["error"]["code"], "llm_not_configured")
        self.assertEqual(result["fallback"], "rules")
        self.assertFalse(result["retryable"])

    def test_invalid_json_and_missing_fields_return_clear_400_errors(self):
        with running_server(make_config()) as base_url:
            status, malformed = http_json(
                base_url,
                "/api/npc/decide",
                method="POST",
                raw_body=b"{not-json",
            )
            missing_status, missing = http_json(
                base_url,
                "/api/npc/decide",
                method="POST",
                body={"npc_profile": {}},
            )
        self.assertEqual(status, 400)
        self.assertEqual(malformed["error"]["code"], "invalid_request")
        self.assertIn("invalid JSON", malformed["error"]["message"])
        self.assertEqual(missing_status, 400)
        self.assertIn("world_state", missing["error"]["message"])

    def test_request_size_limit_returns_413(self):
        with running_server(make_config(max_request_bytes=32)) as base_url:
            status, result = http_json(
                base_url, "/api/npc/decide", method="POST", body=VALID_REQUEST
            )
        self.assertEqual(status, 413)
        self.assertEqual(result["error"]["code"], "request_too_large")

    def test_upstream_timeout_is_reported_as_504(self):
        with mock.patch.object(server, "call_llm", side_effect=socket.timeout):
            with running_server(make_config(api_key="test-secret")) as base_url:
                status, result = http_json(
                    base_url, "/api/npc/decide", method="POST", body=VALID_REQUEST
                )
        self.assertEqual(status, 504)
        self.assertEqual(result["error"]["code"], "llm_timeout")
        self.assertTrue(result["retryable"])


class UpstreamParsingTests(unittest.TestCase):
    def test_chat_completion_is_parsed_and_standardized(self):
        completion = {
            "choices": [
                {
                    "message": {
                        "content": (
                            "```json\n"
                            '{"reply":"去雪山前带上火把。","action":"offer_torch",'
                            '"reason":"暴风雪将至","memory":"提醒玩家准备火把"}'
                            "\n```"
                        )
                    }
                }
            ]
        }

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, traceback):
                return False

            def read(self, _size=-1):
                return json.dumps(completion, ensure_ascii=False).encode("utf-8")

        config = make_config(api_key="test-secret", timeout=4.0)
        with mock.patch.object(
            server.urllib_request, "urlopen", return_value=FakeResponse()
        ) as mocked_urlopen:
            result = server.call_llm(config, VALID_REQUEST)

        self.assertEqual(
            result,
            {
                "reply": "去雪山前带上火把。",
                "action": "offer_torch",
                "reason": "暴风雪将至",
                "memory": "提醒玩家准备火把",
            },
        )
        request = mocked_urlopen.call_args.args[0]
        self.assertEqual(
            request.full_url, "https://llm.example.test/v1/chat/completions"
        )
        self.assertEqual(request.get_header("Authorization"), "Bearer test-secret")
        self.assertEqual(mocked_urlopen.call_args.kwargs["timeout"], 4.0)
        submitted = json.loads(request.data.decode("utf-8"))
        self.assertEqual(submitted["model"], "test-model")
        self.assertEqual(len(submitted["messages"]), 2)


if __name__ == "__main__":
    unittest.main()
