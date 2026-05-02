#!/bin/bash
# Alternative model download - uses models that don't require gated access
# Falls back to freely available GGUF conversions

set -e

MODEL_DIR="${HOME}/llama-models"
mkdir -p "$MODEL_DIR"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   LLM Model Download (Alternative - Accessible Models)         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo "⚠️  Note: Gated models (Gemma, DeepSeek) require license acceptance"
echo "   We'll try alternative freely-available models instead"
echo ""

echo "⬇️  Downloading models to $MODEL_DIR"
echo ""

~/.local/share/pipx/venvs/huggingface-hub/bin/python3 << 'DLPY'
from huggingface_hub import hf_hub_download
import os

models = [
    # Accessible alternatives (not gated)
    ("lmstudio-community/Mistral-7B-Instruct-v0.2-GGUF", "Mistral-7B-Instruct-v0.2-Q4_K_M.gguf", "Mistral 7B (general)"),
    ("lmstudio-community/Meta-Llama-3-8B-Instruct-GGUF", "Meta-Llama-3-8B-Instruct-Q4_K_M.gguf", "Llama 3 8B (general)"),
    ("lmstudio-community/Phi-3-mini-4k-instruct-GGUF", "Phi-3-mini-4k-instruct-Q4_K_M.gguf", "Phi 3 Mini (fast)"),
]

print("📦 Attempting downloads...\n")

downloaded = []
for repo_id, filename, name in models:
    try:
        print(f"⬇️  {name}")
        path = hf_hub_download(
            repo_id=repo_id,
            filename=filename,
            local_dir=os.path.expanduser("~/llama-models"),
        )
        size = os.path.getsize(path) / (1024**3)
        print(f"   ✅ {os.path.basename(path)} ({size:.1f} GB)\n")
        downloaded.append((os.path.basename(path), size))
        break  # Download just the first one that works
    except Exception as e:
        error_msg = str(e)
        if "401" in error_msg:
            print(f"   ⚠️  Gated (need license): {repo_id}\n")
        elif "404" in error_msg:
            print(f"   ❌ Not found: {filename}\n")
        else:
            print(f"   ⚠️  {str(e)[:60]}\n")
        continue

if downloaded:
    print(f"\n✅ Downloaded {len(downloaded)} model(s):")
    for fname, size in downloaded:
        print(f"   • {fname} ({size:.1f} GB)")
else:
    print("\n❌ All downloads failed. Check your internet connection or try:")
    print("   1. Manually accept licenses: https://huggingface.co/settings/gated-models")
    print("   2. Use browser to download: https://huggingface.co/TheBloke")
    print("   3. Place .gguf files in ~/llama-models/")
DLPY

echo ""
echo "📦 Models in $MODEL_DIR:"
ls -lh "$MODEL_DIR" 2>/dev/null | tail -n +2 || echo "   (No models yet)"

echo ""
echo "If downloads failed, you can:"
echo "1. Try the interactive setup again with 'hf auth login'"
echo "2. Download manually from https://huggingface.co/lmstudio-community"
echo "3. Or contact support on HuggingFace"
