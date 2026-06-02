# RAG First

Use this skill for non-trivial coding tasks.

## Workflow

1. Call `rag_task_step` first.
2. Follow `recommended_call.tool` and `recommended_call.arguments` exactly.
3. Loop:
4. `rag_task_step`
5. if `needs_plan` -> `rag_plan_task`
6. if `needs_context` -> `rag_subtask_context`
7. if `ready_for_work` -> inspect/edit/check -> `rag_subtask_done` or `rag_subtask_failed`
8. if `complete` -> `rag_reflect_run` then `rag_learn_from_outcome`
9. if `failed` -> `rag_reflect_run` and stop
10. repeat

## Guardrails

- Do not claim checks passed unless command output confirms it.
- Never store secrets in notes.
- No out-of-scope edits without inspection-backed reason.
- Record `retrieved_files`, `edited_files`, `checks_run`, `passed`, and `notes` on every outcome.
- Prefer compact context by default and only request full context when needed.
- Prefer `must_inspect_first` and stay inside `edit_scope` unless file inspection proves otherwise.
