# Local GGUF runtime: llama.cpp + llama-swap

Ollama is intentionally not used. GGUF files live under:

~~~text
/home/namik/llama-models/
├── chat/qwen3-4b-instruct-2507/
├── chat/granite-4-h-tiny/
├── coder/qwen3-coder-30b-a3b/       # optional; not a 6GB default
├── embed/nomic-embed-text-v2-moe/
└── embed/nomic-embed-code/
~~~

## Install binaries

~~~bash
cd /home/namik/Documents/code/dotfiles
./setup/bootstrap.sh --install-packages --with-aur
./setup/install-local-llm-stack.sh
~~~

This installs CUDA-enabled llama.cpp, llama-swap, OpenCode links, the chat manager, and the embedding manager. It does not install Ollama.

## Download models

~~~bash
mkdir -p /home/namik/llama-models/{chat,coder,embed}
uv tool install "huggingface_hub[cli]" 2>/dev/null || pipx install "huggingface_hub[cli]"
hf auth login

hf download unsloth/Qwen3-4B-Instruct-2507-GGUF --include "*UD-Q4_K_XL*" --local-dir /home/namik/llama-models/chat/qwen3-4b-instruct-2507

hf download ibm-granite/granite-4.0-h-tiny-GGUF --include "*Q4_K_M*" --local-dir /home/namik/llama-models/chat/granite-4-h-tiny

hf download nomic-ai/nomic-embed-text-v2-moe-GGUF --include "*Q4_K_M*" --local-dir /home/namik/llama-models/embed/nomic-embed-text-v2-moe

hf download nomic-ai/nomic-embed-code-GGUF --include "nomic-embed-code.Q4_K_S.gguf" --local-dir /home/namik/llama-models/embed/nomic-embed-code
~~~

Optional heavy model:

~~~bash
hf download unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF +  --include "*UD-Q4_K_XL*" +  --local-dir /home/namik/llama-models/coder/qwen3-coder-30b-a3b
~~~

Verify files:

~~~bash
find /home/namik/llama-models -type f -name '*.gguf' -print
find /home/namik/llama-models -type f -name '*.gguf' -size +0c -exec sh -c +  'head -c 4 "$1" | grep -q GGUF || echo "invalid GGUF: $1"' sh {} \;
~~~

## Start services

~~~bash
llama-swap-manager render-config
llama-swap-manager start
llama-swap-manager status
llama-swap-manager test
embedding-server-manager start
embedding-server-manager status
~~~

Endpoints:

- Chat/agent router: http://127.0.0.1:8080/v1
- Text embeddings: http://127.0.0.1:8081/v1
- Default alias: local -> qwen3-4b-local
- Agent alias: granite-agent
- Optional heavy alias: qwen3-coder-heavy

The main router loads one chat model at a time. Embeddings run separately with llama.cpp --embeddings.

## Switch models

~~~bash
llama-swap-manager switch local
llama-swap-manager switch granite-agent
llama-swap-manager switch qwen3-coder-heavy
~~~

Do not use the heavy coder as the default on a 6GB RTX 4050.

## Stop and diagnose

~~~bash
local-ai-runtime status
local-ai-runtime stop
llama-swap-manager logs
embedding-server-manager logs
llama-server --list-devices
nvidia-smi
~~~

If the main model is missing, render-config fails with the exact directory expected. Optional models are omitted until their GGUF exists.
