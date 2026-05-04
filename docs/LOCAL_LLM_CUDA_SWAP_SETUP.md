# Local LLM CUDA + llama-swap setup

## Install

```bash
cd ~/Documents/code/dotfiles
./setup/install-local-llm-stack.sh
```

If AUR prompts for sudo during install, allow it and finish the transaction.

## Required model files

The default model root is `~/llama-models` because this machine already keeps the local GGUF files there.

- `~/llama-models/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf` (primary `local` alias)
- optional: `~/llama-models/llama-3.2-3b-instruct.gguf`
- optional: `~/llama-models/mistral-7b-instruct.gguf`

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
- Model: `local` (alias to `qwen-coder`)

## OpenCode config

Template file:

- `configs/opencode/opencode.local-llamacpp.json`

Runtime path expected by OpenCode:

- `~/.config/opencode/opencode.json`

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
