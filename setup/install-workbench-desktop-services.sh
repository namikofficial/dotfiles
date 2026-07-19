#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unit_source="$repo_dir/systemd/user"
unit_dest="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
action="${1:-install}"
option="${2:-}"
dry_run=false

if [[ "$action" == "--dry-run" ]]; then
  action="install"
  dry_run=true
fi
if [[ "$option" == "--dry-run" ]]; then
  dry_run=true
fi

units=(
  ai-workbench-desktop-observer.service
  ai-workbench-project-watch.service
  ai-workbench-notification-bridge.service
)
scripts=(
  ai-workbench-observer
  ai-workbench-project-watch.py
  ai-workbench-notification-bridge.py
)

run() {
  if [[ "$dry_run" == true ]]; then
    printf 'dry-run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

validate_launchers() {
  local script
  local scripts_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
  [[ "$dry_run" == true ]] && return 0
  for script in "${scripts[@]}"; do
    if [[ ! -x "$scripts_dir/$script" ]]; then
      printf 'Desktop launcher is missing or not executable: %s\n' "$scripts_dir/$script" >&2
      printf 'Run ./setup/bootstrap.sh first, or link the repository hypr directory into XDG config.\n' >&2
      return 1
    fi
  done
}

case "$action" in
  install)
    run mkdir -p "$unit_dest"
    for unit in "${units[@]}"; do
      run install -m 0644 "$unit_source/$unit" "$unit_dest/$unit"
    done
    run systemctl --user daemon-reload
    if [[ "$option" == "--enable" ]]; then
      validate_launchers
      run systemctl --user enable --now "${units[@]}"
    elif [[ -n "$option" && "$option" != "--dry-run" ]]; then
      printf 'Unknown install option: %s\n' "$option" >&2
      exit 2
    fi
    printf 'Installed AI Workbench desktop bridge units.\n'
    printf 'Enable with: %s install --enable\n' "$0"
    ;;
  uninstall)
    if [[ -n "$option" && "$option" != "--dry-run" ]]; then
      printf 'Unknown uninstall option: %s\n' "$option" >&2
      exit 2
    fi
    run systemctl --user disable --now "${units[@]}" || true
    for unit in "${units[@]}"; do
      if [[ -e "$unit_dest/$unit" || -L "$unit_dest/$unit" ]]; then
        run rm -- "$unit_dest/$unit"
      fi
    done
    run systemctl --user daemon-reload
    printf 'Removed AI Workbench desktop bridge units; caches and runtime configuration were preserved.\n'
    ;;
  status)
    systemctl --user status "${units[@]}" --no-pager
    ;;
  *)
    printf 'Usage: %s [install [--enable|--dry-run]|uninstall [--dry-run]|status|--dry-run]\n' "$0" >&2
    exit 2
    ;;
esac
