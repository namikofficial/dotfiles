# Local LLM Setup

## Quick start
1. Run `setup/install-local-ai-stack.sh --install-runtime --doctor`.
2. Start the router with `llama-swap-manager start`.
3. Check the endpoint with `curl http://127.0.0.1:8080/v1/models`.
4. Switch models with `llama-swap-manager switch <model>` when needed.

## Model roles
| Model | Alias | Role | Default ctx |
| --- | --- | --- | --- |
| Qwen3 8B | `local`, `qwen3` | Primary chat/code/RAG | 32768 |
| Qwen2.5 Coder 7B | `qwen-coder-7b` | Coding sessions | 32768 |
| Gemma 3 4B | `gemma-3-4b` | Fast fallback | 32768 |
| Phi-4 Mini | `phi-4-mini` | Compact reasoning | 16384 |
| DeepSeek R1 Distill Qwen 7B | `deepseek-r1` | Debugging/reasoning | 32768 |
| Llama 3.2 3B | `llama3b` | Small fallback | 65536 |
| Qwen3 4B | `qwen3-4b` | Fast chat | 65536 |
| Qwen3 1.7B | `router` | Routing/query rewrite | 65536 |

## llama-swap usage
- Status: `llama-swap-manager status`
- Start: `llama-swap-manager start`
- Stop: `llama-swap-manager stop`
- Logs: `llama-swap-manager logs`
- Test chat: `llama-swap-manager test`

## Switching models
- Primary alias: `local` → `qwen3-8b`
- Coding model: `qwen-coder-7b`
- Fast fallback: `gemma-3-4b`
- Example: `llama-swap-manager switch qwen-coder-7b`

## OOM recovery
1. Stop the router: `llama-swap-manager stop`
2. Switch to `gemma-3-4b`, `qwen3-4b`, or `llama3b`
3. Reduce concurrent work and retry
4. Lower context size before restarting if needed

## Context window guide
- 7B/8B Q4_K_M models: `32768`
- 3B/4B models: `65536`
- 1.7B router models: `65536`
- Embedding/reranker models: `8192`
