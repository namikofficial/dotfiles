#!/usr/bin/env sh
set -eu

# Include common binary locations used by some desktop agents.
for p in /usr/lib/hyprpolkitagent /usr/libexec /usr/lib/polkit-gnome; do
  if [ -d "$p" ]; then
    PATH="$p:$PATH"
  fi
done
export PATH

# Load feature flags (overrides env defaults set inline below).
_features_env="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/features.env"
# shellcheck source=/dev/null
[ -f "$_features_env" ] && . "$_features_env"
unset _features_env

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG_DIR="$STATE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/hypr-startup-$(date +%Y%m%d-%H%M%S).log"
ln -sfn "$(basename "$LOG_FILE")" "$LOG_DIR/hypr-startup-latest.log"

log() {
  printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG_FILE"
}

prune_startup_logs() {
  find "$LOG_DIR" -maxdepth 1 -type f -name 'hypr-startup-*.log' -printf '%T@ %p\n' 2>/dev/null |
    sort -nr |
    awk 'NR > 10 { print $2 }' |
    while IFS= read -r old_log; do
      [ -n "$old_log" ] && rm -f -- "$old_log"
    done
}

prune_startup_logs
log "starting Hyprland session bootstrap"

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

setting_bool() {
  key="$1"
  fallback="${2:-true}"

  if [ -x "$HOME/.config/hypr/scripts/settingsctl" ]; then
    value="$("$HOME/.config/hypr/scripts/settingsctl" get "$key" 2>/dev/null || true)"
    case "$value" in
      true | false)
        printf '%s\n' "$value"
        return 0
        ;;
    esac
  fi

  printf '%s\n' "$fallback"
}

# Warm launcher cache first so Super+Space opens immediately.
if [ -x "$HOME/.config/hypr/scripts/launcher.sh" ]; then
  log "warming launcher cache"
  "$HOME/.config/hypr/scripts/launcher.sh" --warm-cache >/dev/null 2>&1 &
fi

# Initialize notification cache/state early so downstream scripts can emit
# events safely during session bootstrap.
if [ -x "$HOME/.config/hypr/scripts/lib/log.sh" ]; then
  log "initializing notification cache"
  "$HOME/.config/hypr/scripts/lib/log.sh" --init >/dev/null 2>&1 || true
fi

# Apply generated settings overlays for Hypr/Wayle at session start.
if [ -x "$HOME/.config/hypr/scripts/settingsctl" ]; then
  log "scheduling generated settings apply"
  (
    sleep 0.5
    "$HOME/.config/hypr/scripts/settingsctl" apply all >/dev/null 2>&1 || true
  ) &
fi

# Warm cheatsheet cache so Super+. opens immediately.
if [ -x "$HOME/.config/hypr/scripts/dev-cheatsheet.sh" ]; then
  log "warming cheatsheet cache"
  "$HOME/.config/hypr/scripts/dev-cheatsheet.sh" --warm-cache >/dev/null 2>&1 &
fi

# Warm scratch/AI dependencies so Super+` paths do not stall on first use.
(
  log "warming scratchpad dependencies"
  sleep 2
  for cmd in jq python3 hyprctl kitty; do
    command -v "$cmd" >/dev/null 2>&1 || true
  done
  if [ -x "$HOME/.config/hypr/scripts/scratchpad-manager.sh" ]; then
    "$HOME/.config/hypr/scripts/scratchpad-manager.sh" menu >/dev/null 2>&1 || true
  fi
  if [ "${HYPR_AUTOSTART_LOCAL_LLM:-0}" = "1" ] && command -v curl >/dev/null 2>&1 && command -v llama-swap-manager >/dev/null 2>&1; then
    if ! curl -fsS --max-time 1 "${LLM_HEALTH_ENDPOINT:-http://127.0.0.1:8080/v1/models}" >/dev/null 2>&1; then
      llama-swap-manager start >/dev/null 2>&1 || true
    fi
  fi
) &

# Keep the clipboard browser daemon warm so clipboard UI opens on the hot path.
if [ -x "$HOME/.config/hypr/scripts/cliphist-daemon.sh" ]; then
  log "scheduling clipboard browser daemon warmup"
  (
    sleep 3
    "$HOME/.config/hypr/scripts/cliphist-daemon.sh" start >/dev/null 2>&1 || true
  ) &
fi

# Warm desktop-app binaries/resources in page cache so first-launch latency is
# less noticeable without keeping the apps visibly open all session.
if [ "${HYPR_WARM_DESKTOP_APPS:-1}" = "1" ] && [ -x "$HOME/.config/hypr/scripts/app-warm-cache.sh" ]; then
  log "scheduling desktop app cache warmup"
  (
    sleep 6
    "$HOME/.config/hypr/scripts/app-warm-cache.sh" --session >/dev/null 2>&1 || true
  ) &
fi

# Optional cold-start improvement: keep browser process hot in background.
# Default off to reduce login work; opt in with HYPR_PRELAUNCH_BROWSER=1.
if [ "${HYPR_PRELAUNCH_BROWSER:-0}" = "1" ] && ! pgrep -x 'chrome|google-chrome|google-chrome-stable|chromium|chromium-browser' >/dev/null 2>&1; then
  log "scheduling browser prelaunch"
  (
    sleep 10
    for browser in google-chrome-stable google-chrome chromium chromium-browser; do
      bin="$(resolve_cmd "$browser" || true)"
      [ -n "$bin" ] || continue
      "$bin" --no-startup-window >/dev/null 2>&1 &
      break
    done
  ) &
fi

# Re-apply preferred monitor layout and mode choices at session start.
if [ -x "$HOME/.config/hypr/scripts/monitor-control.sh" ]; then
  log "scheduling monitor layout apply"
  (
    sleep 1
    "$HOME/.config/hypr/scripts/monitor-control.sh" apply >/dev/null 2>&1 || true
  ) &
fi

# Start the Bluetooth tray applet; Wi-Fi is controlled through iwd/NoxFlow.
if [ "$(setting_bool startup.blueman_applet_autostart true)" = "true" ]; then
  log "starting blueman-applet"
  run_once blueman-applet blueman-applet
fi
log "starting udiskie tray"
run_cmd_if_not '(^|/)udiskie( .*)?$' udiskie --smart-tray --menu nested --no-appindicator
ensure_single_process udiskie

# Secret service for apps like Obsidian (encrypted token/key storage).
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  if ! pgrep -x gnome-keyring-daemon >/dev/null 2>&1; then
    log "starting gnome-keyring-daemon"
    gnome-keyring-daemon --start --components=secrets >/dev/null 2>&1 || true
  fi
fi

# NoxFlow island provides visual OSD for volume/brightness.
# avizo-service is intentionally not started to avoid double OSDs.
# Panel shell — respects the persisted engine.
# noxflow-shell.service is WantedBy=graphical-session.target and starts on its
# own; do NOT call `panel-switch.sh show` here. That path probes the shell with
# a 0.5s sleep and would fall back to Wayle on a slow NoxFlow start, producing
# a dual-shell. Shell failure is handled by systemd's OnFailure →
# noxflow-fallback.service. Only start Wayle when the persisted engine is
# explicitly wayle.
if [ -x "$HOME/.config/hypr/scripts/panel-switch.sh" ]; then
  _engine_file="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow/panel.engine"
  _engine=""
  if [ -f "$_engine_file" ]; then
    _engine="$(cat "$_engine_file" 2>/dev/null || true)"
  fi
  if [ "$_engine" = "wayle" ]; then
    log "starting Wayle (persisted engine)"
    "$HOME/.config/hypr/scripts/panel-switch.sh" wayle >/dev/null 2>&1 || true
  else
    log "noxflow engine: noxflow-shell.service starts via graphical-session.target"
    # Clean up a stale fallback process from an earlier session. Wayle must not
    # remain as a second layer-shell bar above the NoxFlow rail.
    systemctl --user stop wayle.service >/dev/null 2>&1 || true
    pkill -x wayle >/dev/null 2>&1 || true
  fi
  unset _engine_file _engine
fi

log "starting monitor hotplug watcher"
run_cmd_if_not "$HOME/.config/hypr/scripts/monitor-hotplug-watch.sh" "$HOME/.config/hypr/scripts/monitor-hotplug-watch.sh"
# Let Hyprland's generic monitor rules handle displays by default.
# Only start kanshi when the user has provided an explicit profile config.
KANSHI_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
if [ -f "$KANSHI_CONFIG_HOME/kanshi/config" ]; then
  log "starting kanshi"
  run_once kanshi kanshi
fi
log "starting hypridle"
run_once hypridle hypridle
_settingsctl="$HOME/.config/hypr/scripts/settingsctl"
_auto_profile="false"
if [ -x "$_settingsctl" ]; then
  _auto_profile="$("$_settingsctl" get power.auto_profile 2>/dev/null || printf 'false')"
fi
if [ "$_auto_profile" = "true" ]; then
  log "starting power profile watcher (power.auto_profile=true)"
  run_cmd_if_not "$HOME/.config/hypr/scripts/power-profile-auto.sh" "$HOME/.config/hypr/scripts/power-profile-auto.sh"
else
  log "power profile watcher disabled by settings"
fi
unset _settingsctl _auto_profile

# hyprpm currently fails its header refresh path on Hyprland 0.54.1
# ("You need to run make all first"), which surfaces a false outdated-plugin
# warning on login. Keep automatic hyprpm reload opt-in until that is fixed.
if [ "${HYPR_USE_HYPRPM_RELOAD:-0}" = "1" ] && resolve_cmd hyprpm >/dev/null 2>&1; then
  log "scheduling hyprpm reload"
  (
    sleep 3
    hyprpm reload >/dev/null 2>&1 || true
  ) &
fi

# Keep hyprexpo off by default at session start. Loading it here after a
# Hyprland upgrade can surface a one-time version mismatch warning if the
# plugin was built against an older ABI. Super+Tab loads it on demand.
hyprexpo_plugin="${XDG_DATA_HOME:-$HOME/.local/share}/hypr/plugins/hyprexpo/hyprexpo.so"
if [ "${HYPR_LOAD_HYPREXPO_AT_STARTUP:-0}" = "1" ] && [ -f "$hyprexpo_plugin" ]; then
  log "scheduling hyprexpo plugin load"
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

# scroll-overview plugin (primary overview, replaces the QML overview).
# Built against the installed Hyprland headers (see setup/scrolloverview-rebuild.sh).
# Loaded here (not in 95-plugins.lua) because plugin load must happen before the
# Lua config can reference hl.plugin.scrolloverview. After a Hyprland upgrade the
# ABI changes: rebuild with setup/scrolloverview-rebuild.sh, then restart.
scrolloverview_plugin="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/plugins/libscrolloverview.so"
if [ -f "$scrolloverview_plugin" ]; then
  log "scheduling scroll-overview plugin load"
  (
    sleep 2
    if ! hyprctl plugin list 2>/dev/null | grep -qi 'scrolloverview'; then
      hyprctl plugin load "$scrolloverview_plugin" >/dev/null 2>&1 || log "scroll-overview plugin load failed (may need rebuild after Hyprland upgrade)"
    fi
    # The Lua config evaluates hl.plugin.scrolloverview at load time. Reload
    # the config so 95-plugins.lua binds SUPER+TAB to the plugin instead of the
    # legacy fallback.
    if hyprctl plugin list 2>/dev/null | grep -qi 'scrolloverview'; then
      hyprctl reload >/dev/null 2>&1 || true
    fi
  ) &
fi

# Start whichever polkit agent is available.
for agent in \
  hyprpolkitagent \
  /usr/lib/hyprpolkitagent/hyprpolkitagent \
  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
  /usr/libexec/polkit-gnome-authentication-agent-1 \
  lxqt-policykit-agent \
  mate-polkit; do
  if pgrep -f 'polkit.*agent|hyprpolkitagent' >/dev/null 2>&1; then
    break
  fi

  if [ -x "$agent" ]; then
    log "starting polkit agent: $agent"
    "$agent" >/dev/null 2>&1 &
    break
  fi

  bin="$(resolve_cmd "$agent" || true)"
  if [ -n "$bin" ]; then
    log "starting polkit agent: $bin"
    "$bin" >/dev/null 2>&1 &
    break
  fi
done

# Use cliphist only as a fallback when Author Clipboard is not installed.
author_clipboard_bin="$(resolve_cmd author-clipboard-daemon || true)"
if [ -z "$author_clipboard_bin" ] && [ -x "$HOME/.local/bin/author-clipboard-daemon" ]; then
  author_clipboard_bin="$HOME/.local/bin/author-clipboard-daemon"
fi
if [ -z "$author_clipboard_bin" ]; then
  wlpaste_bin="$(resolve_cmd wl-paste || true)"
  cliphist_bin="$(resolve_cmd cliphist || true)"
  if [ -n "$wlpaste_bin" ] && [ -n "$cliphist_bin" ]; then
    log "starting fallback clipboard history watchers"
    pkill -f 'wl-paste --type text --watch .*cliphist store' >/dev/null 2>&1 || true
    pkill -f 'wl-paste --type image --watch .*cliphist store' >/dev/null 2>&1 || true
    "$wlpaste_bin" --type text --watch "$cliphist_bin" store >/dev/null 2>&1 &
    "$wlpaste_bin" --type image --watch "$cliphist_bin" store >/dev/null 2>&1 &
  fi
fi

# Start kage project watch daemon
(
  log "starting kage project watcher"
  sleep 2
  _kage_watch_pid_file="${HOME}/.cache/kage/project-watch.pid"
  if [ -f "$_kage_watch_pid_file" ]; then
    _kage_wpid="$(cat "$_kage_watch_pid_file" 2>/dev/null || true)"
    if [ -n "$_kage_wpid" ] && kill -0 "$_kage_wpid" 2>/dev/null; then
      true
    else
      setsid -f "$HOME/.config/hypr/scripts/kage" project watch >/dev/null 2>&1
    fi
  else
    setsid -f "$HOME/.config/hypr/scripts/kage" project watch >/dev/null 2>&1
  fi
) &

# Set default wallpaper + sync theme after daemon boot.
if [ -x "$HOME/.config/hypr/scripts/set-wallpaper.sh" ]; then
  log "scheduling wallpaper init"
  (
    sleep 1.5
    "$HOME/.config/hypr/scripts/set-wallpaper.sh" --init >/dev/null 2>&1 || true
  ) &
fi

if [ -x "$HOME/.config/hypr/scripts/dynamic-theme-sync.sh" ]; then
  log "starting dynamic theme watcher"
  run_cmd_if_not "$HOME/.config/hypr/scripts/dynamic-theme-sync.sh watch" "$HOME/.config/hypr/scripts/dynamic-theme-sync.sh" watch
fi

if [ -x "$HOME/.config/hypr/scripts/wallpaper-rotate.sh" ]; then
  log "starting wallpaper rotation"
  run_cmd_if_not "$HOME/.config/hypr/scripts/wallpaper-rotate.sh" "$HOME/.config/hypr/scripts/wallpaper-rotate.sh"
fi

log "startup bootstrap queued"
