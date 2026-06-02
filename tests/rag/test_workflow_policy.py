from __future__ import annotations

import sys
import unittest
from pathlib import Path


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.workflow_policy import workflow_policy_for_task


class WorkflowPolicyTest(unittest.TestCase):
    def test_tiny_task_prefers_single_step(self) -> None:
        policy = workflow_policy_for_task("fix typo in README", runtime={"qdrant_ready": True, "llm_ready": True})
        self.assertFalse(policy.use_task_graph)
        self.assertEqual(policy.max_subtasks, 1)
        self.assertEqual(policy.retrieval_mode, "quick")

    def test_large_task_expands_subtasks(self) -> None:
        policy = workflow_policy_for_task(
            "perform a large refactor across architecture layers and multiple modules with migration planning and validation",
            runtime={"qdrant_ready": True, "llm_ready": True},
        )
        self.assertTrue(policy.use_task_graph)
        self.assertEqual(policy.max_subtasks, 8)
        self.assertIn("large_task_detected", policy.reasons)

    def test_runtime_unavailable_skips_context_collection(self) -> None:
        policy = workflow_policy_for_task(
            "implement authentication bug fix with integration tests and full regression validation in backend services",
            runtime={"qdrant_ready": False, "llm_ready": False},
        )
        self.assertFalse(policy.collect_context_now)
        self.assertIn("qdrant_not_ready", policy.reasons)
        self.assertIn("llm_not_ready", policy.reasons)


if __name__ == "__main__":
    unittest.main()
