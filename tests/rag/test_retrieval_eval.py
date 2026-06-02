from __future__ import annotations

import copy
import shutil
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.cli import route_mode
from rag.indexing import index_repo
from rag.retrieval import gather_context, retrieve
from rag.settings import DEFAULT_CONFIG
from rag.state import add_error, add_test_failure
from rag.storage import ensure_db


FIXTURE_ROOT = Path(__file__).resolve().parents[1] / "fixtures" / "rag_repo"


class FakeVector(list):
    def tolist(self):
        return list(self)


class FakeEmbedder:
    def embed(self, texts):
        for index, text in enumerate(texts):
            yield FakeVector([float((len(text) + index) % 11), 0.25, 1.0])


class FakeResponse:
    def __init__(self, points):
        self.points = points


class FakeClient:
    def __init__(self) -> None:
        self.upserts = []
        self.deletes = []

    def upsert(self, collection_name, points, wait=True):
        self.upserts.append((collection_name, len(points), wait))

    def delete(self, collection_name, points_selector, wait=True):
        self.deletes.append((collection_name, points_selector, wait))

    def query_points(self, collection_name, query, query_filter, limit, with_payload=True):
        return FakeResponse([])


def make_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    ensure_db(conn)
    return conn


class RetrievalEvalTest(unittest.TestCase):
    def setUp(self) -> None:
        self.conn = make_connection()
        self.client = FakeClient()
        self.config = copy.deepcopy(DEFAULT_CONFIG)
        self.profile = {"facts": True, "file_summaries": True, "repo_memory": False}
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name) / "rag-repo"
        shutil.copytree(FIXTURE_ROOT, self.root)
        self.repo = self.root.name
        with patch("rag.indexing.ensure_collection"), patch("rag.indexing.get_embedder", return_value=FakeEmbedder()):
            index_repo(
                self.conn,
                self.client,
                self.config,
                self.root,
                changed_only=False,
                profile=self.profile,
            )

    def tearDown(self) -> None:
        self.conn.close()
        self.tempdir.cleanup()

    def _retrieve(self, query: str, *, mode: str = "deep"):
        with patch("rag.retrieval.get_embedder", return_value=FakeEmbedder()):
            return retrieve(
                self.conn,
                self.client,
                self.config,
                query,
                self.repo,
                use_reranker=True,
                mode=mode,
            )

    def test_auth_symbol_query_returns_service_and_caller(self) -> None:
        result = self._retrieve("AuthService.login", mode="deep")
        paths = {row["path"] for row in result.rows}
        self.assertIn("src/auth_service.ts", paths)
        self.assertIn("src/auth_routes.ts", paths)

    def test_docker_postgres_query_returns_compose_and_env(self) -> None:
        result = self._retrieve("where is docker postgres configured env file", mode="deep")
        paths = {row["path"] for row in result.rows}
        self.assertIn("infra/docker-compose.yml", paths)
        self.assertIn("infra/postgres-config.toml", paths)

    def test_keybind_query_includes_binding_and_script_target(self) -> None:
        result = self._retrieve("Super Alt S", mode="deep")
        paths = {row["path"] for row in result.rows}
        self.assertIn("hypr/hyprland.lua", paths)
        context, _files = gather_context(result.rows, self.config, facts=result.facts, summaries=result.summaries)
        self.assertIn("super-alt-s.sh", context)

    def test_error_query_surfaces_error_and_test_failure_context(self) -> None:
        add_test_failure(
            self.conn,
            self.repo,
            "pytest tests/auth/test_login.py",
            "OperationalError: database is locked\n at tests/auth/test_login.py:10",
            runner="pytest",
            exit_code=1,
        )
        add_error(
            self.conn,
            self.repo,
            "sqlite3.OperationalError: database is locked",
            fix_text="close stale transaction and retry",
            command="pytest tests/auth/test_login.py",
            exit_code=1,
        )
        result = self._retrieve("database is locked", mode="deep")
        source_types = {item.source_type for item in result.context_sources}
        self.assertIn("error", source_types)
        self.assertIn("test_failure", source_types)

    def test_agent_handoff_query_prefers_cli_file_over_unrelated_docs(self) -> None:
        mode, _reason = route_mode("prepare codex handoff for RAG CLI")
        self.assertEqual(mode, "agent")
        result = self._retrieve("prepare codex handoff for RAG CLI cli.py", mode="agent")
        self.assertTrue(result.rows)
        top_paths = {row["path"] for row in result.rows[:4]}
        self.assertIn("system/rag/cli.py", top_paths)
        self.assertNotIn("docs/unrelated.md", top_paths)


if __name__ == "__main__":
    unittest.main()
