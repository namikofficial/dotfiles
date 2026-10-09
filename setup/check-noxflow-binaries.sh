#!/usr/bin/env bash
set -euo pipefail

# check-noxflow-binaries.sh — verify every external program the shell launches
# is actually installed.
#
# The shell used to reference gnome-control-center, thunar, zenity and magick,
# none of which exist on this workstation. Each missing binary turned a button
# into a silent no-op. config/Apps.qml is now the single registry of external
# commands and probes them at startup, but a typo or a removed package still
# produces a disabled entry rather than a visible failure — so check it here.
#
# Modes:
#   (default)     required programs must be present; optional ones are reported
#   --all         every registered program must be present
#   --list        print the parsed registry and exit

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
apps_qml="$repo_dir/shell/noxflow/config/Apps.qml"

if [[ ! -f "$apps_qml" ]]; then
  echo "FAIL: $apps_qml not found" >&2
  exit 1
fi

mode="required"
case "${1:-}" in
  --all) mode="all" ;;
  --list) mode="list" ;;
  "") ;;
  *)
    echo "usage: ${BASH_SOURCE[0]} [--all|--list]" >&2
    exit 2
    ;;
esac

# Programs the shell cannot function without. Everything else is a feature
# toggle: a missing binary disables that entry with a tooltip.
required_programs=(
  grim        # screen capture
  tesseract   # OCR
  notify-send # user feedback
  systemctl   # service control and fallbacks
  loginctl    # session lock fallback
  hyprctl     # compositor control and workspace fallbacks
  # No dunstctl: Quickshell owns org.freedesktop.Notifications and Do Not
  # Disturb is NotificationModel.dnd, not an external command.
)

# Parse `"id": { command: "bin", label: "..." }` out of Apps.qml.
mapfile -t entries < <(
  grep -oE '"[a-zA-Z]+": *\{ *command: *"[a-zA-Z0-9._-]+"' "$apps_qml" |
    sed -E 's/^"([a-zA-Z]+)".*command: *"([a-zA-Z0-9._-]+)"$/\1 \2/'
)

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "FAIL: no programs parsed from $apps_qml" >&2
  exit 1
fi

declare -A binaries=()
for entry in "${entries[@]}"; do
  binaries["${entry%% *}"]="${entry##* }"
done

if [[ "$mode" == "list" ]]; then
  for id in "${!binaries[@]}"; do
    printf '%-14s %s\n' "$id" "${binaries[$id]}"
  done | sort
  exit 0
fi

missing_required=()
missing_optional=()

for binary in "${required_programs[@]}"; do
  command -v "$binary" >/dev/null 2>&1 || missing_required+=("$binary")
done

if [[ "$mode" == "all" ]]; then
  for id in "${!binaries[@]}"; do
    binary="${binaries[$id]}"
    command -v "$binary" >/dev/null 2>&1 || missing_optional+=("$id ($binary)")
  done
else
  # In the default mode, still verify that every id in required_programs is
  # actually registered — a rename in Apps.qml must not silently drop a check.
  for binary in "${required_programs[@]}"; do
    registered=false
    for id in "${!binaries[@]}"; do
      if [[ "${binaries[$id]}" == "$binary" ]]; then
        registered=true
        break
      fi
    done
    if [[ "$registered" == false ]]; then
      echo "FAIL: required program '$binary' is not registered in Apps.qml" >&2
      missing_required+=("$binary (unregistered)")
    fi
  done
fi

if [[ ${#missing_optional[@]} -gt 0 ]]; then
  printf 'optional programs unavailable (their shell entries are disabled): %s\n' \
    "${missing_optional[*]}"
fi

if [[ ${#missing_required[@]} -gt 0 ]]; then
  echo "FAIL: required NoxFlow programs are not installed: ${missing_required[*]}" >&2
  echo "Fix: sudo pacman -S --needed ${missing_required[*]}" >&2
  exit 1
fi

echo "NoxFlow binaries: ${#binaries[@]} registered, all required present"
