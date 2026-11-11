#!/usr/bin/env bash
# Install the local llama.cpp router: user unit, preset and helper symlinks.
#
# The unit is installed but NOT enabled at login. The workstation prioritises
# CUDA availability over battery and a resident model server costs both, so
# the router is started on demand:
#
#   ~/.local/bin/llama-router start
#
# Usage: setup/install-llama-router.sh [--dry-run]
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unit_src="$repo_dir/systemd/user/llama-router.service"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
model_root="${LLAMA_MODEL_ROOT:-/home/namik/llama-models}"
dry_run=0

if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
  shift
fi
if (($# != 0)); then
  printf 'Usage: %s [--dry-run]\n' "$0" >&2
  exit 64
fi

command -v llama-server >/dev/null 2>&1 || {
  printf 'llama-server is not installed; install llama.cpp-cuda-git first\n' >&2
  exit 1
}

if [[ ! -d "$model_root" ]]; then
  printf 'model root %s does not exist; run setup/download-local-models.sh core\n' "$model_root" >&2
  exit 1
fi

run() {
  if ((dry_run)); then
    printf '[dry-run] %s\n' "$*"
    return
  fi
  "$@"
}

mkdir -p "$unit_dir" "$bin_dir"

if ((dry_run)); then
  printf '[dry-run] ln -sfn %q %q\n' "$unit_src" "$unit_dir/llama-router.service"
  printf '[dry-run] ln -sfn %q %q\n' "$repo_dir/system/llama-router/llama-router.sh" "$bin_dir/llama-router"
else
  ln -sfn "$unit_src" "$unit_dir/llama-router.service"
  ln -sfn "$repo_dir/system/llama-router/llama-router.sh" "$bin_dir/llama-router"
  printf 'link %s -> %s\n' "$unit_dir/llama-router.service" "$unit_src"
  printf 'link %s -> %s\n' "$bin_dir/llama-router" "$repo_dir/system/llama-router/llama-router.sh"
fi

run python3 "$repo_dir/system/llama-router/render-preset.py" --model-root "$model_root"

run systemctl --user daemon-reload

# Deliberately NOT enabled at login. The workstation documentation keeps the
# local model router start-on-demand so a resident server does not drain the
# battery; the unit keeps [Install] WantedBy=default.target so it can be
# enabled explicitly if that trade-off is ever wanted.
printf '\nRouter installed. It is not enabled at login and is not running.\n'
printf 'Start it with:  %s start\n' "$bin_dir/llama-router"
printf 'Check it with:  %s status\n' "$bin_dir/llama-router"
printf 'Enable at login: systemctl --user enable llama-router.service\n'
printf 'Lane list:\n'
run python3 "$repo_dir/system/llama-router/render-preset.py" \
  --model-root "$model_root" --print
