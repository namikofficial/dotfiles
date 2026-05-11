from __future__ import annotations

import copy
import sqlite3
import sys
import unittest
from pathlib import Path


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.cli import render_handoff
from rag.retrieval import ContextSource, approx_tokens, gather_context
from rag.settings import DEFAULT_CONFIG, get_mode_profile
from rag.storage import ensure_db


def make_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    ensure_db(conn)
    return conn


def seed_rows(conn: sqlite3.Connection) -> tuple[list[sqlite3.Row], list[sqlite3.Row], list[sqlite3.Row]]:
    config = copy.deepcopy(DEFAULT_CONFIG)
    conn.execute(
        """
        INSERT INTO chunks (
            chunk_id, repo, root, path, language, kind, symbol, modified_at,
            file_hash, index_schema, embedding_model, chunker, chunk_index,
            start_line, end_line, content
        ) VALUES
            ('c1', 'dotfiles', '/repo/dotfiles', 'src/auth_service.ts', 'typescript', 'code', 'AuthService.login', 1.0, 'h1', 'rag-v5', ?, 'semantic-lines-v5', 0, 1, 20, 'export class AuthService { login() {} }'),
            ('c2', 'dotfiles', '/repo/dotfiles', 'src/auth_routes.ts', 'typescript', 'code', 'loginRoute', 1.0, 'h2', 'rag-v5', ?, 'semantic-lines-v5', 0, 1, 20, 'import { AuthService } from \"./auth_service\";')
        """,
        (config["embedding_model"], config["embedding_model"]),
    )
    conn.execute(
        """
        INSERT INTO facts (fact_id, repo, path, kind, key, value, line, confidence, source, file_hash, updated_at) VALUES
            ('f1', 'dotfiles', 'src/auth_service.ts', 'service', 'AuthService', 'login', 1, 1.0, 'extractor', 'h1', 1.0)
        """
    )
    conn.execute(
        """
        INSERT INTO file_summaries (
            repo, path, package, file_hash, language, kind, summary, symbols, facts_count, updated_at
        ) VALUES
            ('dotfiles', 'src/auth_service.ts', NULL, 'h1', 'typescript', 'code', 'Auth service implementation', 'AuthService.login', 1, 1.0)
        """
    )
    conn.commit()
    rows = conn.execute("SELECT * FROM chunks ORDER BY chunk_id").fetchall()
    facts = conn.execute("SELECT * FROM facts ORDER BY fact_id").fetchall()
    summaries = conn.execute("SELECT * FROM file_summaries ORDER BY path").fetchall()
    return rows, facts, summaries


class ContextPackingTest(unittest.TestCase):
    def test_quick_mode_prefers_facts_then_chunks_without_memory_sections(self) -> None:
        conn = make_connection()
        rows, facts, summaries = seed_rows(conn)
        config = get_mode_profile(DEFAULT_CONFIG, "quick")
        context, _files = gather_context(rows, config, facts=facts, summaries=summaries)
        self.assertIn("<facts>", context)
        self.assertIn("<chunks>", context)
        self.assertNotIn("<repo_memory>", context)
        self.assertNotIn("<operational_state>", context)
        self.assertLess(context.index("<facts>"), context.index("<chunks>"))
        self.assertLessEqual(approx_tokens(context), config["context_budget"]["total_tokens"])
        conn.close()

    def test_deep_mode_places_active_state_before_repo_memory(self) -> None:
        conn = make_connection()
        rows, facts, summaries = seed_rows(conn)
        config = get_mode_profile(DEFAULT_CONFIG, "deep")
        context_sources = [
            ContextSource(
                source_type="git",
                title="branch feature/auth",
                content="dirty files: src/auth_service.ts",
                file_refs=("dotfiles/src/auth_service.ts",),
            )
        ]
        context, _files = gather_context(
            rows,
            config,
            facts=facts,
            summaries=summaries,
            context_sources=context_sources,
            memory="Repo memory summary",
            operational_state="## Test failures\n- database is locked",
            operational_state_tokens=600,
        )
        self.assertLess(context.index("<operational_state>"), context.index("<context_sources>"))
        self.assertLess(context.index("<context_sources>"), context.index("<facts>"))
        self.assertLess(context.index("<facts>"), context.index("<repo_memory>"))
        self.assertLess(context.index("<repo_memory>"), context.index("<chunks>"))
        conn.close()

    def test_agent_handoff_includes_important_files_and_missing_context_checklist(self) -> None:
        handoff = render_handoff(
            "prepare codex handoff for RAG CLI",
            "dotfiles",
            "matched long-running implementation or handoff language",
            "<chunks>\ncontent\n</chunks>",
            ["dotfiles/system/rag/cli.py:1-40", "dotfiles/system/rag/retrieval.py:1-80"],
            "## Todos\n- tighten doctor checks",
            target_agent="codex",
            missing_context=["caller file", "config file"],
        )
        self.assertIn("## Important files", handoff)
        self.assertIn("dotfiles/system/rag/cli.py:1-40", handoff)
        self.assertIn("## Missing context checklist", handoff)
        self.assertIn("caller / route entry file", handoff)
        self.assertIn("config or env file", handoff)


if __name__ == "__main__":
    unittest.main()
