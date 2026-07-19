#!/usr/bin/env python3
"""Coalesce active-project filesystem events into canonical Workbench status refreshes."""

from __future__ import annotations

import ctypes
import errno
import json
import os
import select
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

IN_ATTRIB = 0x00000004
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800
IN_IGNORED = 0x00008000
IN_ISDIR = 0x40000000
WATCH_MASK = (
    IN_ATTRIB
    | IN_CLOSE_WRITE
    | IN_MOVED_FROM
    | IN_MOVED_TO
    | IN_CREATE
    | IN_DELETE
    | IN_DELETE_SELF
    | IN_MOVE_SELF
)
EVENT_HEADER = struct.Struct("iIII")
EXCLUDED_DIRECTORIES = {
    ".cache",
    ".gradle",
    ".next",
    ".nox",
    ".pytest_cache",
    ".tox",
    ".venv",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "node_modules",
    "objects",
    "site-packages",
    "target",
    "vendor",
}
DEFAULT_API_URL = "http://127.0.0.1:4417"


@dataclass(frozen=True)
class ProjectTarget:
    project_id: str
    path: Path


def log_event(event: str, severity: str = "info", **metadata: object) -> None:
    print(
        json.dumps(
            {
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "service": "ai-workbench-project-watch",
                "severity": severity,
                "event": event,
                "metadata": metadata,
            },
            separators=(",", ":"),
        ),
        file=sys.stderr,
        flush=True,
    )


def load_status_target(cache_path: Path) -> ProjectTarget | None:
    try:
        payload = json.loads(cache_path.read_text(encoding="utf-8"))
        if payload.get("schemaVersion") != 1:
            return None
        project = payload.get("status", {}).get("project", {})
        project_id = project.get("id")
        raw_path = project.get("path")
        if not isinstance(project_id, str) or not project_id or not isinstance(raw_path, str):
            return None
        path = Path(raw_path)
        resolved = path.resolve(strict=True)
        if not path.is_absolute() or path.is_symlink() or resolved != path or not path.is_dir():
            return None
        return ProjectTarget(project_id=project_id, path=path)
    except (OSError, ValueError, TypeError):
        return None


def should_descend(path: Path) -> bool:
    if path.name in EXCLUDED_DIRECTORIES:
        return False
    if path.parent.name == ".git" and path.name in {"logs", "modules", "worktrees"}:
        return False
    return True


class InotifyTree:
    def __init__(self, root: Path, max_watches: int = 4096) -> None:
        self.root = root
        self.max_watches = max(1, max_watches)
        self._libc = ctypes.CDLL(None, use_errno=True)
        self._libc.inotify_init1.argtypes = [ctypes.c_int]
        self._libc.inotify_init1.restype = ctypes.c_int
        self._libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        self._libc.inotify_add_watch.restype = ctypes.c_int
        self.fd = self._libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self.fd < 0:
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error))
        self.paths: dict[int, Path] = {}
        self.truncated = False
        self.add_tree(root)

    @property
    def watch_count(self) -> int:
        return len(self.paths)

    def close(self) -> None:
        if self.fd >= 0:
            os.close(self.fd)
            self.fd = -1
        self.paths.clear()

    def __enter__(self) -> InotifyTree:
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()

    def add_directory(self, path: Path) -> bool:
        if len(self.paths) >= self.max_watches:
            self.truncated = True
            return False
        try:
            if path.is_symlink() or not path.is_dir() or not should_descend(path):
                return False
            wd = self._libc.inotify_add_watch(self.fd, os.fsencode(path), WATCH_MASK)
            if wd < 0:
                error = ctypes.get_errno()
                if error in {errno.EACCES, errno.ENOENT, errno.ENOSPC}:
                    self.truncated = self.truncated or error == errno.ENOSPC
                    return False
                raise OSError(error, os.strerror(error), path)
            self.paths[wd] = path
            return True
        except OSError:
            return False

    def add_tree(self, root: Path) -> None:
        for current, directories, _files in os.walk(root, followlinks=False):
            current_path = Path(current)
            directories[:] = [
                name
                for name in directories
                if should_descend(current_path / name) and not (current_path / name).is_symlink()
            ]
            if not self.add_directory(current_path) and self.truncated:
                directories.clear()
                return

    def read_events(self, timeout: float) -> list[Path]:
        if self.fd < 0:
            return []
        readable, _writable, _errors = select.select([self.fd], [], [], max(0.0, timeout))
        if not readable:
            return []
        try:
            data = os.read(self.fd, 1024 * 1024)
        except BlockingIOError:
            return []
        changed: list[Path] = []
        offset = 0
        while offset + EVENT_HEADER.size <= len(data):
            wd, mask, _cookie, name_length = EVENT_HEADER.unpack_from(data, offset)
            offset += EVENT_HEADER.size
            raw_name = data[offset : offset + name_length].split(b"\0", 1)[0]
            offset += name_length
            parent = self.paths.get(wd)
            if parent is None:
                continue
            path = parent / os.fsdecode(raw_name) if raw_name else parent
            if mask & IN_IGNORED:
                self.paths.pop(wd, None)
                continue
            if mask & IN_ISDIR and mask & (IN_CREATE | IN_MOVED_TO):
                self.add_tree(path)
            if should_descend(path):
                changed.append(path)
        return changed


def refresh_status(api_url: str, target: ProjectTarget, timeout: float = 10.0) -> bool:
    query = urllib.parse.urlencode({"projectId": target.project_id})
    request = urllib.request.Request(
        f"{api_url.rstrip('/')}/project-status/compact?{query}",
        headers={"Accept": "application/json", "User-Agent": "ai-workbench-project-watch/1"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310 - loopback URL is configured
            payload: Any = json.load(response)
        return isinstance(payload, dict) and payload.get("status") == "ok"
    except (OSError, ValueError, urllib.error.URLError):
        return False


def is_loopback_api_url(api_url: str) -> bool:
    try:
        parsed = urllib.parse.urlparse(api_url)
        return parsed.scheme == "http" and parsed.hostname in {"127.0.0.1", "localhost", "::1"}
    except ValueError:
        return False


def read_events_or_wait(watcher: InotifyTree | None, timeout: float) -> list[Path]:
    if watcher is not None:
        return watcher.read_events(timeout)
    time.sleep(max(0.0, timeout))
    return []


def run() -> int:
    cache_root = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
    cache_path = Path(
        os.environ.get(
            "AI_WORKBENCH_STATUS_CACHE",
            str(cache_root / "ai-workbench" / "project-status-v1.json"),
        )
    )
    api_url = os.environ.get(
        "AI_WORKBENCH_API_URL",
        os.environ.get("AI_API_URL", DEFAULT_API_URL),
    )
    if not is_loopback_api_url(api_url):
        log_event("configuration.invalid", "error", errorCode="non_loopback_api_url")
        return 2
    debounce = max(0.05, float(os.environ.get("AI_WORKBENCH_PROJECT_WATCH_DEBOUNCE_MS", "350")) / 1000)
    max_watches = max(32, int(os.environ.get("AI_WORKBENCH_PROJECT_WATCH_MAX_DIRECTORIES", "4096")))
    target: ProjectTarget | None = None
    watcher: InotifyTree | None = None
    refresh_at: float | None = None
    try:
        while True:
            observed = load_status_target(cache_path)
            if observed != target:
                if watcher is not None:
                    watcher.close()
                    watcher = None
                target = observed
                refresh_at = None
                if target is not None:
                    watcher = InotifyTree(target.path, max_watches=max_watches)
                    log_event(
                        "project_watch.configured",
                        projectId=target.project_id,
                        directories=watcher.watch_count,
                        truncated=watcher.truncated,
                    )
            timeout = 1.0
            if refresh_at is not None:
                timeout = min(timeout, max(0.0, refresh_at - time.monotonic()))
            events = read_events_or_wait(watcher, timeout)
            if events:
                refresh_at = time.monotonic() + debounce
            if refresh_at is not None and time.monotonic() >= refresh_at and target is not None:
                ok = refresh_status(api_url, target)
                log_event(
                    "project_status.refresh_requested" if ok else "project_status.refresh_failed",
                    "info" if ok else "warning",
                    projectId=target.project_id,
                    coalesced=True,
                )
                refresh_at = None
    except KeyboardInterrupt:
        return 0
    finally:
        if watcher is not None:
            watcher.close()


if __name__ == "__main__":
    raise SystemExit(run())
