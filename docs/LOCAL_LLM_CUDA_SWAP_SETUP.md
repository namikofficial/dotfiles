# Local LLM CUDA + llama-swap setup

## Install

```bash
cd ~/Documents/code/dotfiles
./setup/install-local-llm-stack.sh
```

If AUR prompts for sudo during install, allow it and finish the transaction.

## Required model files

The default model root is `~/llama-models` because this machine already keeps the local GGUF files there.

Required:

- `~/llama-models/qwen2.5-coder-7b-instruct-q4_k_m.gguf` (primary `local` alias)

Optional fallback:

- `~/llama-models/google_gemma-3-4b-it-Q4_K_M.gguf`

Override with `LLAMA_MODEL_ROOT=/path/to/models` if needed.

## Start router

```bash
llama-swap-manager start
llama-swap-manager status
llama-swap-manager test
```

Endpoint for all tools:

- Base URL: `http://127.0.0.1:8080/v1`
- API Key: `local`
- Model: `local` (alias to `qwen3-8b`)
- Alternate model names: `qwen3`, `qwen3-8b`
- Fallback model: `gemma-3-4b`

## OpenCode config

Template file:

- `configs/opencode/opencode.local-llamacpp.json`

Runtime path expected by OpenCode:

- `~/.config/opencode/opencode.json`

The install script links that runtime file back to `configs/opencode/opencode.local-llamacpp.json`.

Current runtime behavior:

- the AI scratchpad opens a project-rooted shell and checks the local runtime on demand
- from that shell, run `opencode` when you want to start the local AI agent
- the runtime config now also carries OpenCode MCP setup, extra skill paths, and local plugins
- if the runtime cannot come up, the scratchpad falls back to the local chat helper
- enabled MCP servers: `chrome-devtools`, `browser`, `context7`
- `obsidian` is configured but left disabled by default until the local REST bridge is healthy

Open WebUI:
- install with `./setup/install-open-webui-stack.sh`
- start with `docker compose --env-file .env up -d` from `~/.config/open-webui`
- point it at `http://127.0.0.1:8080/v1`
- keep `rag-mcp` attached to OpenCode; do not replace that path with the browser UI

OpenCode docs used:

- providers: <https://opencode.ai/docs/providers/>
- config: <https://opencode.ai/docs/config/>

## Codex CLI config

Template file:

- `configs/codex/config.local-llamacpp.toml`

Runtime path:

- `~/.codex/config.toml`

Codex docs used:

- config reference: <https://developers.openai.com/codex/config-reference>

Important: Codex custom providers currently support only `wire_api = "responses"`. If your local server/proxy does not support `/v1/responses`, Codex local-provider mode will not work reliably.

## GPU verification

```bash
llama-server --list-devices
nvidia-smi
```

`llama-swap-manager start` fails fast when CUDA/NVIDIA is not detected in `llama-server --list-devices`.
