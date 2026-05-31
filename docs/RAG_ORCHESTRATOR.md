# RAG Orchestrator

The task orchestrator adds a lightweight runtime graph on top of the existing RAG retrieval flow.

## Files

- `.agent/task.md`: current task summary
- `.agent/task-graph.json`: serialized task graph
- `.agent/subtasks/<id>.md`: per-subtask brief
- `.agent/context.md`: active context note
- `.agent/handoff.md`: short agent handoff
- `.agent/rag-runs/<run-id>.json`: exported run trace
- `.agent/outcomes.jsonl`: append-only outcome log

## Flow

1. `rag_plan_task` creates a graph.
2. `rag_next_subtask` returns the next runnable unit.
3. `rag_subtask_context` builds narrow retrieval context.
4. The agent edits files and runs checks.
5. `rag_subtask_done` or `rag_subtask_failed` records the outcome.
6. `rag_reflect_run` summarizes the run.
7. `rag_learn_from_outcome` updates `.rag/profile.json` and repo memory.

## Rules

- Retry failed subtasks only.
- Keep stored data redacted.
- Keep the graph small and dependency-aware.

