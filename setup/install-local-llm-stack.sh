#!/usr/bin/env bash
set -euo pipefail

# Installs local coder-focused stack with package-managed updates.
# Run as your normal user (script uses sudo only for package install).

PACMAN_PKGS=(opencode cuda)
AUR_PKGS=(llama.cpp-cuda-git llama-swap-bin)

echo "Installing pacman packages: ${PACMAN_PKGS[*]}"
sudo pacman -S --needed "${PACMAN_PKGS[@]}"

echo "Installing AUR packages: ${AUR_PKGS[*]}"
yay -S --needed "${AUR_PKGS[@]}"

echo "Linking managers"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/opencode"
ln -sf "$HOME/Documents/code/dotfiles/system/local-ai-runtime.sh" "$HOME/.local/bin/local-ai-runtime"
ln -sf "$HOME/Documents/code/dotfiles/system/llama-swap-manager.sh" "$HOME/.local/bin/llama-swap-manager"
ln -sf "$HOME/Documents/code/dotfiles/system/embedding-server-manager.sh" "$HOME/.local/bin/embedding-server-manager"
ln -sf /usr/bin/llama-server "$HOME/.local/bin/llama-server"
ln -sf /usr/bin/llama-swap "$HOME/.local/bin/llama-swap"
ln -sf "$HOME/Documents/code/dotfiles/configs/opencode/opencode.local-llamacpp.json" "$HOME/.config/opencode/opencode.json"
rm -f "$HOME/.local/bin/llm-manager"

# Remove remembered local model IDs that are no longer routed by llama-swap.
MODEL_STATE="$HOME/.local/state/opencode/model.json"
if [ -f "$MODEL_STATE" ]; then
  python - "$MODEL_STATE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    state = json.loads(path.read_text())
except (OSError, ValueError):
    raise SystemExit(0)

allowed_local = {"granite-agent"}
for key in ("recent", "favorite"):
    values = state.get(key, [])
    state[key] = [
        item for item in values
        if item.get("providerID") != "llamacpp"
        or item.get("modelID") in allowed_local
    ]
state["variant"] = {
    key: value for key, value in state.get("variant", {}).items()
    if not key.startswith("llamacpp/") or key == "llamacpp/granite-agent"
}
path.write_text(json.dumps(state, separators=(",", ":")) + "\n")
PY
fi

echo "Done. Next:"
echo "  1) put GGUF files under: $HOME/llama-models/chat and $HOME/llama-models/embed"
echo "  2) llama-swap-manager start       # chat/agent endpoint :8080"
echo "  3) embedding-server-manager start # embeddings endpoint :8081"
echo "  4) llama-swap-manager test"
echo "  5) local-ai-runtime stop          # cool the machine back down when done"
