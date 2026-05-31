from __future__ import annotations

import asyncio
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from contextlib import contextmanager


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag import mcp_server
from rag.orchestrator import (
    learn_from_task_outcome,
    load_task_graph,
    mark_subtask_done,
    mark_subtask_failed,
    mark_subtask_running,
    next_subtask,
    plan_task,
    reset_task,
    subtask_context,
    task_graph_status,
    task_step,
)
from rag.profile import _looks_generated, learn_profile_from_run, profile_init, profile_validate
from rag.storage import ensure_db
from rag.task_graph import SubtaskStatus




@contextmanager
def _db_ctx(conn: sqlite3.Connection):
    yield conn

def make_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    ensure_db(conn)
    return conn


class TaskOrchestratorTest(unittest.TestCase):
    TASK = "Implement a runtime-structured task orchestrator for OpenCode with per-subtask context, outcome tracking, retry handling, and profile learning"

    def test_plan_task_writes_graph_and_ready_root_subtask(self) -> None:
        conn = make_connection()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            with patch("rag.orchestrator.repo_root", return_value=root), patch(
                "rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)
            ):
                graph = plan_task(self.TASK, max_subtasks=6)

            graph_path = root / ".agent" / "task-graph.json"
            self.assertTrue(graph_path.exists())
            payload = json.loads(graph_path.read_text())
            self.assertEqual(payload["task_id"], graph.task_id)
            self.assertGreaterEqual(len(payload["subtasks"]), 1)
            self.assertEqual(graph.subtasks[0].status.value, "ready")
            self.assertEqual(graph.subtasks[0].depends_on, [])

    def test_dependency_unblocks_next_subtask_after_done(self) -> None:
        conn = make_connection()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            with patch("rag.orchestrator.repo_root", return_value=root), patch(
                "rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)
            ):
                graph = plan_task(self.TASK, max_subtasks=6)
                updated = mark_subtask_done(
                    graph,
                    graph.subtasks[0].id,
                    retrieved_files=["system/rag/task_graph.py"],
                    edited_files=["system/rag/orchestrator.py"],
                    checks_run=["python -m unittest"],
                    passed=True,
                )
                self.assertEqual(updated.subtasks[0].status.value, "done")
                reloaded = load_task_graph(root)
                self.assertIsNotNone(reloaded)
                next_item = next_subtask(reloaded)
                self.assertIsNotNone(next_item)
                self.assertEqual(next_item.id, updated.subtasks[1].id)

    def test_subtask_context_exports_a_focused_run(self) -> None:
        conn = make_connection()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            with patch("rag.orchestrator.repo_root", return_value=root), patch(
                "rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)
            ):
                graph = plan_task(self.TASK, max_subtasks=6)

            stub = {
                "conn": conn,
                "repo": "dotfiles",
                "config": {"repo_profile": {}},
                "result": type("Result", (), {"rows": [], "summaries": [], "debug": {}, "facts": [], "context_sources": [], "memory": None})(),
                "context": "context",
                "files": ["system/rag/task_graph.py", "tests/rag/test_task_orchestrator.py"],
                "edit_scope": {"likely_edit": [{"path": "system/rag/task_graph.py", "reason": "top hit"}], "likely_tests": [], "read_only": [], "avoid": []},
                "missing_context": {"missing": ["test file"], "selected_files": ["system/rag/task_graph.py"]},
                "commands": ["python -m unittest"],
            }
            with patch("rag.orchestrator.repo_root", return_value=root), patch(
                "rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)
            ), patch("rag.orchestrator._build_retrieval_context", return_value=stub):
                payload = subtask_context(graph, graph.subtasks[0].id)

            self.assertIn("edit_scope", payload)
            self.assertIn("suggested_commands", payload)
            self.assertTrue((root / ".agent" / "rag-runs" / f"{payload['run_id']}.json").exists())
            self.assertEqual(graph.get_subtask(graph.subtasks[0].id).status.value, "running")
            self.assertGreaterEqual(graph.get_subtask(graph.subtasks[0].id).attempts, 1)

            with patch("rag.orchestrator.repo_root", return_value=root), patch(
                "rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)
            ), patch("rag.orchestrator._build_retrieval_context", return_value=stub):
                compact = subtask_context(graph, graph.subtasks[0].id, output_format="compact")
            self.assertNotIn("context", compact)

    def test_running_tool_can_be_called_explicitly(self) -> None:
        conn = make_connection()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            with patch("rag.orchestrator.repo_root", return_value=root), patch(
                "rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)
            ):
                graph = plan_task(self.TASK, max_subtasks=6)
                updated = mark_subtask_running(graph, graph.subtasks[0].id)
            self.assertEqual(updated.subtasks[0].status.value, "running")
            self.assertGreaterEqual(updated.subtasks[0].attempts, 1)

    def test_mark_subtask_done_rejects_passed_false(self) -> None:
        conn = make_connection()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            with patch("rag.orchestrator.repo_root", return_value=root), patch(
                "rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)
            ):
                graph = plan_task(self.TASK, max_subtasks=3)
                with self.assertRaisesRegex(ValueError, "passed=false should use rag_subtask_failed"):
                    mark_subtask_done(graph, graph.subtasks[0].id, passed=False)

    def test_failed_subtask_keeps_current_for_retry(self) -> None:
        conn = make_connection()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            with patch("rag.orchestrator.repo_root", return_value=root), patch(
                "rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)
            ):
                graph = plan_task(self.TASK, max_subtasks=3)
                updated = mark_subtask_failed(graph, graph.subtasks[0].id, notes="first fail")
                self.assertEqual(updated.current_subtask_id, graph.subtasks[0].id)
                retried = next_subtask(updated)
                self.assertIsNotNone(retried)
                self.assertEqual(retried.id, graph.subtasks[0].id)
                self.assertEqual(updated.get_subtask(graph.subtasks[0].id).status.value, "ready")

    def test_outcome_recording_redacts_and_appends_jsonl(self) -> None:
        conn = make_connection()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            with patch("rag.orchestrator.repo_root", return_value=root), patch(
                "rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)
            ):
                graph = plan_task("Fix auth flow with sk-live-secret", max_subtasks=4)
                mark_subtask_done(
                    graph,
                    graph.subtasks[0].id,
                    retrieved_files=["system/rag/task_graph.py"],
                    edited_files=["system/rag/orchestrator.py"],
                    checks_run=["pytest tests/rag"],
                    notes="Bearer sk-live-secret",
                )

            outcome_log = (root / ".agent" / "outcomes.jsonl").read_text()
            self.assertNotIn("sk-live-secret", outcome_log)
            row = conn.execute("SELECT notes FROM task_outcomes LIMIT 1").fetchone()
            self.assertIsNotNone(row)
            self.assertNotIn("sk-live-secret", row["notes"] or "")
            self.assertGreater(conn.execute("SELECT COUNT(*) AS c FROM eval_cases").fetchone()["c"], 0)

    def test_profile_learning_updates_repo_profile(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            path, profile = profile_init(root)
            self.assertTrue(path.exists())
            payload = {
                "run_id": "run-1",
                "task_id": "task-1",
                "task": "Fix auth flow",
                "repo": "dotfiles",
                "outcome": {
                    "edited_files": ["system/rag/cli.py"],
                    "retrieved_files": ["system/rag/cli.py"],
                    "missed_files": ["system/rag/mcp_server.py"],
                    "checks_run": ["pytest tests/rag/test_task_orchestrator.py"],
                    "passed": True,
                },
            }
            learned_path, learned = learn_profile_from_run(payload, root)
            self.assertEqual(learned_path, path)
            self.assertIn("system/rag/cli.py", learned["boost_paths"])
            self.assertIn("system/rag/mcp_server.py", learned["boost_paths"])
            self.assertIn("*.py", learned["learned_file_patterns"])
            self.assertIn("pytest tests/rag/test_task_orchestrator.py", learned["check_commands"])
            self.assertEqual(profile_validate(root), [])

    def test_mcp_tool_schemas_include_task_orchestrator_tools(self) -> None:
        tools = asyncio.run(mcp_server._list_tools())
        names = {tool.name for tool in tools}
        for name in {
            "rag_plan_task",
            "rag_next_subtask",
            "rag_subtask_context",
            "rag_subtask_running",
            "rag_subtask_done",
            "rag_subtask_failed",
            "rag_task_status",
            "rag_task_step",
            "rag_reflect_run",
            "rag_learn_from_outcome",
            "rag_search",
            "rag_deep",
        }:
            self.assertIn(name, names)

    def test_task_graph_status_returns_next_subtask_without_advancing(self) -> None:
        conn = make_connection()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            with patch("rag.orchestrator.repo_root", return_value=root), patch(
                "rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)
            ):
                graph = plan_task(self.TASK, max_subtasks=6)
                status = task_graph_status(graph)

            self.assertEqual(status["counts"]["done"], 0)
            self.assertIsNotNone(status["next_subtask"])
            self.assertEqual(graph.subtasks[0].status.value, "ready")

    def test_missing_dependency_blocks_subtask(self) -> None:
        conn = make_connection()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            with patch("rag.orchestrator.repo_root", return_value=root), patch(
                "rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)
            ):
                graph = plan_task(self.TASK, max_subtasks=6)
                graph.subtasks[1].depends_on = ["T999"]
                graph.subtasks[1].status = SubtaskStatus.ready
                status = task_graph_status(graph)
            blocked = graph.get_subtask("T2")
            self.assertEqual(blocked.status.value, "blocked")
            self.assertIn("missing dependencies", blocked.last_error or "")
            self.assertGreaterEqual(status["counts"]["blocked"], 1)

    def test_generated_path_detection_catches_relative_and_build_outputs(self) -> None:
        for path in [
            ".agent/task.md",
            ".rag/profile.json",
            "dist/foo.js",
            "build/foo.js",
            "coverage/index.html",
            "src/generated_client.py",
        ]:
            self.assertTrue(_looks_generated(path), path)

    def test_task_step_states(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            with patch("rag.orchestrator.repo_root", return_value=root):
                no_graph = task_step("something")
                self.assertEqual(no_graph["state"], "needs_plan")
            conn = make_connection()
            with patch("rag.orchestrator.repo_root", return_value=root), patch("rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)):
                graph = plan_task(self.TASK, max_subtasks=3)
                ready = task_step()
                self.assertEqual(ready["state"], "needs_context")
                mark_subtask_running(graph, graph.subtasks[0].id)
                running = task_step()
                self.assertEqual(running["state"], "ready_for_work")
                for subtask in graph.subtasks:
                    if subtask.status != SubtaskStatus.done:
                        if subtask.status != SubtaskStatus.running:
                            mark_subtask_running(graph, subtask.id)
                        mark_subtask_done(graph, subtask.id, retrieved_files=[], edited_files=[], checks_run=[], passed=True)
                complete = task_step()
                self.assertEqual(complete["state"], "complete")
            conn2 = make_connection()
            with patch("rag.orchestrator.repo_root", return_value=root), patch("rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn2)):
                graph = plan_task("retry exhaustion", max_subtasks=1)
                subtask_id = graph.subtasks[0].id
                mark_subtask_running(graph, subtask_id)
                failed = graph.get_subtask(subtask_id)
                failed.attempts = 3
                mark_subtask_failed(graph, subtask_id, notes="done retrying")
                step = task_step()
                self.assertEqual(step["state"], "failed")
                self.assertEqual(step["next_tool"], "rag_reflect_run")

    def test_reset_task_archives_files_and_preserves_memory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            agent = root / ".agent"
            agent.mkdir()
            (agent / "task-graph.json").write_text("{}\n")
            (agent / "task.md").write_text("task\n")
            (agent / "context.md").write_text("context\n")
            (agent / "handoff.md").write_text("handoff\n")
            (agent / "memory.md").write_text("keep\n")
            subtasks = agent / "subtasks"
            subtasks.mkdir()
            (subtasks / "T1.md").write_text("subtask\n")
            result = reset_task(root)
            self.assertTrue(result["ok"])
            self.assertFalse((agent / "task-graph.json").exists())
            self.assertFalse((agent / "task.md").exists())
            self.assertFalse((agent / "subtasks" / "T1.md").exists())
            self.assertTrue((agent / "memory.md").exists())

    def test_learning_scopes_to_run_id(self) -> None:
        conn = make_connection()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            with patch("rag.orchestrator.repo_root", return_value=root), patch("rag.orchestrator.db_conn", side_effect=lambda: _db_ctx(conn)):
                graph1 = plan_task("task one", max_subtasks=2)
                graph2 = plan_task("task two", max_subtasks=2)
                mark_subtask_done(graph1, graph1.subtasks[0].id, edited_files=["a.py"], retrieved_files=["a.py"], checks_run=["u"], passed=True)
                mark_subtask_done(graph2, graph2.subtasks[0].id, edited_files=["b.py"], retrieved_files=["b.py"], checks_run=["u"], passed=True)
                learned = learn_from_task_outcome(graph1.run_id, root)
                edited = [f for lesson in learned["task_lessons"] for f in lesson["edited_files"]]
                self.assertIn("a.py", edited)
                self.assertNotIn("b.py", edited)


if __name__ == "__main__":
    unittest.main()
