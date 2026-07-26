# RAG Harness and MCP Setup

## Architecture overview
- The TypeScript AI Workbench is the canonical MCP and retrieval service.
- SQLite FTS is the default local retrieval fallback; Qdrant remains optional.
- llama-swap exposes the local OpenAI-compatible endpoint on `http://127.0.0.1:8080/v1`.
- MCP clients use Workbench, filesystem, git, local-docs, browser, Chrome DevTools, and optional Obsidian.

## Install steps
1. Ensure the TypeScript Workbench exists at `~/Documents/code/ai` and has its dependencies installed.
2. Run `setup/install-local-ai-stack.sh --install-runtime` for local AI links/config.
3. Run `setup/test-opencode-mcp.sh` to validate the Workbench stdio handshake and configured servers.

## MCP servers
Workbench is the canonical server. Python RAG is no longer required by OpenCode.
Local docs runs in its own `uv` environment and does not depend on the retired RAG venv.

## OpenCode integration
Use `configs/opencode/opencode.local-llamacpp.json` as the baseline. It points to
the Workbench MCP through `system/workbench-mcp.sh` and keeps filesystem/git project-scoped.

## Open WebUI integration
- Keep Workbench MCP as the canonical stdio server for OpenCode.
- Use `mcpo` as the HTTP bridge for Open WebUI. The compose stack mounts `~/Documents/code/dotfiles` and `~/ai-rag` into the bridge container and exposes the generated OpenAPI endpoint on host port `8088`.
- The web UI should consume the local inference endpoint separately from the RAG tool surface.
