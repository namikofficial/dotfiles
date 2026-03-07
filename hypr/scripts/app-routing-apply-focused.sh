#!/usr/bin/env bash
set -euo pipefail

rules_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/app-routing.generated.json"
if [[ ! -f "$rules_file" ]]; then
  notify-send -a "App Routing" "No routing rules" "Run settings apply first."
  exit 0
fi

if ! command -v hyprctl >/dev/null 2>&1; then
  exit 0
fi

active_class="$(hyprctl -j activewindow 2>/dev/null | jq -r '.class // empty')"
active_title="$(hyprctl -j activewindow 2>/dev/null | jq -r '.title // empty')"
[[ -n "$active_class" ]] || exit 0

rule="$(jq -r --arg cls "$active_class" --arg title "$active_title" '.rules[] | select((.app|ascii_downcase)==($cls|ascii_downcase) or (.app|ascii_downcase)==($title|ascii_downcase)) | @base64' "$rules_file" | head -n1 || true)"
[[ -n "$rule" ]] || {
  notify-send -a "App Routing" "No rule matched" "$active_class"
  exit 0
}

decode() { echo "$rule" | base64 -d | jq -r "$1"; }
route="$(decode '.route')"
workspace="$(decode '.workspace')"
sink="$(decode '.audio_sink')"

if [[ "$route" == "mute" ]]; then
  notify-send -a "App Routing" "Muted by routing" "$active_class"
  exit 0
fi

if [[ -n "$workspace" ]]; then
  hyprctl dispatch movetoworkspacesilent "$workspace" >/dev/null 2>&1 || true
fi

if [[ "$sink" != "default" ]] && command -v pactl >/dev/null 2>&1; then
  while IFS= read -r input_id; do
    [[ -n "$input_id" ]] || continue
    pactl move-sink-input "$input_id" "$sink" >/dev/null 2>&1 || true
  done < <(pactl list sink-inputs short | awk -v cls="$active_class" '$0 ~ cls {print $1}')
fi

notify-send -a "App Routing" "Applied" "$active_class -> $workspace ($sink)"
