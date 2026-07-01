#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/quick-actions.sh"

state_dir="$(noxflow_state_dir)"
pid_file="$state_dir/rofi-actions.pid"
other_pid_file="$state_dir/rofi-launcher.pid"
mkdir -p "$state_dir"

if noxflow_stop_if_running "$pid_file"; then
  exit 0
fi
noxflow_stop_if_running "$other_pid_file" || true

mapfile -t actions < <(noxflow_quick_action_labels)

hint_for_index() {
  case "$1" in
    0) echo 'Ctrl+1' ;;
    1) echo 'Ctrl+2' ;;
    2) echo 'Ctrl+3' ;;
    3) echo 'Ctrl+4' ;;
    4) echo 'Ctrl+5' ;;
    5) echo 'Ctrl+6' ;;
    6) echo 'Ctrl+7' ;;
    7) echo 'Ctrl+8' ;;
    8) echo 'Ctrl+9' ;;
    9) echo 'Ctrl+0' ;;
    *) echo '--' ;;
  esac
}

render_menu() {
  local action idx max_width=0 width hint

  for action in "${actions[@]}"; do
    [ "${#action}" -gt "$max_width" ] && max_width="${#action}"
  done

  width=$((max_width + 2))
  [ "$width" -lt 30 ] && width=30
  [ "$width" -gt 56 ] && width=56

  for idx in "${!actions[@]}"; do
    action="${actions[$idx]}"
    [ "${#action}" -gt 56 ] && action="${action:0:53}..."
    hint="$(hint_for_index "$idx")"
    printf '%-*s | quick | %7s\n' "$width" "$action" "$hint"
  done
}

set +e
choice_index="$(
  render_menu | rofi -dmenu -i \
    -no-show-icons \
    -p 'Quick Actions' \
    -mesg 'Ctrl+1..0 quick-launch rows 1-10' \
    -theme "$HOME/.config/rofi/actions.rasi" \
    -kb-select-1 'Control+1,Super+1' \
    -kb-select-2 'Control+2,Super+2' \
    -kb-select-3 'Control+3,Super+3' \
    -kb-select-4 'Control+4,Super+4' \
    -kb-select-5 'Control+5,Super+5' \
    -kb-select-6 'Control+6,Super+6' \
    -kb-select-7 'Control+7,Super+7' \
    -kb-select-8 'Control+8,Super+8' \
    -kb-select-9 'Control+9,Super+9' \
    -kb-select-10 'Control+0,Super+0' \
    -kb-cancel 'Escape,Control+g,Super+a,Super+slash,Super+Control+space' \
    -format 'i' \
    -pid "$pid_file"
)"
rofi_status=$?
set -e

rm -f "$pid_file"
[ "$rofi_status" -eq 0 ] || exit 0
[ -n "$choice_index" ] || exit 0
[[ "$choice_index" =~ ^[0-9]+$ ]] || exit 0

choice="${actions[$choice_index]:-}"
[ -n "$choice" ] || exit 0
noxflow_quick_action_run "$choice"
