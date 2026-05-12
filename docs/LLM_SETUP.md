# Local LLM setup

The current local AI path is **llama-swap only**.

- router: `llama-swap-manager`
- endpoint: `http://127.0.0.1:8080/v1`
- default model alias: `local`
- current wired model: `gemma-3-4b`

## Install

```bash
cd ~/Documents/code/dotfiles
./setup/install-local-llm-stack.sh
```

## Download the model

```bash
bash ~/Documents/code/dotfiles/system/model-downloader.sh gemma-3-4b
# or
bash ~/Documents/code/dotfiles/system/model-download-setup.sh
```

Required file:

```text
~/llama-models/google_gemma-3-4b-it-Q4_K_M.gguf
```

## Start the local endpoint when needed

```bash
local-ai-runtime start
local-ai-runtime status
llama-swap-manager test
```

## Use it

```bash
kage ai explain
kage ai commit-msg
kage ai review
```

Hyprland keybinds:

- `Super+Shift+E` — explain clipboard text
- `Super+Shift+C` — generate commit message
- `Super+Shift+R` — review last commit

## Files

- `system/llama-swap-manager.sh` — local router manager
- `system/local-ai-runtime.sh` — start/stop/status helper for llama-swap + Qdrant
- `system/model-downloader.sh` — manual model instructions
- `system/model-download-setup.sh` — guided HuggingFace download helper
- `system/wayle-llm-module.sh` — Wayle LLM widget
- `system/llama-swap/config.template.yaml` — routed model config

## Troubleshooting

### Router will not start

```bash
llama-swap-manager status
llama-swap-manager logs
llama-server --list-devices
```

### AI features say local AI is offline

```bash
local-ai-runtime start
llama-swap-manager test
```

### Quick endpoint test

```bash
curl -s http://127.0.0.1:8080/v1/models | jq .
```

## Notes

- The local AI scripts can auto-start llama-swap on first use instead of assuming it is already running.
- Use `local-ai-runtime stop` when you want to unload the local runtime again.
- Old `llm-manager` / port-8000 guidance is retired.
- If you want another model, add it to `system/llama-swap/config.template.yaml` first instead of using an undocumented side path.
