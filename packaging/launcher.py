"""One-click Windows launcher for the packaged Blindspot Relay build."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


APP_TITLE = "Blindspot Relay"
DEFAULT_RELAY_PORT = 8787
STARTUP_TIMEOUT_SECONDS = 30.0


def _hide_console_window() -> None:
    if os.name != "nt":
        return
    try:
        import ctypes

        console = ctypes.windll.kernel32.GetConsoleWindow()
        if console:
            ctypes.windll.user32.ShowWindow(console, 0)
    except Exception:
        pass


def _bundle_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[1]


def _show_message(message: str, *, error: bool = False) -> None:
    try:
        import ctypes

        icon = 0x10 if error else 0x30
        ctypes.windll.user32.MessageBoxW(None, message, APP_TITLE, icon)
    except Exception:
        # This fallback is primarily useful when running launcher.py directly.
        print(message, file=sys.stderr if error else sys.stdout)


def _relay_port() -> int:
    try:
        value = int(os.getenv("BLINDSPOT_RELAY_PORT", str(DEFAULT_RELAY_PORT)))
    except ValueError:
        return DEFAULT_RELAY_PORT
    return value if 1 <= value <= 65535 else DEFAULT_RELAY_PORT


def _relay_health(port: int, timeout: float = 0.8) -> dict[str, object] | None:
    try:
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}/health", headers={"Accept": "application/json"}
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (OSError, ValueError, urllib.error.URLError):
        return None
    if not isinstance(payload, dict) or payload.get("service") != "blindspot-relay":
        return None
    return payload


def _log_file() -> Path:
    base = Path(os.getenv("LOCALAPPDATA") or tempfile.gettempdir())
    log_dir = base / "BlindspotRelay" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    path = log_dir / "relay.log"
    if path.is_file() and path.stat().st_size > 2 * 1024 * 1024:
        rotated = log_dir / "relay.previous.log"
        rotated.unlink(missing_ok=True)
        path.replace(rotated)
    return path


def _start_relay(runtime_dir: Path, port: int) -> tuple[subprocess.Popen[bytes] | None, dict[str, object] | None]:
    existing = _relay_health(port)
    if existing is not None:
        return None, existing

    relay_exe = runtime_dir / "BlindspotRelayServer.exe"
    if not relay_exe.is_file():
        return None, None

    log_handle = _log_file().open("ab", buffering=0)
    creation_flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    try:
        process = subprocess.Popen(
            [str(relay_exe), "--host", "127.0.0.1", "--port", str(port)],
            cwd=str(runtime_dir),
            stdin=subprocess.DEVNULL,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            creationflags=creation_flags,
        )
    except OSError:
        log_handle.close()
        return None, None
    finally:
        # Popen owns a duplicate of this handle after successful process creation.
        log_handle.close()

    deadline = time.monotonic() + STARTUP_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if process.poll() is not None:
            return process, None
        health = _relay_health(port)
        if health is not None:
            return process, health
        time.sleep(0.2)
    return process, None


def _stop_owned_process(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
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
        process.wait(timeout=4.0)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2.0)


def main() -> int:
    _hide_console_window()
    bundle_dir = _bundle_dir()
    runtime_dir = bundle_dir / "_runtime"
    game_exe = runtime_dir / "BlindspotGame.exe"
    game_pack = runtime_dir / "BlindspotGame.pck"
    if not game_exe.is_file() or not game_pack.is_file():
        _show_message("游戏文件不完整，请重新解压整个压缩包后再启动。", error=True)
        return 2

    relay_process, health = _start_relay(runtime_dir, _relay_port())
    if health is None:
        _show_message(
            "在线 AI 服务未能启动，游戏仍会以完整的本地 NPC 模式运行。\n\n"
            "诊断日志位于：%LOCALAPPDATA%\\BlindspotRelay\\logs\\relay.log"
        )
    elif not bool(health.get("configured", False)):
        _show_message(
            "发行包未配置在线模型凭据，游戏将使用完整的本地 NPC 模式。"
        )

    try:
        game_args = [str(game_exe), "--main-pack", str(game_pack)]
        smoke_iterations = os.getenv("BLINDSPOT_SMOKE_QUIT_AFTER", "").strip()
        if smoke_iterations.isdigit():
            game_args.extend(["--headless", "--quit-after", smoke_iterations])
        game_process = subprocess.Popen(
            game_args, cwd=str(runtime_dir)
        )
        return int(game_process.wait())
    except OSError as exc:
        _show_message(f"游戏启动失败：{exc}", error=True)
        return 3
    finally:
        _stop_owned_process(relay_process)


if __name__ == "__main__":
    raise SystemExit(main())
