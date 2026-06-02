#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-gemma-3-4b}"
MODELS_DIR="${HOME}/llama-models"

mkdir -p "$MODELS_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║            LLM Model Downloader                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

case "$MODEL" in
  gemma|gemma-3-4b)
    echo "Gemma 3 4B Instruct (Q4_K_M quantization)"
    echo "Size: ~3.3 GB"
    echo "Current local alias: model=local via llama-swap"
    echo
    echo "Manual download links (choose one):"
    echo "1. HuggingFace:"
    echo "   https://huggingface.co/google/gemma-3-4b-it-GGUF"
    echo
    echo "2. Or use huggingface-cli:"
    echo "   huggingface-cli download google/gemma-3-4b-it-GGUF google_gemma-3-4b-it-Q4_K_M.gguf --local-dir $MODELS_DIR"
    echo
    echo "3. Save to: $MODELS_DIR/google_gemma-3-4b-it-Q4_K_M.gguf"
    echo
    ;;
  qwen|coder|qwen-coder|qwen-coder-7b|qwen2.5-coder-7b)
    echo "Qwen2.5-Coder-7B Instruct (Q4_K_M quantization)"
    echo "Size: ~4.7 GB"
    echo "Current local alias: model=local via llama-swap (after config update)"
    echo
    echo "Manual download links (choose one):"
    echo "1. HuggingFace:"
    echo "   https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF"
    echo
    echo "2. Or use huggingface-cli:"
    echo "   huggingface-cli download Qwen/Qwen2.5-Coder-7B-Instruct-GGUF qwen2.5-coder-7b-instruct-q4_k_m.gguf --local-dir $MODELS_DIR"
    echo
    echo "3. Save to: $MODELS_DIR/qwen2.5-coder-7b-instruct-q4_k_m.gguf"
    echo
    ;;
  *)
    echo "Usage: $0 [gemma-3-4b|qwen-coder-7b]"
    echo "Only llama-swap-wired models should be documented here."
    exit 1
    ;;
esac

echo "After downloading, verify:"
echo "  ls -lh $MODELS_DIR/"
echo
echo "Then start server:"
echo "  llama-swap-manager start"
