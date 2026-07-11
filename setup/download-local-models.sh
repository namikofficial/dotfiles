#!/usr/bin/env bash
set -euo pipefail

MODEL_ROOT="${LLAMA_MODEL_ROOT:-/home/namik/llama-models}"
HF_BIN="${HF_BIN:-$(command -v hf || true)}"

[ -x "$HF_BIN" ] || {
  echo "hf CLI is missing. Install with: uv tool install 'huggingface_hub[cli]'" >&2
  exit 1
}

mkdir -p "$MODEL_ROOT"/{chat,coder,embed}
"$HF_BIN" download unsloth/Qwen3-4B-Instruct-2507-GGUF --include "*UD-Q4_K_XL*" --local-dir "$MODEL_ROOT/chat/qwen3-4b-instruct-2507"
"$HF_BIN" download ibm-granite/granite-4.0-h-tiny-GGUF --include "*Q4_K_M*" --local-dir "$MODEL_ROOT/chat/granite-4-h-tiny"
"$HF_BIN" download nomic-ai/nomic-embed-text-v2-moe-GGUF --include "*Q4_K_M*" --local-dir "$MODEL_ROOT/embed/nomic-embed-text-v2-moe"
"$HF_BIN" download nomic-ai/nomic-embed-code-GGUF --include "nomic-embed-code.Q4_K_S.gguf" --local-dir "$MODEL_ROOT/embed/nomic-embed-code"

if [ "${DOWNLOAD_HEAVY:-0}" = "1" ]; then
  "$HF_BIN" download unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF --include "*UD-Q4_K_XL*" --local-dir "$MODEL_ROOT/coder/qwen3-coder-30b-a3b"
fi

find "$MODEL_ROOT" -type f -name '*.gguf' -print
