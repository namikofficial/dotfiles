#!/usr/bin/env bash
set -euo pipefail

AI_PYTHON="${NOX_AI_PYTHON:-$HOME/.local/share/nox-ai/bin/python}"
OCR_PYTHON="${NOX_OCR_PYTHON:-$HOME/.local/share/nox-ocr/bin/python}"
MODEL_ROOT="${NOX_AI_MODEL_ROOT:-$HOME/ai-models}"

printf 'AI Python: %s\n' "$AI_PYTHON"
printf 'OCR Python: %s\n' "$OCR_PYTHON"
printf 'Model root: %s\n' "$MODEL_ROOT"

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader
fi

"$AI_PYTHON" - <<'PY'
import torch
import transformers
import whisper
from tree_sitter import Parser
import qdrant_client

print(f'torch: {torch.__version__}; CUDA available: {torch.cuda.is_available()}')
print(f'transformers: {transformers.__version__}')
print(f'whisper: {whisper.__file__}')
print(f'tree-sitter: {Parser.__module__}')
print(f'qdrant-client: {qdrant_client.QdrantClient.__module__}')
PY

for path in \
  "$MODEL_ROOT/embedding/qwen3-embedding-0.6b/model.safetensors" \
  "$MODEL_ROOT/rerank/qwen3-reranker-0.6b/model.safetensors" \
  "$MODEL_ROOT/vision/dinov2-small/config.json"; do
  test -f "$path" && printf 'asset: ok %s\n' "$path" || printf 'asset: missing %s\n' "$path"
done

if command -v colgrep >/dev/null 2>&1; then
  colgrep --version
fi
