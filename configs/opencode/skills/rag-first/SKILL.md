# RAG First

Use this skill for any non-trivial code task.

## Before editing

1. Call the `rag` MCP server.
2. Use `rag_agent_context` with the user request.
3. Read `.agent/memory.md` if present.
4. Inspect the files suggested by RAG before touching anything.
5. Make minimal, patch-sized edits.

## While editing

- Follow existing project patterns — do not invent new ones.
- Do not rewrite unrelated code.
- Update tightly coupled docs and tests before closing the task.

## After editing

1. Run the checks in `.agent/checks.md` if present, otherwise run `bash setup/check-shell.sh` for shell files.
2. Fix any failures before reporting done.
3. Update `.agent/task.md` or `.agent/handoff.md` if present.
4. Store durable facts with `rag_memory_add` only when they reflect stable project knowledge — not temporary guesses.

## Do not use RAG to

- Dump huge context blindly without reading it.
- Replace direct file inspection when you already know the path.
- Write unrelated files.
- Store temporary working notes as permanent memory.
