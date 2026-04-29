#!/usr/bin/env bash
set -euo pipefail

last_ws=""

emit() {
  local ws="$1"
  jq -cn --arg text "󰍹 ${ws}" --arg tooltip "Active workspace: ${ws}" --arg class "active-workspace" \
    '{text:$text, tooltip:$tooltip, class:$class}'
}

read_active_ws() {
  local ws
  ws="$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)"
  if [[ -z "${ws}" ]]; then
    ws="?"
  fi
  printf '%s\n' "${ws}"
}

emit_if_changed() {
  local ws
  ws="$(read_active_ws)"
  if [[ "${ws}" != "${last_ws}" ]]; then
    emit "${ws}"
    last_ws="${ws}"
  fi
}

socket_path() {
  local sig runtime candidate
  sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
  runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

  if [[ -n "${sig}" ]]; then
    candidate="${runtime}/hypr/${sig}/.socket2.sock"
    if [[ -S "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  candidate="$(ls -1dt "${runtime}"/hypr/*/.socket2.sock 2>/dev/null | head -n1 || true)"
  if [[ -n "${candidate}" && -S "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  return 1
}

emit_if_changed

while :; do
  sock="$(socket_path || true)"
  if [[ -z "${sock}" ]]; then
    sleep 1
    emit_if_changed
    continue
  fi

  stdbuf -oL ncat -U "${sock}" 2>/dev/null | while IFS= read -r event; do
    case "${event}" in
      workspace\>\>*|workspacev2\>\>*|focusedmon\>\>*|activespecial\>\>*)
        emit_if_changed
        ;;
    esac
  done

  sleep 0.2
done
