#!/usr/bin/env python3

import importlib.util
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "hypr/scripts/workbench-workflow-launch.py"
SPEC = importlib.util.spec_from_file_location("workbench_workflow_launch", SCRIPT)
assert SPEC and SPEC.loader
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)


def launch_payload(mode="terminal"):
    return {
        "launch": {
            "executionId": "execution-1",
            "projectId": "project-1",
            "mode": mode,
            "state": "ready",
            "command": {"executable": "git", "arguments": ["--version"], "workingDirectory": "/tmp"},
            "environment": {"AI_WORKBENCH_PROJECT_ID": "project-1"},
            "tmuxSession": "project-session" if mode == "tmux" else None,
        },
        "token": "secret-launch-token",
    }


class WorkflowLauncherTests(unittest.TestCase):
    def test_terminal_launch_uses_structured_kitty_arguments_and_private_capability(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.dict(
                os.environ,
                {"XDG_RUNTIME_DIR": directory, "AI_WORKBENCH_API_URL": "http://127.0.0.1:4417"},
                clear=False,
            ):
                with mock.patch.object(launcher, "request", return_value=launch_payload()):
                    with mock.patch.object(launcher.subprocess, "Popen") as popen:
                        self.assertEqual(launcher.launch_desktop("execution-1"), 0)
            argv = popen.call_args.args[0]
            self.assertEqual(argv[0], "kitty")
            self.assertIn("--execute", argv)
            self.assertNotIn("sh", argv)
            capability = Path(argv[-1])
            self.assertEqual(stat.S_IMODE(capability.stat().st_mode), 0o600)
            self.assertEqual(json.loads(capability.read_text())["token"], "secret-launch-token")
            capability.unlink()

    def test_tmux_launch_uses_manifest_session_without_shell_interpolation(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.dict(
                os.environ,
                {"XDG_RUNTIME_DIR": directory, "AI_WORKBENCH_API_URL": "http://127.0.0.1:4417"},
                clear=False,
            ):
                with mock.patch.object(launcher, "request", return_value=launch_payload("tmux")):
                    with mock.patch.object(
                        launcher.subprocess, "run", side_effect=[SimpleNamespace(returncode=0), SimpleNamespace(returncode=0)]
                    ) as run:
                        launcher.launch_desktop("execution-1")
            new_window = run.call_args_list[1].args[0]
            self.assertEqual(new_window[:6], ["tmux", "new-window", "-d", "-t", "=project-session", "-c"])
            self.assertIn("--execute", new_window)
            Path(new_window[-1]).unlink()

    def test_execute_reports_start_and_completion_with_canonical_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            capability = Path(directory) / "capability.json"
            capability.write_text(
                json.dumps(
                    {
                        "apiUrl": "http://127.0.0.1:4417",
                        "executionId": "execution-1",
                        **launch_payload(),
                    }
                )
            )
            capability.chmod(0o600)
            child = SimpleNamespace(pid=12345, wait=mock.Mock(return_value=0))
            with mock.patch.object(launcher.subprocess, "Popen", return_value=child) as popen:
                with mock.patch.object(launcher, "request", return_value={}) as request:
                    self.assertEqual(launcher.execute_capability(str(capability)), 0)
            self.assertFalse(capability.exists())
            self.assertEqual(popen.call_args.args[0], ["git", "--version"])
            self.assertEqual(popen.call_args.kwargs["env"]["AI_WORKBENCH_PROJECT_ID"], "project-1")
            self.assertEqual(request.call_args_list[0].args[1]["pid"], 12345)
            self.assertEqual(request.call_args_list[1].args[1]["exitCode"], 0)


if __name__ == "__main__":
    unittest.main()
