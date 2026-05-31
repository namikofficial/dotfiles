# RAG First

Use this skill for non-trivial coding tasks.

## Workflow

1. Call `rag_plan_task` for broad tasks.
2. Never solve a broad task as one giant prompt.
3. Call `rag_next_subtask` and work only on the returned subtask.
4. Call `rag_subtask_context` before editing files for that subtask.
5. Inspect the suggested files directly.
6. Stay inside the returned edit scope unless inspection proves otherwise.
7. Run the suggested checks for the current subtask.
8. Call `rag_subtask_done` or `rag_subtask_failed` after each subtask.
9. Repeat until `rag_task_status` reports completion.
10. Call `rag_reflect_run` and `rag_learn_from_outcome` at the end.

## Guardrails

- Do not claim checks passed unless command output confirms it.
- Do not widen the edit scope without inspecting the code that justifies it.
- Keep failed retries local to the failing subtask.
- Treat `.agent/task-graph.json` as the source of truth for the current run.

