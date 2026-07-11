# Local LLM setup

Use llama.cpp and llama-swap directly. Ollama is not part of this workstation stack.

## Roles

| Role | Alias | Endpoint |
|---|---|---|
| Daily chat/coding | local / qwen3-4b-local | 127.0.0.1:8080 |
| Tool/MCP agent | granite-agent | 127.0.0.1:8080 |
| Text/code embeddings | nomic models | 127.0.0.1:8081 |
| Heavy coding experiment | qwen3-coder-heavy | 127.0.0.1:8080 |

Model root: /home/namik/llama-models. See LOCAL_LLM_CUDA_SWAP_SETUP.md for download commands.

## Commands

~~~bash
llama-swap-manager render-config
llama-swap-manager start
llama-swap-manager status
llama-swap-manager test
llama-swap-manager switch granite-agent
embedding-server-manager start
local-ai-runtime status
local-ai-runtime stop
~~~

The heavy coder is never the default on the 6GB RTX 4050.
