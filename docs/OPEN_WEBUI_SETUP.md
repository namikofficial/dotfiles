# Open WebUI Setup

## Purpose
Use Open WebUI as the browser workspace for comparing models, testing prompts, and exploring local backends.

Keep these responsibilities separate:
- `llama-swap` / `local-ai-runtime`: stable local model endpoint
- `rag-mcp`: canonical RAG and handoff surface for OpenCode
- Open WebUI: interactive browser UI for model experimentation
- `mcpo`: HTTP bridge that exposes the same RAG surface to Open WebUI as OpenAPI

## Install

```bash
cd ~/Documents/code/dotfiles
./setup/install-open-webui-stack.sh
```

This prepares:
- `~/.config/open-webui/compose.yml`
- `~/.config/open-webui/.env`

Edit `~/.config/open-webui/.env` and replace the placeholder secret before starting the service.

## Start

```bash
cd ~/.config/open-webui
docker compose --env-file .env up -d --build
```

## Local backend

Default backend:
- host: `http://127.0.0.1:8080/v1`
- from Open WebUI container: `http://host.docker.internal:8080/v1`

This is the same llama-swap endpoint already used by the rest of the local AI stack.

## RAG in the web UI

Keep `rag-mcp` as the OpenCode-native MCP server.

The compose stack now runs `mcpo` as `rag-mcpo` on port `8000`, mounting the repo and `~/ai-rag` into the container.
The compose stack now runs `mcpo` as `rag-mcpo` on host port `8088`, mounting the repo and `~/ai-rag` into the container. The bridge image installs the RAG Python dependencies inside the container and runs `/usr/local/bin/python -m rag.mcp_server`, so it does not depend on the host venv layout.

In Open WebUI, add a tool:
- Type: OpenAPI
- URL from your browser: `http://127.0.0.1:8088/openapi.json`
- URL from inside Docker: `http://rag-mcpo:8000/openapi.json`
- Auth: use the shared `MCPO_API_KEY` from `~/.config/open-webui/.env`

That exposes the same RAG surface without changing the OpenCode path or the underlying `rag-mcp` stdio server.

The Open WebUI UI itself is published on `http://127.0.0.1:3080`. The RAG bridge root URL returns `{"detail":"Not Found"}` by design; use `/docs` or `/openapi.json`.

## Verify

```bash
cd ~/Documents/code/dotfiles
./setup/test-open-webui-stack.sh
```

## Recommended operating split

- OpenCode: repository work, handoffs, tool use, RAG-driven agent workflows
- Open WebUI: prompt/model comparison, ad hoc chat, local model experimentation
- llama-swap: model routing and stable local inference
