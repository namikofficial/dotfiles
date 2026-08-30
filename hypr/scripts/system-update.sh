#!/usr/bin/env bash
set -euo pipefail

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "System Update" "$1" "${2:-}"
}

log_file="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow/system-update.log"
launch_log="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow/system-update-launch.log"
mkdir -p "$(dirname "$log_file")"
printf '%s system-update invoked\n' "$(date -Iseconds)" >>"$log_file"

run_update() {
  if command -v paru >/dev/null 2>&1; then
    paru -Syu
    return
  fi
  if command -v yay >/dev/null 2>&1; then
    yay -Syu
    return
  fi
  sudo pacman -Syu
}

if [ "${1:-}" = "run" ]; then
  run_update
  exit 0
fi

open_in_terminal() {
  local mode="${1:-launch}"
  local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  local ack_dir="$runtime_dir/noxflow"
  local ack_file="$ack_dir/system-update-launch-$$.ack"
  local child="$HOME/.config/hypr/scripts/system-update-terminal.sh"
  local terminal

  mkdir -p "$ack_dir"
  rm -f "$ack_file"

  for terminal in kitty foot alacritty wezterm; do
    command -v "$terminal" >/dev/null 2>&1 || continue
    command -v hyprctl >/dev/null 2>&1 || break

    terminal_path="$(command -v "$terminal")"
    command_string="env NOXFLOW_UPDATE_LAUNCH_ACK=$ack_file"
    if [ "$mode" = "probe" ]; then
      command_string+=" NOXFLOW_UPDATE_PROBE=1"
    fi
    command_string+=" $terminal_path -e $child"
    lua_command="${command_string//\\/\\\\}"
    lua_command="${lua_command//\"/\\\"}"

    {
      printf '%s launching via Hyprland: %s\n' "$(date -Iseconds)" "$command_string"
      hyprctl eval "hl.dispatch(hl.dsp.exec_cmd(\"$lua_command\"))"
    } >>"$launch_log" 2>&1 || continue

    for _attempt in {1..40}; do
      if [ -e "$ack_file" ]; then
        rm -f "$ack_file"
        printf 'launched\n'
        return 0
      fi
      sleep 0.1
    done
    printf '%s terminal did not acknowledge launch: %s\n' "$(date -Iseconds)" "$terminal" >>"$launch_log"
  done

  rm -f "$ack_file"
  return 1
}

if open_in_terminal "${1:-launch}"; then
  exit 0
fi

notify "Update terminal failed to open" "See $launch_log"
printf 'Update terminal failed to open\n' >&2
exit 1
