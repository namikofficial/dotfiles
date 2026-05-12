from __future__ import annotations

import sqlite3
import sys
import unittest
from pathlib import Path


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.context_planner import build_context_plan
from rag.contracts import AgentPlan, ContextPlan
from rag.prompt_compiler import compile_prompt
from rag.router import build_agent_plan, classify_intent
from rag.storage import ensure_db


def make_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    ensure_db(conn)
    return conn


class V7ContractsTest(unittest.TestCase):
    def test_context_plan_defaults_scale_by_mode(self) -> None:
        quick = build_context_plan("quick")
        agent = build_context_plan("agent")
        self.assertFalse(quick.include_memory)
        self.assertTrue(agent.include_memory)
        self.assertGreater(agent.semantic_budget, quick.semantic_budget)

    def test_agent_plan_is_json_serializable_contract(self) -> None:
        conn = make_connection()
        plan = build_agent_plan("implement profile router in system/rag/router.py", conn=conn, repo="dotfiles")
        payload = plan.to_dict()
        self.assertEqual(payload["repo"], "dotfiles")
        self.assertEqual(payload["intent"], "implement")
        self.assertIn(payload["target"], {"codex", "opencode", "aider", "copy", "file", "local-answer"})
        self.assertIn("context", payload)
        self.assertIn("top_profiles", payload)

    def test_prompt_compiler_keeps_task_and_context(self) -> None:
        context = ContextPlan(True, False, False, False, True, True, 4, 4, 2, 2000)
        plan = AgentPlan(
            task="review retrieval stack",
            repo="dotfiles",
            session_id="s1",
            intent="review",
            mode="deep",
            profile="repo-review",
            target="local-answer",
            confidence=0.9,
            context=context,
            retrieval_semantic_limit=4,
            retrieval_keyword_limit=4,
            use_model_reranker=False,
            allow_shell=False,
            require_approval=True,
            sandbox="read-only",
            risk_level="low",
        )
        prompt = compile_prompt(plan, "<chunks>\nretrieval.py\n</chunks>")
        self.assertIn("review retrieval stack", prompt.user)
        self.assertIn("retrieval.py", prompt.user)
        self.assertGreater(prompt.token_count, 0)

    def test_intent_classifier_defaults_to_question_when_unclear(self) -> None:
        intent, confidence, reason = classify_intent("super alt s")
        self.assertEqual(intent, "question")
        self.assertLess(confidence, 0.7)
        self.assertIn("defaulted", reason)


if __name__ == "__main__":
    unittest.main()
