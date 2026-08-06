"""Validate a Blindspot Relay ZIP from an isolated extraction directory."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request
import zipfile


def _request_json(url: str, *, body: dict[str, object] | None = None, timeout: float = 2.0) -> dict[str, object]:
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json; charset=utf-8"
    request = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError(f"Expected a JSON object from {url}")
    return payload


def _wait_for_health(port: int, timeout: float = 30.0) -> dict[str, object]:
    deadline = time.monotonic() + timeout
    url = f"http://127.0.0.1:{port}/health"
    while time.monotonic() < deadline:
        try:
            health = _request_json(url, timeout=1.0)
            if health.get("service") == "blindspot-relay":
                return health
        except (OSError, ValueError, urllib.error.URLError):
            time.sleep(0.2)
    raise RuntimeError(f"Relay did not become healthy on port {port}")


def _safe_extract(zip_path: Path, target: Path) -> None:
    target_resolved = target.resolve()
    with zipfile.ZipFile(zip_path) as archive:
        for member in archive.infolist():
            destination = (target / member.filename).resolve()
            if not destination.is_relative_to(target_resolved):
                raise RuntimeError(f"Unsafe ZIP member: {member.filename}")
        archive.extractall(target)


def _verify_hashes(root: Path) -> int:
    failures = 0
    hash_file = root / "SHA256SUMS.txt"
    for raw_line in hash_file.read_text(encoding="utf-8").splitlines():
        expected, relative = raw_line.split(" *", 1)
        path = root / Path(relative)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != expected:
            failures += 1
    return failures


def _online_dialogue_smoke(port: int) -> dict[str, object]:
    payload: dict[str, object] = {
        "player_text": "你还好吗？",
        "state": {
            "room_id": "relay_control",
            "oxygen": 88,
            "power": 61,
            "physical_state": "左肩受伤，呼吸急促",
        },
        "visible_observations": [
            "你在中继控制室",
            "逃生舱指示灯仍是红色",
        ],
        "valid_actions": [
            {"action": "wait", "target": "", "label": "等待"},
        ],
        "history": [],
    }
    result = _request_json(
        f"http://127.0.0.1:{port}/api/npc/decide",
        body=payload,
        timeout=90.0,
    )
    decision = result.get("decision", {})
    if not isinstance(decision, dict):
        raise RuntimeError("Online response did not contain a decision")
    if result.get("provider") != "openai" or not str(decision.get("reply", "")).strip():
        raise RuntimeError("Online AI dialogue smoke test did not return an OpenAI reply")
    return {
        "provider": result.get("provider"),
        "model": result.get("model"),
        "intent": decision.get("intent"),
        "action": decision.get("action"),
        "reply_length": len(str(decision.get("reply", ""))),
    }


def _stop_process_tree(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(process.pid), "/T", "/F"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            timeout=8.0,
            check=False,
        )
        try:
            process.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            pass
        return
    process.terminate()
    try:
        process.wait(timeout=5.0)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2.0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("zip_path", type=Path)
    args = parser.parse_args()

    zip_path = args.zip_path.resolve()
    project_root = Path(__file__).resolve().parents[1]
    smoke_root = project_root / "build" / "package_smoke" / time.strftime("%Y%m%d_%H%M%S")
    smoke_root.mkdir(parents=True, exist_ok=False)
    _safe_extract(zip_path, smoke_root)

    hash_failures = _verify_hashes(smoke_root)
    if hash_failures:
        raise RuntimeError(f"Release hash failures: {hash_failures}")

    runtime_dir = smoke_root / "_runtime"
    relay = runtime_dir / "BlindspotRelayServer.exe"
    launcher = smoke_root / "BlindspotRelay.exe"
    safe_check = subprocess.run(
        [str(relay), "--check"],
        cwd=runtime_dir,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=30.0,
    )
    check_payload = json.loads(safe_check.stdout.strip())
    if not check_payload.get("configured"):
        raise RuntimeError("Packaged relay has no provider configuration")

    port = 18787
    log_path = smoke_root / "relay-smoke.log"
    creation_flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    with log_path.open("wb") as log_handle:
        relay_process = subprocess.Popen(
            [str(relay), "--host", "127.0.0.1", "--port", str(port)],
            cwd=runtime_dir,
            stdin=subprocess.DEVNULL,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            creationflags=creation_flags,
        )
    try:
        health = _wait_for_health(port)
        online = _online_dialogue_smoke(port)
    finally:
        _stop_process_tree(relay_process)

    try:
        _request_json(f"http://127.0.0.1:{port}/health", timeout=0.5)
    except (OSError, ValueError, urllib.error.URLError):
        relay_cleaned = True
    else:
        relay_cleaned = False
    if not relay_cleaned:
        raise RuntimeError("Packaged relay was not cleaned up after the test")

    launcher_environment = os.environ.copy()
    launcher_environment["BLINDSPOT_SMOKE_QUIT_AFTER"] = "180"
    launcher_relay_port = 18788
    launcher_environment["BLINDSPOT_RELAY_PORT"] = str(launcher_relay_port)
    launcher_result = subprocess.run(
        [str(launcher)],
        cwd=smoke_root,
        env=launcher_environment,
        timeout=60.0,
    )
    if launcher_result.returncode != 0:
        raise RuntimeError(f"One-click launcher exited with {launcher_result.returncode}")
    try:
        _request_json(f"http://127.0.0.1:{launcher_relay_port}/health", timeout=0.5)
    except (OSError, ValueError, urllib.error.URLError):
        launcher_relay_cleaned = True
    else:
        launcher_relay_cleaned = False
    if not launcher_relay_cleaned:
        raise RuntimeError("One-click launcher left its AI relay running")

    summary = {
        "smoke_root": str(smoke_root),
        "hash_failures": hash_failures,
        "relay_configured": health.get("configured"),
        "relay_model": health.get("model"),
        "online": online,
        "relay_cleaned": relay_cleaned,
        "launcher_exit_code": launcher_result.returncode,
        "launcher_relay_cleaned": launcher_relay_cleaned,
        "zip_size": zip_path.stat().st_size,
        "zip_sha256": hashlib.sha256(zip_path.read_bytes()).hexdigest(),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
