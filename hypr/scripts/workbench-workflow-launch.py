#!/usr/bin/env python3
"""Launch an API-authorized interactive Workbench workflow without a shell."""

from __future__ import annotations

import json
import os
import re
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any

SECRET_NAME = re.compile(r"^[A-Z_][A-Z0-9_]*$")
SAFE_AMBIENT_ENVIRONMENT = (
    "HOME",
    "USER",
    "LOGNAME",
    "SHELL",
    "PATH",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
    "TERM",
    "COLORTERM",
    "TMPDIR",
    "XDG_RUNTIME_DIR",
    "WAYLAND_DISPLAY",
    "DISPLAY",
    "DBUS_SESSION_BUS_ADDRESS",
    "SSH_AUTH_SOCK",
)
PROTECTED_ENVIRONMENT_NAMES = {
    "HOME",
    "LOGNAME",
    "PATH",
    "SHELL",
    "USER",
    "XDG_RUNTIME_DIR",
    "AI_WORKBENCH_API_URL",
    "AI_WORKBENCH_EXECUTION_ID",
    "AI_WORKBENCH_PROJECT_ID",
    "AI_WORKBENCH_SECRET_FILE",
    "AI_WORKBENCH_SESSION_ID",
    "AI_WORKBENCH_TASK_ID",
}


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
    environment_refs = launch.get("environmentRefs", [])
    if not isinstance(environment_refs, list) or not all(
        isinstance(name, str) and SECRET_NAME.fullmatch(name) for name in environment_refs
    ):
        raise RuntimeError("workflow launch secret references are invalid")
    if len(environment_refs) != len(set(environment_refs)):
        raise RuntimeError("workflow launch secret references contain duplicates")
    if any(name in PROTECTED_ENVIRONMENT_NAMES for name in environment_refs):
        raise RuntimeError("workflow launch cannot override protected environment")
    return launch, data["token"]


def resolve_secret_environment(names: list[str]) -> dict[str, str]:
    if not names:
        return {}
    configured = os.environ.get("AI_WORKBENCH_SECRET_FILE")
    if not configured:
        raise RuntimeError("approved secret provider is not configured")
    provider = Path(configured)
    if not provider.is_absolute():
        raise RuntimeError("approved secret provider path must be absolute")
    try:
        info = provider.lstat()
    except FileNotFoundError as error:
        raise RuntimeError("approved secret provider is unavailable") from error
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise RuntimeError("approved secret provider must be a regular file without symlinks")
    if provider.resolve(strict=True) != provider:
        raise RuntimeError("approved secret provider path must be canonical")
    if stat.S_IMODE(info.st_mode) & 0o077:
        raise RuntimeError("approved secret provider must have mode 0600 or stricter")
    if hasattr(os, "getuid") and info.st_uid != os.getuid():
        raise RuntimeError("approved secret provider must be owned by the Workbench user")
    if info.st_size > 1024 * 1024:
        raise RuntimeError("approved secret provider is too large")

    available: dict[str, str] = {}
    for index, raw_line in enumerate(provider.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        name, separator, value = line.partition("=")
        name = name.strip()
        if not separator or not SECRET_NAME.fullmatch(name):
            raise RuntimeError(f"secret provider contains an invalid entry at line {index}")
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        if "\0" in value:
            raise RuntimeError(f"secret provider contains an invalid value at line {index}")
        available[name] = value

    resolved: dict[str, str] = {}
    for name in names:
        if name not in available:
            raise RuntimeError(f"approved secret reference is unavailable: {name}")
        resolved[name] = available[name]
    return resolved


def child_environment(launch: dict[str, Any]) -> dict[str, str]:
    environment = {name: os.environ[name] for name in SAFE_AMBIENT_ENVIRONMENT if name in os.environ}
    environment.update(resolve_secret_environment(launch.get("environmentRefs", [])))
    # Canonical identifiers win over manifest-provided names.
    environment.update(launch["environment"])
    return environment


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
    environment = child_environment(launch)
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
