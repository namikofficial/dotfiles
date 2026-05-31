# RAG First

Use this skill for any non-trivial code task.

## Before editing

1. Call the `rag` MCP server.
2. Use `rag_agent_context` with the user request before serious edits.
3. Inspect the suggested files directly and use the returned `edit_scope`.
4. Stay inside `edit_scope` unless direct file inspection proves another file is required.
5. If uncertainty remains, call `rag_missing_context` before wandering to unrelated files.

## While editing

- Follow existing project patterns — do not invent new ones.
- Do not rewrite unrelated code.
- Update tightly coupled docs and tests before closing the task.
- Use `rag_find_tests` and `rag_explain_file` when the next file or test target is unclear.

## After editing

1. Run the checks suggested by `rag_agent_context` or `rag_suggest_commands`.
2. Do not claim checks passed unless command output confirms it.
3. Call `rag_record_outcome` with retrieved files, edited files, checks run, and whether the task passed.
4. Store durable facts only when they reflect stable project knowledge — not temporary guesses.

## Do not use RAG to

- Dump huge context blindly without reading it.
- Replace direct file inspection when you already know the path.
- Write unrelated files.
- Store temporary working notes as permanent memory.
