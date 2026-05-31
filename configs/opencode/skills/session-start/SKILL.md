# Session Start

Apply this skill at the beginning of every new coding session before any file edits.

## On session start

1. Call `rag_status` to verify RAG is running.
2. Call `rag_agent_context` with the user's first message as `task`.
3. Read the `rag://task/current` resource — if a task exists and is not stale (< 24 h old), continue it.
4. If no task exists or the user is starting something new, call `rag_task_init` with the user's request.
5. Read `rag://memory/project` to load durable project knowledge.
6. Read `rag://git/status` to see what has changed since the last session.

## During the session

- Use `rag_search` before opening any file you have not already read.
- Use `rag_deep` when you need architecture or cross-file reasoning.
- Prefer reading `.agent/memory.md` for repo-specific conventions over guessing.

## On session end

- If meaningful work was done, call `rag_task_done` with a one-paragraph summary.
- Store only stable, verified facts with `rag_memory_add`; do not store guesses or temporary state.

## When not to use RAG

- For a single-file change you fully understand from reading it directly.
- For purely mechanical edits (renaming, formatting, whitespace).
- When the user explicitly says "just do it" and the scope is trivially small.
