# RAG Harness and MCP Setup

## Architecture overview
- `rag` CLI wraps the local RAG stack.
- Qdrant handles vector search; SQLite stores local metadata/state.
- llama-swap exposes the local OpenAI-compatible endpoint on `http://127.0.0.1:8080/v1`.
- MCP clients can talk to filesystem, git, sqlite, context7, and rag; postgres, browser, qdrant, and obsidian stay optional.

## Install steps
1. Run `setup/install-local-rag-stack.sh` for the Python/Qdrant stack.
2. Run `setup/install-local-ai-stack.sh --install-runtime` for local AI links/config.
3. Copy an MCP example from `ai/mcp/` into your client config and replace placeholders.

## rag CLI reference
- `rag doctor`
- `rag quick <query>`
- `rag deep <query>`
- `rag index <path>`
- `rag search <query>`

## MCP servers
Start with `filesystem`, `git`, `sqlite`, `context7`, and `rag`. Enable `postgres`, `browser`, `qdrant`, or `obsidian` only when the local path or credentials are ready.

## OpenCode integration
Use `ai/mcp/opencode-mcp.example.json` as the baseline OpenCode config. Keep local RAG enabled and point filesystem/git at the active workspace.
