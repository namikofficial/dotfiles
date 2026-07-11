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

echo "Done. Next:"
echo "  1) put GGUF files under: $HOME/llama-models/chat and $HOME/llama-models/embed"
echo "  2) llama-swap-manager start       # chat/agent endpoint :8080"
echo "  3) embedding-server-manager start # embeddings endpoint :8081"
echo "  4) llama-swap-manager test"
echo "  5) local-ai-runtime stop          # cool the machine back down when done"
