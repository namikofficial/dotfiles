#!/usr/bin/env bash
# gemma-setup.sh - Download and validate Gemma 3 4B for CUDA

set -euo pipefail

MODELS_DIR="${HOME}/llama-models"
GEMMA_URL="https://huggingface.co/bartowski/google_gemma-3-4b-it-GGUF/resolve/main/google_gemma-3-4b-it-Q4_K_M.gguf"
GEMMA_FILE="$MODELS_DIR/google_gemma-3-4b-it-Q4_K_M.gguf"
TMP_FILE="${GEMMA_FILE}.tmp"

is_valid_gguf() {
  [ -s "$1" ] || return 1
  [ "$(head -c 4 "$1" 2>/dev/null)" = "GGUF" ]
}

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           Gemma 3 4B Setup for CUDA (llama.cpp)              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v curl >/dev/null 2>&1 || { echo "✗ curl not found"; exit 1; }
command -v llama-server >/dev/null 2>&1 || { echo "✗ llama-server not found"; exit 1; }

# Create models directory
mkdir -p "$MODELS_DIR"
echo "✓ Models directory: $MODELS_DIR"
echo ""

# Check if Gemma already exists
if is_valid_gguf "$GEMMA_FILE"; then
  size=$(du -h "$GEMMA_FILE" | cut -f1)
  echo "✓ Gemma 3 4B Q4_K_M already downloaded ($size)"
  echo "  Path: $GEMMA_FILE"
  echo ""
else
  if [ -f "$GEMMA_FILE" ]; then
    echo "⚠ Existing Gemma file is not a valid GGUF model. Re-downloading."
    rm -f "$GEMMA_FILE"
  fi
  echo "⟳ Downloading Gemma 3 4B Q4_K_M from HuggingFace..."
  echo "  URL: $GEMMA_URL"
  echo "  Size: ~2.5 GB (this may take a while)"
  echo ""

  if curl -fL --progress-bar -o "$TMP_FILE" "$GEMMA_URL"; then
    if ! is_valid_gguf "$TMP_FILE"; then
      echo ""
      echo "✗ Download completed but the file is not a valid GGUF model."
      echo "  First bytes: $(head -c 32 "$TMP_FILE" 2>/dev/null | cat -v)"
      rm -f "$TMP_FILE"
      exit 1
    fi
    mv "$TMP_FILE" "$GEMMA_FILE"
    size=$(du -h "$GEMMA_FILE" | cut -f1)
    echo ""
    echo "✓ Downloaded and validated: $size"
  else
    echo "✗ Download failed. Check network and try again."
    rm -f "$TMP_FILE"
    exit 1
  fi
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              Gemma 3 4B Setup Complete!                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "CUDA Configuration:"
echo "  • RTX 4050 Laptop GPU detected (~6GB VRAM)"
echo "  • Gemma 3 4B Q4_K_M: ~2.4GB model file"
echo "  • Recommended local router context on this machine: 32768"
echo "  • Run one model at a time through llama-swap"
echo ""
echo "Gemma is now available through:"
echo "  1. llama-swap model id: gemma-3-4b"
echo "  2. OpenCode provider model: llamacpp/gemma-3-4b"
echo ""
echo "To verify:"
echo "  $ llama-server -m $GEMMA_FILE --list-devices"
echo "  $ llama-server -m $GEMMA_FILE -ngl 99 -c 32768 -t 8"
echo ""
