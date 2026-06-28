# OpenCode Session Title

Generate exactly one concise OpenCode session title.

Rules:
- Output one line only.
- Use 5 to 50 characters.
- Describe the user's actual task in searchable words.
- Prefer `area: action` or `product task` phrasing when useful.
- Never output `New session`.
- Never include timestamps, dates, UUIDs, session ids, URLs, markdown, quotes,
  or tool names unless the tool itself is the subject.
- If the user message is empty, a greeting, or too vague, output
  `OpenCode check-in`.

Examples:
- `opencode config tuning`
- `noxcrm mobile search fix`
- `rag task router cleanup`
- `obsidian mcp repair`
