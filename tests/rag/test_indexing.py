from __future__ import annotations

import copy
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.indexing import index_repo
from rag.retrieval import build_retrieval_plan, semantic_line_hits, symbol_hits
from rag.settings import DEFAULT_CONFIG
from rag.storage import ensure_db


class FakeVector(list):
    def tolist(self):
        return list(self)


class FakeEmbedder:
    def embed(self, texts):
        for index, text in enumerate(texts):
            yield FakeVector([float((len(text) + index) % 7), 0.5, 1.0])


class FakeClient:
    def __init__(self) -> None:
        self.upserts = []
        self.deletes = []

    def upsert(self, collection_name, points, wait=True):
        self.upserts.append((collection_name, len(points), wait))

    def delete(self, collection_name, points_selector, wait=True):
        self.deletes.append((collection_name, points_selector, wait))


class IndexingTest(unittest.TestCase):
    def make_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(":memory:")
        conn.row_factory = sqlite3.Row
        ensure_db(conn)
        return conn

    def test_index_repo_builds_symbol_dependency_and_package_indexes(self) -> None:
        conn = self.make_connection()
        config = copy.deepcopy(DEFAULT_CONFIG)
        profile = {"facts": True, "file_summaries": True, "repo_memory": False}

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo_name = root.name
            (root / "package.json").write_text(
                json.dumps({"name": "workspace-root", "workspaces": ["packages/*"]})
            )
            (root / "packages/app/src").mkdir(parents=True)
            (root / "packages/shared/src").mkdir(parents=True)
            (root / "packages/app/package.json").write_text(json.dumps({"name": "@acme/app"}))
            (root / "packages/shared/package.json").write_text(json.dumps({"name": "@acme/shared"}))
            (root / "packages/app/src/helper.ts").write_text("export const helper = () => 'ok'\n")
            (root / "packages/shared/src/index.ts").write_text("export const sharedThing = () => 1\n")
            (root / "packages/app/src/index.ts").write_text(
                "import { helper } from './helper'\n"
                "import { sharedThing } from '@acme/shared'\n\n"
                "export class AppService {\n"
                "  run() {\n"
                "    return helper() + String(sharedThing())\n"
                "  }\n"
                "}\n"
            )

            client = FakeClient()
            with patch("rag.indexing.ensure_collection"), patch("rag.indexing.get_embedder", return_value=FakeEmbedder()):
                changed_files, total_chunks = index_repo(conn, client, config, root, changed_only=False, profile=profile)

        self.assertGreaterEqual(changed_files, 5)
        self.assertGreater(total_chunks, 0)
        self.assertTrue(client.upserts)

        symbol_rows = conn.execute(
            "SELECT qualified_name, kind, parser FROM symbols WHERE repo = ? AND path = ? ORDER BY start_line",
            (repo_name, "packages/app/src/index.ts"),
        ).fetchall()
        qualified_names = {row["qualified_name"] for row in symbol_rows}
        self.assertIn("AppService", qualified_names)
        self.assertTrue(any(name.endswith("run") for name in qualified_names))
        self.assertTrue(all(row["parser"] in {"regex", "tree-sitter"} for row in symbol_rows))

        dependency_rows = conn.execute(
            "SELECT dependency, target_path, is_internal FROM file_dependencies WHERE repo = ? AND source_path = ? ORDER BY dependency",
            (repo_name, "packages/app/src/index.ts"),
        ).fetchall()
        dependency_map = {row["dependency"]: (row["target_path"], row["is_internal"]) for row in dependency_rows}
        self.assertEqual(dependency_map["./helper"], ("packages/app/src/helper.ts", 1))
        self.assertEqual(dependency_map["@acme/shared"], ("packages/shared", 1))

        semantic_rows = conn.execute(
            "SELECT symbol, content FROM semantic_lines WHERE repo = ? AND path = ? ORDER BY line_no",
            (repo_name, "packages/app/src/index.ts"),
        ).fetchall()
        self.assertTrue(any("helper" in row["content"] for row in semantic_rows))
        self.assertTrue(any((row["symbol"] or "").endswith("run") for row in semantic_rows))

        chunk_packages = conn.execute(
            "SELECT DISTINCT package FROM chunks WHERE repo = ? AND path = ?",
            (repo_name, "packages/app/src/index.ts"),
        ).fetchall()
        self.assertEqual({row[0] for row in chunk_packages}, {"@acme/app"})

        summary_row = conn.execute(
            "SELECT package, summary, dependencies FROM package_summaries WHERE repo = ? AND package = ?",
            (repo_name, "@acme/app"),
        ).fetchone()
        self.assertIsNotNone(summary_row)
        self.assertIn("indexed files", summary_row["summary"])
        self.assertIn("packages/shared", summary_row["dependencies"])

        plan = build_retrieval_plan("AppService run helper", repo_name, config=config, conn=conn)
        self.assertTrue(symbol_hits(conn, plan))
        self.assertTrue(semantic_line_hits(conn, config, plan))


if __name__ == "__main__":
    unittest.main()
