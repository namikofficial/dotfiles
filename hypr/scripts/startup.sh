#!/usr/bin/env sh
set -eu

# Include common binary locations used by some desktop agents.
for p in /usr/lib/hyprpolkitagent /usr/libexec /usr/lib/polkit-gnome; do
  if [ -d "$p" ]; then
    PATH="$p:$PATH"
  fi
done
export PATH

resolve_cmd() {
  cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    command -v "$cmd"
    return 0
  fi

  for candidate in \
    "/usr/lib/$cmd/$cmd" \
    "/usr/libexec/$cmd" \
    "/usr/lib/$cmd"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

run_once() {
  cmd="$1"
  proc="$2"
  bin="$(resolve_cmd "$cmd" || true)"
  if [ -n "$bin" ] && ! pgrep -x "$proc" >/dev/null 2>&1; then
    "$bin" >/dev/null 2>&1 &
  fi
}

run_cmd_if_not() {
  pattern="$1"
  shift
  if ! pgrep -f "$pattern" >/dev/null 2>&1; then
    "$@" >/dev/null 2>&1 &
  fi
}

ensure_single_process() {
  name="$1"
  pids="$(pgrep -x "$name" 2>/dev/null || true)"
  [ -n "$pids" ] || return 0
  keep="$(printf '%s\n' "$pids" | head -n1)"
  printf '%s\n' "$pids" | while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    [ "$pid" = "$keep" ] && continue
    kill "$pid" >/dev/null 2>&1 || true
  done
}

loaded_hyprexpo_path() {
  hypr_pid="$(pgrep -x Hyprland 2>/dev/null | head -n1 || true)"
  [ -n "$hypr_pid" ] || return 1
  awk '/\/.*hyprexpo\.so$/ { print $NF; exit }' "/proc/$hypr_pid/maps" 2>/dev/null
}

# Warm launcher cache first so Super+Space opens immediately.
if [ -x "$HOME/.config/hypr/scripts/launcher.sh" ]; then
  "$HOME/.config/hypr/scripts/launcher.sh" --warm-cache >/dev/null 2>&1 &
fi

# Apply generated settings overlays for Hypr/SwayNC at session start.
if [ -x "$HOME/.config/hypr/scripts/settingsctl" ]; then
  "$HOME/.config/hypr/scripts/settingsctl" apply all >/dev/null 2>&1 || true
fi

# Warm cheatsheet cache so Super+. opens immediately.
if [ -x "$HOME/.config/hypr/scripts/dev-cheatsheet.sh" ]; then
  "$HOME/.config/hypr/scripts/dev-cheatsheet.sh" --warm-cache >/dev/null 2>&1 &
fi

# Re-apply preferred monitor layout and mode choices at session start.
if [ -x "$HOME/.config/hypr/scripts/monitor-control.sh" ]; then
  "$HOME/.config/hypr/scripts/monitor-control.sh" apply >/dev/null 2>&1 || true
fi

# nm-applet can spam duplicate StatusNotifier warnings with Waybar on some setups.
# Keep it opt-in (set HYPR_ENABLE_NM_APPLET=1 to auto-start it).
if [ "${HYPR_ENABLE_NM_APPLET:-0}" = "1" ]; then
  run_once nm-applet nm-applet
fi
run_once blueman-applet blueman-applet
run_cmd_if_not '(^|/)udiskie( .*)?$' udiskie --smart-tray --menu nested --no-appindicator
ensure_single_process udiskie

# Secret service for apps like Obsidian (encrypted token/key storage).
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  if ! pgrep -x gnome-keyring-daemon >/dev/null 2>&1; then
    gnome-keyring-daemon --start --components=secrets >/dev/null 2>&1 || true
  fi
fi

run_once avizo-service avizo-service
run_once waybar waybar
ensure_single_process waybar
run_cmd_if_not "$HOME/.config/hypr/scripts/monitor-hotplug-watch.sh" "$HOME/.config/hypr/scripts/monitor-hotplug-watch.sh"
# Let Hyprland's generic monitor rules handle displays by default.
# Only start kanshi when the user has provided an explicit profile config.
KANSHI_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
if [ -f "$KANSHI_CONFIG_HOME/kanshi/config" ]; then
  run_once kanshi kanshi
fi
run_once hypridle hypridle
run_cmd_if_not "$HOME/.config/hypr/scripts/power-profile-auto.sh" "$HOME/.config/hypr/scripts/power-profile-auto.sh"

# Ensure enabled hyprpm plugins are actually loaded after compositor startup.
if resolve_cmd hyprpm >/dev/null 2>&1; then
  (
    sleep 3
    hyprpm reload >/dev/null 2>&1 || true
  ) &
fi

# Load locally built hyprexpo when available. This avoids depending on hyprpm
# version pins for every session and keeps Super+Tab on the expo path.
hyprexpo_plugin="${XDG_DATA_HOME:-$HOME/.local/share}/hypr/plugins/hyprexpo/hyprexpo.so"
if [ -f "$hyprexpo_plugin" ]; then
  (
    sleep 2
    current_hyprexpo="$(loaded_hyprexpo_path || true)"
    if [ -n "$current_hyprexpo" ] && [ "$current_hyprexpo" != "$hyprexpo_plugin" ]; then
      hyprctl plugin unload "$current_hyprexpo" >/dev/null 2>&1 || true
      sleep 1
    fi
    if ! hyprctl plugin list 2>/dev/null | grep -q 'Plugin hyprexpo'; then
      hyprctl plugin load "$hyprexpo_plugin" >/dev/null 2>&1 || true
    fi
  ) &
fi

# Waybar occasionally races Hyprland startup on cold boots; retry once.
if resolve_cmd waybar >/dev/null 2>&1; then
  (
    sleep 2
    if ! pgrep -x waybar >/dev/null 2>&1; then
      "$(resolve_cmd waybar)" >/dev/null 2>&1 &
    fi
  ) &
fi

# Notifications: prefer swaync, fallback dunst.
if resolve_cmd swaync >/dev/null 2>&1; then
  run_once swaync swaync
  pkill -x dunst >/dev/null 2>&1 || true

  # Ensure popups are not silently suppressed by stale DND/inhibitors.
  if resolve_cmd swaync-client >/dev/null 2>&1; then
    (
      sleep 1
      swaync-client -sw -df >/dev/null 2>&1 || true
      swaync-client -sw -Ic >/dev/null 2>&1 || true
    ) &
  fi
else
  run_once dunst dunst
fi

if resolve_cmd swww >/dev/null 2>&1; then
  run_cmd_if_not '^swww-daemon$' swww-daemon
fi

if [ -f "$HOME/.config/hypr/hyprpaper.conf" ] && resolve_cmd hyprpaper >/dev/null 2>&1; then
  # Keep hyprpaper as fallback only if swww is not installed.
  if ! resolve_cmd swww >/dev/null 2>&1; then
    run_once hyprpaper hyprpaper
  fi
fi

# Start whichever polkit agent is available.
for agent in \
  hyprpolkitagent \
  /usr/lib/hyprpolkitagent/hyprpolkitagent \
  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
  /usr/libexec/polkit-gnome-authentication-agent-1 \
  lxqt-policykit-agent \
  mate-polkit \
  polkit-kde-authentication-agent-1; do
  if pgrep -f 'polkit.*agent|hyprpolkitagent' >/dev/null 2>&1; then
    break
  fi

  if [ -x "$agent" ]; then
    "$agent" >/dev/null 2>&1 &
    break
  fi

  bin="$(resolve_cmd "$agent" || true)"
  if [ -n "$bin" ]; then
    "$bin" >/dev/null 2>&1 &
    break
  fi
done

# Clipboard history daemon
wlpaste_bin="$(resolve_cmd wl-paste || true)"
cliphist_bin="$(resolve_cmd cliphist || true)"
if [ -n "$wlpaste_bin" ] && [ -n "$cliphist_bin" ]; then
  pkill -f 'wl-paste --type text --watch .*cliphist store' >/dev/null 2>&1 || true
  pkill -f 'wl-paste --type image --watch .*cliphist store' >/dev/null 2>&1 || true
  "$wlpaste_bin" --type text --watch "$cliphist_bin" store >/dev/null 2>&1 &
  "$wlpaste_bin" --type image --watch "$cliphist_bin" store >/dev/null 2>&1 &
fi

# Set default wallpaper + sync theme after daemon boot.
if [ -x "$HOME/.config/hypr/scripts/set-wallpaper.sh" ]; then
  "$HOME/.config/hypr/scripts/set-wallpaper.sh" --init >/dev/null 2>&1 || true
fi

if [ -x "$HOME/.config/hypr/scripts/dynamic-theme-sync.sh" ]; then
  run_cmd_if_not "$HOME/.config/hypr/scripts/dynamic-theme-sync.sh watch" "$HOME/.config/hypr/scripts/dynamic-theme-sync.sh" watch
fi

if [ -x "$HOME/.config/hypr/scripts/wallpaper-rotate.sh" ]; then
  run_cmd_if_not "$HOME/.config/hypr/scripts/wallpaper-rotate.sh" "$HOME/.config/hypr/scripts/wallpaper-rotate.sh"
fi
