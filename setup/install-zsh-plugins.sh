#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
PLUGIN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: install-zsh-plugins.sh [--dry-run]
Installs/updates optional zsh plugins under ~/.local/share/zsh/plugins.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

run() {
  if (( DRY_RUN )); then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

clone_or_update() {
  local name="$1"
  local url="$2"
  local target="$PLUGIN_DIR/$name"

  if [[ -d "$target/.git" ]]; then
    run git -C "$target" pull --ff-only
    return 0
  fi

  if [[ -e "$target" ]]; then
    echo "warning: '$target' exists but is not a git repo, skipping" >&2
    return 0
  fi

  run git clone --depth 1 "$url" "$target"
}

run mkdir -p "$PLUGIN_DIR"

clone_or_update "fzf-git.sh" "https://github.com/junegunn/fzf-git.sh.git"
clone_or_update "fzf-tab" "https://github.com/Aloxaf/fzf-tab.git"
clone_or_update "forgit" "https://github.com/wfxr/forgit.git"
clone_or_update "zsh-you-should-use" "https://github.com/MichaelAquilina/zsh-you-should-use.git"
clone_or_update "zsh-autopair" "https://github.com/hlissner/zsh-autopair.git"

echo "zsh plugin sync complete: $PLUGIN_DIR"
