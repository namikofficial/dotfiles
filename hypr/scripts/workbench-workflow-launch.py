#!/usr/bin/env python3
"""Launch an API-authorized interactive Workbench workflow without a shell."""

from __future__ import annotations

import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any


def api_url() -> str:
    value = os.environ.get("AI_WORKBENCH_API_URL", "http://127.0.0.1:4417").rstrip("/")
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise RuntimeError("workflow launcher requires a loopback Workbench API URL")
    return value


def request(path: str, payload: dict[str, Any]) -> Any:
    data = json.dumps(payload, separators=(",", ":")).encode()
    req = urllib.request.Request(
        f"{api_url()}{path}",
        data=data,
        method="POST",
        headers={"accept": "application/json", "content-type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            envelope = json.load(response)
    except urllib.error.HTTPError as error:
        try:
            envelope = json.load(error)
            message = envelope.get("error", {}).get("message", str(error))
        except Exception:
            message = str(error)
        raise RuntimeError(message) from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"Workbench API unavailable: {error.reason}") from error
    if envelope.get("status") != "ok":
        raise RuntimeError(envelope.get("error", {}).get("message", "Workbench API rejected launch"))
    return envelope.get("data")


def validate_launch(data: Any) -> tuple[dict[str, Any], str]:
    if not isinstance(data, dict) or not isinstance(data.get("launch"), dict) or not isinstance(data.get("token"), str):
        raise RuntimeError("Workbench returned an invalid launch capability")
    launch = data["launch"]
    command = launch.get("command")
    if launch.get("mode") not in {"terminal", "tmux"} or launch.get("state") != "ready":
        raise RuntimeError("workflow launch is not ready")
    if not isinstance(command, dict) or not isinstance(command.get("executable"), str):
        raise RuntimeError("workflow launch command is invalid")
    if not isinstance(command.get("arguments"), list) or not all(isinstance(arg, str) for arg in command["arguments"]):
        raise RuntimeError("workflow launch arguments are invalid")
    cwd = command.get("workingDirectory")
    if not isinstance(cwd, str) or not os.path.isabs(cwd) or not os.path.isdir(cwd) or os.path.realpath(cwd) != cwd:
        raise RuntimeError("workflow launch working directory is not canonical")
    environment = launch.get("environment")
    if not isinstance(environment, dict) or not all(
        isinstance(key, str) and isinstance(value, str) for key, value in environment.items()
    ):
        raise RuntimeError("workflow launch environment is invalid")
    return launch, data["token"]


def write_capability(execution_id: str, launch: dict[str, Any], token: str) -> str:
    runtime_root = Path(os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir())) / "ai-workbench-launches"
    runtime_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(runtime_root, 0o700)
    fd, path = tempfile.mkstemp(prefix="launch-", suffix=".json", dir=runtime_root)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(
                {"apiUrl": api_url(), "executionId": execution_id, "launch": launch, "token": token},
                handle,
                separators=(",", ":"),
            )
    except Exception:
        os.close(fd)
        Path(path).unlink(missing_ok=True)
        raise
    return path


def launch_desktop(execution_id: str) -> int:
    launch, token = validate_launch(request(f"/actions/executions/{urllib.parse.quote(execution_id)}/launch/authorize", {}))
    capability_path = write_capability(execution_id, launch, token)
    helper = str(Path(__file__).resolve())
    cwd = launch["command"]["workingDirectory"]
    title = f"workflow — {launch.get('projectId', 'project')}"
    try:
        if launch["mode"] == "terminal":
            subprocess.Popen(
                [
                    "kitty",
                    "--directory",
                    cwd,
                    "--class",
                    "ai-workbench-workflow",
                    "--title",
                    title,
                    "--",
                    sys.executable,
                    helper,
                    "--execute",
                    capability_path,
                ],
                start_new_session=True,
            )
        else:
            session = launch.get("tmuxSession")
            if not isinstance(session, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", session):
                raise RuntimeError("manifest tmux session is missing or unsafe")
            if subprocess.run(["tmux", "has-session", "-t", f"={session}"], check=False).returncode != 0:
                subprocess.run(["tmux", "new-session", "-d", "-s", session, "-c", cwd], check=True)
            subprocess.run(
                [
                    "tmux",
                    "new-window",
                    "-d",
                    "-t",
                    f"={session}",
                    "-c",
                    cwd,
                    sys.executable,
                    helper,
                    "--execute",
                    capability_path,
                ],
                check=True,
            )
    except Exception:
        Path(capability_path).unlink(missing_ok=True)
        raise
    return 0


def execute_capability(path: str) -> int:
    capability_path = Path(path)
    try:
        if capability_path.stat().st_mode & 0o077:
            raise RuntimeError("launch capability permissions are unsafe")
        data = json.loads(capability_path.read_text(encoding="utf-8"))
    finally:
        capability_path.unlink(missing_ok=True)
    os.environ["AI_WORKBENCH_API_URL"] = str(data["apiUrl"])
    launch, token = validate_launch({"launch": data.get("launch"), "token": data.get("token")})
    execution_id = str(data["executionId"])
    command = launch["command"]
    environment = os.environ.copy()
    environment.update(launch["environment"])
    child = subprocess.Popen(
        [command["executable"], *command["arguments"]],
        cwd=command["workingDirectory"],
        env=environment,
        start_new_session=True,
    )
    launcher_id = f"{socket.gethostname()}:{os.getpid()}:{uuid.uuid4()}"
    try:
        request(
            f"/actions/executions/{urllib.parse.quote(execution_id)}/launch/start",
            {"token": token, "launcherInstanceId": launcher_id, "pid": child.pid},
        )
    except Exception:
        os.killpg(child.pid, signal.SIGTERM)
        child.wait(timeout=5)
        raise
    cancelled = False
    try:
        exit_code = child.wait()
    except KeyboardInterrupt:
        cancelled = True
        os.killpg(child.pid, signal.SIGTERM)
        exit_code = child.wait()
    request(
        f"/actions/executions/{urllib.parse.quote(execution_id)}/launch/complete",
        {"token": token, "exitCode": exit_code, "cancelled": cancelled or exit_code in {-signal.SIGTERM, -signal.SIGKILL}},
    )
    return exit_code


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--execute":
        return execute_capability(sys.argv[2])
    if len(sys.argv) == 2 and sys.argv[1].strip():
        return launch_desktop(sys.argv[1].strip())
    print(f"usage: {Path(sys.argv[0]).name} <execution-id>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"workflow launch failed: {error}", file=sys.stderr)
        raise SystemExit(1)
