# Local AI runtime quick start

## Default path

The active local AI workflow is:

- **router:** `llama-swap-manager`
- **endpoint:** `http://127.0.0.1:8080/v1`
- **model alias:** `local`
- **current model:** `qwen3-4b-local`

## 5-minute setup

### 1. Install the local stack

```bash
cd ~/Documents/code/dotfiles
./setup/install-local-llm-stack.sh
```

### 2. Download the current model

```bash
bash ~/Documents/code/dotfiles/system/model-download-setup.sh
```

Expected file:

```text
~/llama-models/google_gemma-3-4b-it-Q4_K_M.gguf
```

### 3. Start the local runtime when you need it

```bash
local-ai-runtime start
local-ai-runtime status
llama-swap-manager test
```

### 4. Use the AI tools

```bash
kage ai explain
kage ai commit-msg
kage ai review
```

Hyprland keys:

- `Super+Shift+E`
- `Super+Shift+C`
- `Super+Shift+R`

## Quick checks

```bash
local-ai-runtime status
curl -s http://127.0.0.1:8080/v1/models | jq .
tail -f ~/.cache/kage/llm-logs/llama-swap.log
```

## Notes

- `rag` and the local AI scripts now auto-start Qdrant / llama-swap when they need them.
- Use `local-ai-runtime stop` when you want the machine to cool back down.
- `llm-manager` is retired.
- Port `8000` is no longer the documented local AI path.
- If you want to switch away from `qwen3-8b`, use `llama-swap-manager switch <model>` or update `system/llama-swap/config.template.yaml` first.
