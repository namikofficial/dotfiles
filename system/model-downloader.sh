#!/usr/bin/env bash
# Model downloader with direct link finder
# Usage: ./model-downloader.sh <model-name>

set -euo pipefail

MODEL="${1:-gemma}"
MODELS_DIR="${HOME}/llama-models"

mkdir -p "$MODELS_DIR"
cd "$MODELS_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║            LLM Model Downloader                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

case "$MODEL" in
  gemma)
    echo "Gemma 7B Instruct (Q4_K_M quantization)"
    echo "Size: ~4.5 GB"
    echo "Speed: 50-60 tokens/sec on GTX 4050"
    echo
    echo "Manual download links (choose one):"
    echo "1. HuggingFace (mirror):"
    echo "   https://huggingface.co/TheBloke/Gemma-7B-Instruct-GGUF/blob/main/gemma-7b-it-Q4_K_M.gguf"
    echo
    echo "2. Or use huggingface-cli (if installed):"
    echo "   huggingface-cli download TheBloke/Gemma-7B-Instruct-GGUF gemma-7b-it-Q4_K_M.gguf --local-dir ."
    echo
    echo "3. Save to: $MODELS_DIR/gemma-7b-it-Q4_K_M.gguf"
    echo
    ;;
  
  code|deepseek)
    echo "DeepSeek-Coder 6.7B Instruct (Q4_K_M quantization)"
    echo "Size: ~4.0 GB"
    echo "Speed: 40-50 tokens/sec on GTX 4050"
    echo "Best for: Code analysis, agentic tasks"
    echo
    echo "Manual download links (choose one):"
    echo "1. HuggingFace (mirror):"
    echo "   https://huggingface.co/TheBloke/deepseek-coder-6.7B-instruct-GGUF/blob/main/deepseek-coder-6.7b-instruct-Q4_K_M.gguf"
    echo
    echo "2. Or use huggingface-cli:"
    echo "   huggingface-cli download TheBloke/deepseek-coder-6.7B-instruct-GGUF deepseek-coder-6.7b-instruct-Q4_K_M.gguf --local-dir ."
    echo
    echo "3. Save to: $MODELS_DIR/deepseek-coder-6.7b-instruct-Q4_K_M.gguf"
    echo
    ;;
  
  *)
    echo "Usage: $0 [gemma|code]"
    exit 1
    ;;
esac

echo "After downloading, verify:"
echo "  ls -lh $MODELS_DIR/"
echo
echo "Then start server:"
echo "  llm-manager start $MODEL"
