#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/monitor-layout.json"
ROFI_THEME="$HOME/.config/rofi/actions.rasi"
INTERNAL_MONITOR="eDP-1"
LOG_LIB="$HOME/.config/hypr/scripts/lib/log.sh"

ensure_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  if [[ ! -s "$STATE_FILE" ]]; then
    cat > "$STATE_FILE" <<'EOF'
{"layout":"dynamic-up","external_mode":"preferred","external_scale":"1","internal_scale":"1","external_name":""}
EOF
  else
    local tmp
    tmp="$(mktemp)"
    jq '
      .layout = (.layout // "dynamic-up")
      | .external_mode = (.external_mode // "preferred")
      | .external_scale = (.external_scale // "1")
      | .internal_scale = (.internal_scale // "1")
      | .external_name = (.external_name // "")
      | del(.external_desc)
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
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

emit_event() {
  local sev="$1"
  local title="$2"
  local body="${3:-}"
  if [[ -x "$LOG_LIB" ]]; then
    "$LOG_LIB" --emit "$sev" monitor-control "$title" "$body" "" "" >/dev/null 2>&1 || true
  fi
}

detect_external_name() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  hyprctl monitors -j 2>/dev/null \
    | jq -r --arg internal "$INTERNAL_MONITOR" '
        [
          .[]
          | select(.name != $internal)
          | .name
        ] | sort | .[0] // empty
      ' \
    | sed -e '/^$/d'
}

resolve_external_name() {
  ensure_state

  local detected saved
  detected="$(detect_external_name || true)"
  if [[ -n "$detected" ]]; then
    state_set external_name "$detected"
    printf '%s\n' "$detected"
    return 0
  fi

  saved="$(state_get external_name)"
  if [[ "$saved" != "null" && -n "$saved" ]]; then
    printf '%s\n' "$saved"
  fi
}

all_connected_monitors() {
  hyprctl monitors -j 2>/dev/null \
    | jq -r '.[].name' \
    | sed -e '/^$/d' \
    | sort
}

first_connected_external() {
  hyprctl monitors -j 2>/dev/null \
    | jq -r --arg internal "$INTERNAL_MONITOR" '
        [
          .[]
          | select(.name != $internal)
          | .name
        ] | sort | .[0] // empty
      ' \
    | sed -e '/^$/d'
}

apply_workspace_routing() {
  local external ws
  external="$(first_connected_external || true)"

  # Keep primary desk workspaces on the laptop panel.
  for ws in 1 2 3 4 5; do
    hyprctl dispatch moveworkspacetomonitor "$ws" "$INTERNAL_MONITOR" >/dev/null 2>&1 || true
  done

  # Route 6-10 to the first currently connected external display.
  if [[ -n "$external" ]]; then
    for ws in 6 7 8 9 10; do
      hyprctl dispatch moveworkspacetomonitor "$ws" "$external" >/dev/null 2>&1 || true
    done
  else
    for ws in 6 7 8 9 10; do
      hyprctl dispatch moveworkspacetomonitor "$ws" "$INTERNAL_MONITOR" >/dev/null 2>&1 || true
    done
  fi
}

position_row_no_overlap() {
  local internal_scale external_scale external_mode
  internal_scale="$(state_get internal_scale)"
  external_scale="$(state_get external_scale)"
  external_mode="$(state_get external_mode)"

  mapfile -t connected < <(all_connected_monitors)
  if [[ "${#connected[@]}" -eq 0 ]]; then
    return 0
  fi

  local ordered=()
  local have_internal=0
  for mon in "${connected[@]}"; do
    if [[ "$mon" == "$INTERNAL_MONITOR" ]]; then
      have_internal=1
      break
    fi
  done

  if [[ "$have_internal" -eq 1 ]]; then
    ordered+=("$INTERNAL_MONITOR")
    for mon in "${connected[@]}"; do
      [[ "$mon" == "$INTERNAL_MONITOR" ]] && continue
      ordered+=("$mon")
    done
  else
    ordered=("${connected[@]}")
  fi

  local x=0
  local mon mode scale width step
  for mon in "${ordered[@]}"; do
    if [[ "$mon" == "$INTERNAL_MONITOR" ]]; then
      mode="preferred"
      scale="$internal_scale"
    else
      mode="$external_mode"
      scale="$external_scale"
    fi

    hyprctl keyword monitor "$mon,$mode,${x}x0,$scale" >/dev/null || \
      hyprctl keyword monitor "$mon,preferred,${x}x0,$scale" >/dev/null || true

    width="$(hyprctl monitors -j 2>/dev/null | jq -r --arg mon "$mon" '.[] | select(.name == $mon) | .width // 1920' | head -n1)"
    step="$(awk -v w="${width:-1920}" -v s="${scale:-1}" 'BEGIN { if (s <= 0) s = 1; v = int((w / s) + 0.5); if (v < 640) v = 640; print v }')"
    x=$((x + step))
  done
}

position_stack_up_no_overlap() {
  local internal_scale external_scale external_mode
  internal_scale="$(state_get internal_scale)"
  external_scale="$(state_get external_scale)"
  external_mode="$(state_get external_mode)"

  mapfile -t connected < <(all_connected_monitors)
  if [[ "${#connected[@]}" -eq 0 ]]; then
    return 0
  fi

  local ordered=()
  local have_internal=0
  for mon in "${connected[@]}"; do
    if [[ "$mon" == "$INTERNAL_MONITOR" ]]; then
      have_internal=1
      break
    fi
  done

  if [[ "$have_internal" -eq 1 ]]; then
    ordered+=("$INTERNAL_MONITOR")
    for mon in "${connected[@]}"; do
      [[ "$mon" == "$INTERNAL_MONITOR" ]] && continue
      ordered+=("$mon")
    done
  else
    ordered=("${connected[@]}")
  fi

  local mon mode scale height step y

  # Anchor internal panel at 0x0 when present.
  if [[ "$have_internal" -eq 1 ]]; then
    hyprctl keyword monitor "$INTERNAL_MONITOR,preferred,0x0,$internal_scale" >/dev/null || true
    y=0
    for mon in "${ordered[@]}"; do
      [[ "$mon" == "$INTERNAL_MONITOR" ]] && continue

      mode="$external_mode"
      scale="$external_scale"
      height="$(hyprctl monitors -j 2>/dev/null | jq -r --arg mon "$mon" '.[] | select(.name == $mon) | .height // 1080' | head -n1)"
      step="$(awk -v h="${height:-1080}" -v s="${scale:-1}" 'BEGIN { if (s <= 0) s = 1; v = int((h / s) + 0.5); if (v < 480) v = 480; print v }')"
      y=$((y - step))

      hyprctl keyword monitor "$mon,$mode,0x${y},$scale" >/dev/null || \
        hyprctl keyword monitor "$mon,preferred,0x${y},$scale" >/dev/null || true
    done
    return 0
  fi

  # No internal panel detected: stack from top to bottom.
  y=0
  for mon in "${ordered[@]}"; do
    mode="$external_mode"
    scale="$external_scale"
    hyprctl keyword monitor "$mon,$mode,0x${y},$scale" >/dev/null || \
      hyprctl keyword monitor "$mon,preferred,0x${y},$scale" >/dev/null || true

    height="$(hyprctl monitors -j 2>/dev/null | jq -r --arg mon "$mon" '.[] | select(.name == $mon) | .height // 1080' | head -n1)"
    step="$(awk -v h="${height:-1080}" -v s="${scale:-1}" 'BEGIN { if (s <= 0) s = 1; v = int((h / s) + 0.5); if (v < 480) v = 480; print v }')"
    y=$((y + step))
  done
}

disable_disconnected_outputs() {
  local path connector status
  for path in /sys/class/drm/card*-*/status; do
    [[ -e "$path" ]] || continue
    status="$(cat "$path" 2>/dev/null || true)"
    [[ "$status" == "disconnected" ]] || continue
    connector="${path%/status}"
    connector="${connector##*/}"
    connector="${connector#*-}"
    hyprctl keyword monitor "$connector,disable" >/dev/null 2>&1 || true
  done
}

apply_state() {
  ensure_state

  local layout external_mode external_scale internal_scale external_name
  layout="$(state_get layout)"
  external_mode="$(state_get external_mode)"
  external_scale="$(state_get external_scale)"
  internal_scale="$(state_get internal_scale)"
  external_name="$(resolve_external_name)"

  disable_disconnected_outputs

  if [[ "$layout" == "dynamic-right" ]]; then
    position_row_no_overlap
    apply_workspace_routing
    hyprctl keyword monitor ",preferred,auto-right,1" >/dev/null || true
    hyprctl dispatch dpms on >/dev/null || true
    emit_event info "Monitor layout applied" "Layout=dynamic-right"
    return 0
  fi

  if [[ "$layout" == "dynamic-up" ]]; then
    position_stack_up_no_overlap
    apply_workspace_routing
    hyprctl keyword monitor ",preferred,auto-up,1" >/dev/null || true
    hyprctl dispatch dpms on >/dev/null || true
    emit_event info "Monitor layout applied" "Layout=dynamic-up"
    return 0
  fi

  if [[ -z "$external_name" ]]; then
    hyprctl keyword monitor "$INTERNAL_MONITOR,preferred,0x0,$internal_scale" >/dev/null || true
    apply_workspace_routing
    hyprctl keyword monitor ",preferred,auto-right,1" >/dev/null || true
    hyprctl dispatch dpms on >/dev/null || true
    emit_event info "Monitor layout applied" "Internal-only fallback active"
    return 0
  fi

  case "$layout" in
    external-up)
      hyprctl keyword monitor "$external_name,$external_mode,0x0,$external_scale" >/dev/null
      hyprctl keyword monitor "$INTERNAL_MONITOR,preferred,auto-down,$internal_scale" >/dev/null
      ;;
    external-right)
      hyprctl keyword monitor "$INTERNAL_MONITOR,preferred,0x0,$internal_scale" >/dev/null
      hyprctl keyword monitor "$external_name,$external_mode,auto-right,$external_scale" >/dev/null
      ;;
    external-left)
      hyprctl keyword monitor "$external_name,$external_mode,0x0,$external_scale" >/dev/null
      hyprctl keyword monitor "$INTERNAL_MONITOR,preferred,auto-right,$internal_scale" >/dev/null
      ;;
    external-down)
      hyprctl keyword monitor "$INTERNAL_MONITOR,preferred,0x0,$internal_scale" >/dev/null
      hyprctl keyword monitor "$external_name,$external_mode,auto-down,$external_scale" >/dev/null
      ;;
    *)
      echo "unknown layout: $layout" >&2
      exit 1
      ;;
  esac

  apply_workspace_routing
  hyprctl keyword monitor ",preferred,auto-right,1" >/dev/null || true
  hyprctl dispatch dpms on >/dev/null || true
  emit_event info "Monitor layout applied" "Layout=$layout mode=$external_mode"
}

recover_outputs() {
  apply_state
  hyprctl dispatch dpms on >/dev/null || true
}

show_menu() {
  ensure_state
  local current_layout current_mode current_external choice action
  current_layout="$(state_get layout)"
  current_mode="$(state_get external_mode)"
  current_external="$(resolve_external_name)"

  choice="$(
    cat <<EOF | rofi -dmenu -i -p "Monitor Control" -theme "$ROFI_THEME" || true
Recover displays|recover
External: ${current_external}|noop
Dynamic auto layout up (recommended)$( [[ "$current_layout" == "dynamic-up" ]] && printf ' (Current)' )|layout:dynamic-up
Dynamic auto layout (recommended)$( [[ "$current_layout" == "dynamic-right" ]] && printf ' (Current)' )|layout:dynamic-right
External above laptop$( [[ "$current_layout" == "external-up" ]] && printf ' (Current)' )|layout:external-up
External right of laptop$( [[ "$current_layout" == "external-right" ]] && printf ' (Current)' )|layout:external-right
External left of laptop$( [[ "$current_layout" == "external-left" ]] && printf ' (Current)' )|layout:external-left
External below laptop$( [[ "$current_layout" == "external-down" ]] && printf ' (Current)' )|layout:external-down
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
    layout:dynamic-right)
      state_set layout dynamic-right
      apply_state
      notify "Monitors" "Dynamic auto layout enabled"
      ;;
    layout:dynamic-up)
      state_set layout dynamic-up
      apply_state
      notify "Monitors" "Dynamic auto layout up enabled"
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
    layout:external-left)
      state_set layout external-left
      apply_state
      notify "Monitors" "External display placed to the left"
      ;;
    layout:external-down)
      state_set layout external-down
      apply_state
      notify "Monitors" "External display placed below laptop"
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
    noop)
      exit 0
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
