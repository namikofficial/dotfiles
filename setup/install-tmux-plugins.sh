#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
PLUGIN_DIR="${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.tmux/plugins}"
TPM_DIR="$PLUGIN_DIR/tpm"

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: install-tmux-plugins.sh [--dry-run]
Installs/updates tmux plugin manager (TPM) and syncs plugins from ~/.tmux.conf.
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

run mkdir -p "$PLUGIN_DIR"

if [[ -d "$TPM_DIR/.git" ]]; then
  run git -C "$TPM_DIR" pull --ff-only
elif [[ -e "$TPM_DIR" ]]; then
  echo "warning: '$TPM_DIR' exists but is not a git repo, skipping clone" >&2
else
  run git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux not found; install tmux first." >&2
  exit 1
fi

if (( DRY_RUN )); then
  echo "[dry-run] tmux start-server"
  echo "[dry-run] $TPM_DIR/bin/install_plugins"
  echo "[dry-run] $TPM_DIR/bin/update_plugins all"
else
  tmux start-server
  "$TPM_DIR/bin/install_plugins" || true
  "$TPM_DIR/bin/update_plugins" all || true
fi

echo "tmux plugin sync complete: $TPM_DIR"
