#!/usr/bin/env sh
set -eu

mode="${1:-menu}"
rofi_theme="${HOME}/.config/rofi/actions.rasi"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "AI Helper" "$1" "${2:-}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    notify "Missing command" "$1 is required"
    exit 1
  }
}

urlencode() {
  python - "$1" <<'PY'
import sys
from urllib.parse import quote_plus
print(quote_plus(sys.argv[1]))
PY
}

open_chat() {
  prompt_text="$1"
  encoded="$(urlencode "$prompt_text")"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "https://chat.openai.com/?q=${encoded}" >/dev/null 2>&1 &
  else
    notify "Unable to open browser" "xdg-open is missing"
    exit 1
  fi
}

rofi_input() {
  prompt="$1"
  if [ -f "$rofi_theme" ]; then
    rofi -dmenu -i -p "$prompt" -theme "$rofi_theme"
  else
    rofi -dmenu -i -p "$prompt"
  fi
}

clipboard_text() {
  if command -v wl-paste >/dev/null 2>&1; then
    wl-paste -n --type text 2>/dev/null | head -c 1800
  fi
}

ask_mode() {
  require_cmd rofi
  question="$(rofi_input 'Ask AI')"
  [ -n "$question" ] || exit 0
  open_chat "Answer this clearly and concisely:\n${question}"
}

clip_mode() {
  text="$(clipboard_text)"
  [ -n "$text" ] || {
    notify "Clipboard is empty" "Copy text first, then try Fn+3."
    exit 1
  }
  open_chat "Summarize the text and list next actions:\n\n${text}"
}

shell_mode() {
  require_cmd rofi
  task="$(rofi_input 'Describe shell task')"
  [ -n "$task" ] || exit 0
  open_chat "Write an Arch Linux shell command for this task, then explain it briefly:\n${task}"
}

debug_mode() {
  text="$(clipboard_text)"
  if [ -z "$text" ]; then
    require_cmd rofi
    text="$(rofi_input 'Paste error summary')"
  fi
  [ -n "$text" ] || exit 0
  open_chat "Debug this issue. Explain likely root cause, checks, and fix steps:\n\n${text}"
}

menu_mode() {
  require_cmd rofi
  choice="$(
    rofi -dmenu -i -p 'AI Helper' -theme "$rofi_theme" <<'MENU'
󰚩  Ask AI
󱞁  Summarize Clipboard
󰘦  Generate Shell Command
󰁨  Debug Clipboard Error
MENU
  )"

  case "$choice" in
    "󰚩  Ask AI") ask_mode ;;
    "󱞁  Summarize Clipboard") clip_mode ;;
    "󰘦  Generate Shell Command") shell_mode ;;
    "󰁨  Debug Clipboard Error") debug_mode ;;
    *) exit 0 ;;
  esac
}

case "$mode" in
  ask) ask_mode ;;
  clip) clip_mode ;;
  shell) shell_mode ;;
  debug) debug_mode ;;
  menu) menu_mode ;;
  *)
    echo "usage: $0 [ask|clip|shell|debug|menu]" >&2
    exit 1
    ;;
esac
