#!/usr/bin/env python3

import importlib.util
import json
import os
import stat
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "hypr/scripts/ai-workbench-notification-bridge.py"
SPEC = importlib.util.spec_from_file_location("workbench_notification_bridge", SCRIPT)
assert SPEC and SPEC.loader
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class NotificationBridgeTests(unittest.TestCase):
    def test_filters_only_meaningful_events(self):
        self.assertTrue(bridge.should_notify({"type": "approval.required", "payload": {}}))
        self.assertTrue(
            bridge.should_notify({"type": "index.completed", "payload": {"manualRequest": True}})
        )
        self.assertFalse(
            bridge.should_notify({"type": "index.completed", "payload": {"manualRequest": False}})
        )
        self.assertFalse(bridge.should_notify({"type": "desktop.observed", "payload": {}}))

    def test_deep_links_use_canonical_workbench_routes(self):
        approval = {
            "type": "approval.required",
            "payload": {"approvalId": "approval one"},
            "runId": "run-1",
        }
        self.assertEqual(
            bridge.event_link(approval, "http://127.0.0.1:4317/"),
            "http://127.0.0.1:4317/approvals/approval%20one",
        )
        failed_check = {
            "type": "check.failed",
            "payload": {},
            "projectId": "project one",
        }
        self.assertEqual(
            bridge.event_link(failed_check, "http://127.0.0.1:4317"),
            "http://127.0.0.1:4317/projects/project%20one/checks",
        )

    def test_state_cache_is_versioned_atomic_and_private(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bridge.json"
            state = bridge.initial_state()
            state["cursor"] = "evt_1"
            bridge.write_state(path, state)
            loaded = bridge.load_state(path)
            self.assertEqual(loaded["schemaVersion"], 1)
            self.assertEqual(loaded["cursor"], "evt_1")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(json.loads(path.read_text())["connected"], False)

    def test_legacy_or_malformed_sse_payloads_do_not_crash(self):
        self.assertIsNone(bridge.parse_event("not json"))
        self.assertIsNone(bridge.parse_event('{"type":"run.failed"}'))
        parsed = bridge.parse_event('{"id":"evt_1","type":"run.failed"}')
        self.assertEqual(parsed["id"], "evt_1")

    def test_dnd_and_explicit_disable_are_respected(self):
        with mock.patch.dict(os.environ, {"AI_WORKBENCH_NOTIFICATIONS_ENABLED": "false"}):
            self.assertTrue(bridge.dnd_enabled())
        status = SimpleNamespace(stdout="Do Not Disturb: enabled\n", returncode=0)
        with mock.patch.dict(os.environ, {"AI_WORKBENCH_NOTIFICATIONS_ENABLED": "true"}):
            with mock.patch.object(bridge.subprocess, "run", return_value=status):
                self.assertTrue(bridge.dnd_enabled())


if __name__ == "__main__":
    unittest.main()
