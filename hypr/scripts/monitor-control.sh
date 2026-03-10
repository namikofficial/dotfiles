#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/monitor-layout.json"
ROFI_THEME="$HOME/.config/rofi/actions.rasi"
INTERNAL_MONITOR="eDP-1"
EXTERNAL_DESC="desc:LG Electronics LG ULTRAGEAR 0x0000A0D5"

ensure_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  if [[ ! -s "$STATE_FILE" ]]; then
    cat > "$STATE_FILE" <<'EOF'
{"layout":"external-up","external_mode":"preferred","external_scale":"1","internal_scale":"1"}
EOF
  fi
}

state_get() {
  local key="$1"
  jq -r --arg key "$key" '.[$key]' "$STATE_FILE"
}

state_set() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

notify() {
  local title="$1"
  local body="$2"
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Monitor Control" "$title" "$body"
}

apply_state() {
  ensure_state

  local layout external_mode external_scale internal_scale
  layout="$(state_get layout)"
  external_mode="$(state_get external_mode)"
  external_scale="$(state_get external_scale)"
  internal_scale="$(state_get internal_scale)"

  case "$layout" in
    external-up)
      hyprctl keyword monitor "$EXTERNAL_DESC,$external_mode,0x0,$external_scale" >/dev/null
      hyprctl keyword monitor "$INTERNAL_MONITOR,preferred,auto-down,$internal_scale" >/dev/null
      ;;
    external-right)
      hyprctl keyword monitor "$INTERNAL_MONITOR,preferred,0x0,$internal_scale" >/dev/null
      hyprctl keyword monitor "$EXTERNAL_DESC,$external_mode,auto-right,$external_scale" >/dev/null
      ;;
    *)
      echo "unknown layout: $layout" >&2
      exit 1
      ;;
  esac

  hyprctl keyword monitor ",preferred,auto,1" >/dev/null || true
  hyprctl dispatch dpms on >/dev/null || true
}

recover_outputs() {
  apply_state
  hyprctl reload >/dev/null || true
  hyprctl dispatch dpms on >/dev/null || true
}

show_menu() {
  ensure_state
  local current_layout current_mode choice action
  current_layout="$(state_get layout)"
  current_mode="$(state_get external_mode)"

  choice="$(
    cat <<EOF | rofi -dmenu -i -p "Monitor Control" -theme "$ROFI_THEME" || true
Recover displays|recover
External above laptop$( [[ "$current_layout" == "external-up" ]] && printf ' (Current)' )|layout:external-up
External right of laptop$( [[ "$current_layout" == "external-right" ]] && printf ' (Current)' )|layout:external-right
External mode: preferred$( [[ "$current_mode" == "preferred" ]] && printf ' (Current)' )|mode:preferred
External mode: 1920x1080@143.98$( [[ "$current_mode" == "1920x1080@143.98" ]] && printf ' (Current)' )|mode:1920x1080@143.98
External mode: 3840x2160@60$( [[ "$current_mode" == "3840x2160@60" ]] && printf ' (Current)' )|mode:3840x2160@60
Reset monitor state file|reset
EOF
  )"
  [[ -n "$choice" ]] || exit 0
  action="${choice##*|}"

  case "$action" in
    recover)
      recover_outputs
      notify "Monitors" "Display rules reapplied"
      ;;
    layout:external-up)
      state_set layout external-up
      apply_state
      notify "Monitors" "External display placed above laptop"
      ;;
    layout:external-right)
      state_set layout external-right
      apply_state
      notify "Monitors" "External display placed to the right"
      ;;
    mode:preferred)
      state_set external_mode preferred
      apply_state
      notify "Monitors" "External mode set to preferred"
      ;;
    mode:1920x1080@143.98)
      state_set external_mode "1920x1080@143.98"
      apply_state
      notify "Monitors" "External mode set to 1080p144"
      ;;
    mode:3840x2160@60)
      state_set external_mode "3840x2160@60"
      apply_state
      notify "Monitors" "External mode set to 4K60"
      ;;
    reset)
      rm -f "$STATE_FILE"
      ensure_state
      apply_state
      notify "Monitors" "Monitor state reset to defaults"
      ;;
    *)
      exit 0
      ;;
  esac
}

case "${1:-menu}" in
  apply)
    apply_state
    ;;
  recover)
    recover_outputs
    ;;
  menu)
    show_menu
    ;;
  *)
    echo "Usage: monitor-control.sh [menu|apply|recover]" >&2
    exit 1
    ;;
esac
