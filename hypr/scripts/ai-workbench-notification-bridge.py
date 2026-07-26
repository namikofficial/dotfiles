#!/usr/bin/env python3
"""Low-overhead Workbench SSE to desktop-notification bridge."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
NOTIFICATION_TYPES = {
    "approval.required",
    "run.completed",
    "run.failed",
    "check.failed",
    "index.completed",
    "task.blocked",
    "task.failed",
    "runtime.degraded",
    "workflow.launch_ready",
}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def log_event(
    event: str,
    severity: str = "info",
    *,
    source: dict[str, Any] | None = None,
    error_code: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> None:
    source = source or {}
    record = {
        "timestamp": now_iso(),
        "service": "ai-workbench-notification-bridge",
        "severity": severity,
        "event": event,
        "projectId": source.get("projectId"),
        "sessionId": source.get("sessionId"),
        "taskId": source.get("taskId"),
        "runId": source.get("runId"),
        "correlationId": source.get("correlationId"),
        "errorCode": error_code,
        "metadata": metadata or {},
    }
    print(json.dumps(record, separators=(",", ":")), flush=True)


def cache_path() -> Path:
    cache_root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    return cache_root / "ai-workbench" / "notification-bridge-v1.json"


def initial_state() -> dict[str, Any]:
    timestamp = now_iso()
    return {
        "schemaVersion": SCHEMA_VERSION,
        "cursor": timestamp,
        "connected": False,
        "lastConnectedAt": None,
        "lastEventAt": None,
        "lastNotificationAt": None,
        "lastError": None,
        "reconnects": 0,
        "updatedAt": timestamp,
    }


def load_state(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(value, dict) and value.get("schemaVersion") == SCHEMA_VERSION:
            return {**initial_state(), **value}
    except (OSError, json.JSONDecodeError):
        pass
    return initial_state()


def write_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    state["schemaVersion"] = SCHEMA_VERSION
    state["updatedAt"] = now_iso()
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    temporary.chmod(0o600)
    os.replace(temporary, path)


def dnd_enabled() -> bool:
    enabled = os.environ.get("AI_WORKBENCH_NOTIFICATIONS_ENABLED", "true").lower()
    if enabled in {"0", "false", "no", "off"}:
        return True
    try:
        result = subprocess.run(
            ["wayle", "notify", "status"],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False
    for line in result.stdout.splitlines():
        if "do not disturb" not in line.lower():
            continue
        value = line.split(":", 1)[-1].strip().lower()
        return value in {"on", "enabled", "true", "1", "yes"}
    return False


def should_notify(event: dict[str, Any]) -> bool:
    event_type = event.get("type")
    if event_type not in NOTIFICATION_TYPES:
        return False
    if event_type == "index.completed":
        payload = event.get("payload")
        return isinstance(payload, dict) and payload.get("manualRequest") is True
    return True


def event_link(event: dict[str, Any], web_url: str) -> str:
    payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
    event_type = str(event.get("type", ""))
    project_id = event.get("projectId")
    run_id = event.get("runId")
    task_id = event.get("taskId")
    if event_type == "approval.required" and isinstance(payload.get("approvalId"), str):
        path = f"/approvals/{urllib.parse.quote(payload['approvalId'], safe='')}"
    elif isinstance(run_id, str) and run_id:
        path = f"/runs/{urllib.parse.quote(run_id, safe='')}"
    elif event_type in {"task.blocked", "task.failed"} and isinstance(task_id, str):
        path = f"/tasks/{urllib.parse.quote(task_id, safe='')}"
    elif isinstance(project_id, str) and project_id:
        suffix = "/checks" if event_type == "check.failed" else ""
        path = f"/projects/{urllib.parse.quote(project_id, safe='')}{suffix}"
    else:
        path = "/events"
    return f"{web_url.rstrip('/')}{path}"


def notification_text(event: dict[str, Any]) -> tuple[str, str, str]:
    event_type = str(event.get("type", ""))
    titles = {
        "approval.required": "Approval requested",
        "run.completed": "Development run completed",
        "run.failed": "Development run failed",
        "check.failed": "Project check failed",
        "index.completed": "Project indexing completed",
        "task.blocked": "Task needs input",
        "task.failed": "Task failed",
        "runtime.degraded": "AI Workbench runtime degraded",
        "workflow.launch_ready": "Workflow ready to launch",
    }
    summary = event.get("summary")
    body = summary.strip() if isinstance(summary, str) and summary.strip() else event_type.replace(".", " ")
    severity = str(event.get("severity", "info"))
    urgency = "critical" if severity in {"error", "critical"} or event_type in {"run.failed", "check.failed"} else "normal"
    return titles.get(event_type, "AI Workbench"), body[:500], urgency


def open_link(url: str) -> None:
    try:
        subprocess.Popen(
            ["xdg-open", url],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except FileNotFoundError:
        log_event("notification.action_failed", "warning", error_code="xdg_open_missing")


def launch_workflow(execution_id: str) -> None:
    helper = Path(__file__).with_name("workbench-workflow-launch.py")
    try:
        subprocess.Popen(
            [str(helper), execution_id],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except (FileNotFoundError, PermissionError):
        log_event("notification.action_failed", "warning", error_code="workflow_launcher_missing")


def notification_action_args(event: dict[str, Any]) -> list[str]:
    if event.get("type") == "workflow.launch_ready":
        payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
        if isinstance(payload.get("executionId"), str):
            return ["--action=launch=Launch", "--action=open=Open"]
    return ["--action=open=Open"]


def send_notification(event: dict[str, Any], web_url: str) -> bool:
    if dnd_enabled():
        log_event("notification.suppressed", source=event, metadata={"reason": "dnd_or_disabled", "type": event.get("type")})
        return False
    title, body, urgency = notification_text(event)
    link = event_link(event, web_url)

    def worker() -> None:
        try:
            result = subprocess.run(
                [
                    "notify-send",
                    "--app-name=AI Workbench",
                    f"--urgency={urgency}",
                    *notification_action_args(event),
                    "--wait",
                    title,
                    body,
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=300,
            )
            if result.returncode != 0:
                subprocess.run(
                    ["notify-send", "--app-name=AI Workbench", f"--urgency={urgency}", title, body],
                    check=False,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=10,
                )
                return
            if result.stdout.strip() == "open":
                open_link(link)
            elif result.stdout.strip() == "launch":
                payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
                execution_id = payload.get("executionId")
                if isinstance(execution_id, str):
                    launch_workflow(execution_id)
        except FileNotFoundError:
            log_event("notification.failed", "warning", source=event, error_code="notify_send_missing")
        except subprocess.TimeoutExpired:
            pass

    threading.Thread(target=worker, daemon=True).start()
    return True


def parse_event(data: str) -> dict[str, Any] | None:
    try:
        event = json.loads(data)
    except json.JSONDecodeError:
        return None
    if not isinstance(event, dict) or not isinstance(event.get("id"), str) or not isinstance(event.get("type"), str):
        return None
    return event


def stream_events(api_url: str, state: dict[str, Any], state_file: Path, web_url: str) -> None:
    cursor = str(state.get("cursor") or now_iso())
    url = f"{api_url.rstrip('/')}/events/stream?{urllib.parse.urlencode({'since': cursor})}"
    request = urllib.request.Request(url, headers={"Accept": "text/event-stream"})
    with urllib.request.urlopen(request, timeout=60) as response:
        state.update({"connected": True, "lastConnectedAt": now_iso(), "lastError": None})
        write_state(state_file, state)
        log_event("event_stream.connected", metadata={"cursor": cursor})
        data_lines: list[str] = []
        for raw_line in response:
            line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
            if line.startswith("data:"):
                data_lines.append(line[5:].lstrip())
                continue
            if line != "" or not data_lines:
                continue
            event = parse_event("\n".join(data_lines))
            data_lines.clear()
            if event is None:
                log_event("event_stream.invalid_event", "warning", error_code="invalid_event")
                continue
            state["cursor"] = event["id"]
            state["lastEventAt"] = event.get("occurredAt") or event.get("ts") or now_iso()
            if should_notify(event) and send_notification(event, web_url):
                state["lastNotificationAt"] = now_iso()
                log_event("notification.sent", source=event, metadata={"type": event.get("type")})
            write_state(state_file, state)


def notify_runtime_unavailable(state: dict[str, Any], web_url: str) -> None:
    event = {
        "type": "runtime.degraded",
        "summary": "Workbench API is unavailable; cached project status remains read-only",
        "severity": "error",
        "projectId": None,
        "sessionId": None,
        "taskId": None,
        "runId": None,
        "correlationId": "runtime-offline",
        "payload": {},
    }
    if send_notification(event, web_url):
        state["lastNotificationAt"] = now_iso()


def main() -> int:
    api_url = os.environ.get("AI_WORKBENCH_API_URL", os.environ.get("AI_API_URL", "http://127.0.0.1:4417"))
    web_url = os.environ.get("AI_WORKBENCH_URL", "http://127.0.0.1:4317")
    state_file = cache_path()
    state = load_state(state_file)
    ever_connected = bool(state.get("lastConnectedAt"))
    offline_notified = False
    delay = 1
    while True:
        try:
            stream_events(api_url, state, state_file, web_url)
            ever_connected = True
            offline_notified = False
            delay = 1
        except (OSError, urllib.error.URLError, TimeoutError) as error:
            state["connected"] = False
            state["lastError"] = type(error).__name__
            state["reconnects"] = int(state.get("reconnects", 0)) + 1
            write_state(state_file, state)
            log_event(
                "event_stream.disconnected",
                "warning",
                error_code="workbench_unavailable",
                metadata={"retrySeconds": delay, "errorType": type(error).__name__},
            )
            ever_connected = ever_connected or bool(state.get("lastConnectedAt"))
            if ever_connected and not offline_notified:
                notify_runtime_unavailable(state, web_url)
                offline_notified = True
            time.sleep(delay)
            delay = min(delay * 2, 30)
        except KeyboardInterrupt:
            state["connected"] = False
            write_state(state_file, state)
            return 0


if __name__ == "__main__":
    sys.exit(main())
