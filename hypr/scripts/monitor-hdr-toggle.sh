#!/usr/bin/env bash
set -euo pipefail

target_desc="LG Electronics LG ULTRAGEAR 0x0000A0D5"
monitor_rule_base="desc:${target_desc},preferred,auto-right,1,bitdepth,10"

current_preset="$(
  hyprctl monitors all 2>/dev/null |
    awk -v target="$target_desc" '
      $0 ~ ("description: " target) { in_target=1; next }
      /^Monitor / && in_target { exit }
      in_target && /colorManagementPreset:/ { print $2; exit }
    '
)"

if [[ -z "$current_preset" ]]; then
  echo "target monitor not found" >&2
  exit 1
fi

if [[ "$current_preset" == "hdr" || "$current_preset" == "hdredid" ]]; then
  new_mode="cm,srgb"
  notify_title="LG HDR"
  notify_body="Desktop SDR mode enabled"
else
  new_mode="cm,hdr,sdrbrightness,1.0,sdrsaturation,1.0"
  notify_title="LG HDR"
  notify_body="Forced HDR mode enabled"
fi

hyprctl keyword monitor "${monitor_rule_base},${new_mode}" >/dev/null

if command -v notify-send >/dev/null 2>&1; then
  notify-send "$notify_title" "$notify_body"
fi
