# Session Start

Apply this skill at the beginning of every new coding session before any file edits.

## On session start

1. Call `rag_status` to verify RAG is running.
2. Call `rag_task_step` first with the user's message as optional `task`.
3. Follow `rag_task_step.next_tool` strictly:
   - `rag_plan_task` when state is `needs_plan`
   - `rag_next_subtask` when state is `needs_next_subtask`
   - `rag_subtask_context` when state is `needs_context`
   - `rag_subtask_done` or `rag_subtask_failed` when state is `ready_for_work`
   - `rag_learn_from_outcome` when state is `complete`
   - `rag_reflect_run` when state is `failed`
4. Call `rag_agent_context` directly only for tiny/single-file tasks where task orchestration is unnecessary.
5. Read `rag://memory/project` to load durable project knowledge.
6. Read `rag://git/status` to see what has changed since the last session.

## During the session

- Use `rag_search` before opening any file you have not already read.
- Use `rag_deep` when you need architecture or cross-file reasoning.
- Prefer reading `.agent/memory.md` for repo-specific conventions over guessing.

## On session end

- If meaningful work was done, call `rag_reflect_run` and then `rag_learn_from_outcome`.
- Store only stable, verified facts with `rag_memory_add`; do not store guesses or temporary state.

## When not to use RAG

- For a single-file change you fully understand from reading it directly.
- For purely mechanical edits (renaming, formatting, whitespace).
- When the user explicitly says "just do it" and the scope is trivially small.
