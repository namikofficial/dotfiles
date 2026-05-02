#!/bin/bash
# Model Download Setup for llama.cpp
# This script handles authentication and downloads LLM models

set -e

MODEL_DIR="${HOME}/llama-models"
mkdir -p "$MODEL_DIR"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         LLM Model Download Setup                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check authentication
echo "📋 Step 1: HuggingFace Authentication"
echo "   The models require you to:"
echo "   1. Create account: https://huggingface.co/join"
echo "   2. Accept Gemma license: https://huggingface.co/google/gemma-7b-it"
echo "   3. Accept DeepSeek license: https://huggingface.co/deepseek-ai/deepseek-coder-6.7b-instruct"
echo "   4. Create token: https://huggingface.co/settings/tokens"
echo ""

# Step 2: Login
echo "🔑 Step 2: Login to HuggingFace"
read -p "   Enter your HF token (or press Enter to skip): " HF_TOKEN

if [ -n "$HF_TOKEN" ]; then
  huggingface-cli login --token "$HF_TOKEN" --add-to-git-credential || true
  echo "✅ Authenticated"
fi

echo ""
echo "⬇️  Step 3: Downloading models to $MODEL_DIR"
echo ""

# Download Gemma 7B
echo "📦 Gemma 7B (general tasks)..."
~/.local/share/pipx/venvs/huggingface-hub/bin/python3 << 'PY1'
from huggingface_hub import hf_hub_download
import os

try:
    path = hf_hub_download(
        repo_id="TheBloke/Gemma-7B-Instruct-GGUF",
        filename="gemma-7b-it-Q4_K_M.gguf",
        local_dir=os.path.expanduser("~/llama-models"),
    )
    size = os.path.getsize(path)
    print(f"   ✅ {os.path.basename(path)} ({size/(1024**3):.1f} GB)")
except Exception as e:
    print(f"   ❌ Failed: {str(e)[:100]}")
PY1

echo ""

# Download DeepSeek-Coder
echo "📦 DeepSeek-Coder 6.7B (code tasks)..."
~/.local/share/pipx/venvs/huggingface-hub/bin/python3 << 'PY2'
from huggingface_hub import hf_hub_download
import os

try:
    path = hf_hub_download(
        repo_id="TheBloke/deepseek-coder-6.7B-instruct-GGUF",
        filename="deepseek-coder-6.7b-instruct-Q4_K_M.gguf",
        local_dir=os.path.expanduser("~/llama-models"),
    )
    size = os.path.getsize(path)
    print(f"   ✅ {os.path.basename(path)} ({size/(1024**3):.1f} GB)")
except Exception as e:
    print(f"   ❌ Failed: {str(e)[:100]}")
PY2

echo ""
echo "📦 Downloaded models:"
ls -lh "$MODEL_DIR/" | tail -n +2 | awk '{print "   " $9 " (" $5 ")"}'

echo ""
echo "✅ Setup complete! You can now run:"
echo "   llm-manager start gemma"
