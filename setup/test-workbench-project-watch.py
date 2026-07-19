from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).parents[1] / "hypr" / "scripts" / "ai-workbench-project-watch.py"
SPEC = importlib.util.spec_from_file_location("ai_workbench_project_watch", MODULE_PATH)
assert SPEC and SPEC.loader
watch = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = watch
SPEC.loader.exec_module(watch)


class ProjectWatchTests(unittest.TestCase):
    def test_loads_only_valid_canonical_status_targets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache = root / "status.json"
            cache.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "status": {"project": {"id": "project-1", "path": str(root)}},
                    }
                ),
                encoding="utf-8",
            )
            target = watch.load_status_target(cache)
            self.assertEqual(target.project_id, "project-1")
            self.assertEqual(target.path, root)
            cache.write_text('{"schemaVersion":2}', encoding="utf-8")
            self.assertIsNone(watch.load_status_target(cache))

    def test_inotify_observes_nested_source_but_skips_dependency_trees(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "src"
            dependency = root / "node_modules" / "package"
            source.mkdir()
            dependency.mkdir(parents=True)
            with watch.InotifyTree(root, max_watches=32) as tree:
                self.assertGreaterEqual(tree.watch_count, 2)
                self.assertNotIn(dependency, tree.paths.values())
                changed_file = source / "feature.ts"
                changed_file.write_text("export const feature = true;\n", encoding="utf-8")
                events = tree.read_events(1.0)
                self.assertIn(changed_file, events)

    def test_refresh_is_project_scoped_and_requires_ok_envelope(self) -> None:
        target = watch.ProjectTarget("project/with space", Path("/tmp"))

        class Response:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return None

            def read(self, *_args):
                return b'{"status":"ok","data":{}}'

        with mock.patch.object(watch.urllib.request, "urlopen", return_value=Response()) as urlopen:
            self.assertTrue(watch.refresh_status("http://127.0.0.1:4318", target))
        request = urlopen.call_args.args[0]
        self.assertIn("projectId=project%2Fwith+space", request.full_url)
        self.assertEqual(urlopen.call_args.kwargs["timeout"], 10.0)

    def test_rejects_non_loopback_api_urls(self) -> None:
        self.assertTrue(watch.is_loopback_api_url("http://127.0.0.1:4417"))
        self.assertTrue(watch.is_loopback_api_url("http://[::1]:4417"))
        self.assertFalse(watch.is_loopback_api_url("https://example.com"))
        self.assertFalse(watch.is_loopback_api_url("file:///tmp/socket"))

    def test_runtime_default_uses_the_canonical_api_port(self) -> None:
        self.assertEqual(watch.DEFAULT_API_URL, "http://127.0.0.1:4417")


if __name__ == "__main__":
    unittest.main()
