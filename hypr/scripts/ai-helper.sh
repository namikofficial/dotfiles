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

run_codex_terminal() {
  title="$1"
  prompt_text="$2"

  if ! command -v codex >/dev/null 2>&1 || ! command -v kitty >/dev/null 2>&1; then
    return 1
  fi

  # shellcheck disable=SC2016
  AI_PROMPT="$prompt_text" \
  kitty --title "$title" -e sh -lc '
    printf "Noxflow AI helper\n\n"
    codex exec --sandbox workspace-write --ask-for-approval on-request "$AI_PROMPT" || true
    printf "\nPress Enter to close..."
    read -r _
  ' >/dev/null 2>&1 &

  return 0
}

run_ai() {
  title="$1"
  prompt_text="$2"

  if run_codex_terminal "$title" "$prompt_text"; then
    return 0
  fi

  # Fallback path when codex/kitty is unavailable.
  open_chat "$prompt_text"
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
    wl-paste -n --type text 2>/dev/null | head -c 3500
  fi
}

project_context() {
  _cache="${HOME}/.cache/kage/project-current.json"
  if command -v jq >/dev/null 2>&1 && [ -s "$_cache" ]; then
    _pname=$(jq -r '.name     // ""' "$_cache" 2>/dev/null)
    _pbranch=$(jq -r '.branch   // ""' "$_cache" 2>/dev/null)
    _plang=$(jq -r '.framework // ""' "$_cache" 2>/dev/null)
    _ppath=$(jq -r '.path     // ""' "$_cache" 2>/dev/null)
    _pmod=$(jq -r '.modified  // 0'  "$_cache" 2>/dev/null)
    _pstaged=$(jq -r '.staged   // 0'  "$_cache" 2>/dev/null)
    if [ -n "$_pname" ]; then
      printf 'Active project context:\n  name: %s\n  branch: %s\n  lang/framework: %s\n  path: %s\n  modified: %s | staged: %s\n\n' \
        "$_pname" "$_pbranch" "$_plang" "$_ppath" "$_pmod" "$_pstaged"
    fi
  fi
}

raw_mode() {
  require_cmd rofi
  prompt="$(rofi_input 'Prompt AI')"
  [ -n "$prompt" ] || exit 0

  run_ai "AI Prompt" "$prompt"
}

ask_mode() {
  require_cmd rofi
  question="$(rofi_input 'Ask AI')"
  [ -n "$question" ] || exit 0

  _ctx="$(project_context)"
  run_ai "AI Ask" "${_ctx}You are a direct, practical assistant. Answer clearly and concisely. Prefer the shortest response that is still complete. Call out assumptions instead of hiding them.\n\nQuestion:\n${question}"
}

clip_mode() {
  text="$(clipboard_text)"
  [ -n "$text" ] || {
    notify "Clipboard is empty" "Copy text first, then try Fn+3."
    exit 1
  }

  run_ai "AI Clipboard Summary" "Summarize the clipboard text for quick reuse. Return:\n1. one-sentence summary\n2. key points\n3. action items\n4. ambiguities or risks\n\nClipboard:\n${text}"
}

shell_mode() {
  require_cmd rofi
  task="$(rofi_input 'Describe shell task')"
  [ -n "$task" ] || exit 0

  _ctx="$(project_context)"
  run_ai "AI Shell Command" "${_ctx}You are a senior Arch Linux and Hyprland operator. Generate the minimum safe commands needed to solve the task. Prefer commands that are easy to verify and roll back. Include any required packages, validation steps, and caveats for destructive actions.\n\nTask:\n${task}"
}

debug_mode() {
  text="$(clipboard_text)"
  if [ -z "$text" ]; then
    require_cmd rofi
    text="$(rofi_input 'Paste error summary')"
  fi
  [ -n "$text" ] || exit 0

  _ctx="$(project_context)"
  run_ai "AI Debug" "${_ctx}You are a pragmatic debugger. Diagnose the issue from the pasted text. Return:\n1. likely root causes ordered by probability\n2. checks to run next\n3. a minimal fix plan\n4. what evidence would confirm or rule out the guess\n\nInput:\n${text}"
}

menu_mode() {
  require_cmd rofi
  choice="$(
    rofi -dmenu -i -p 'AI Helper' -theme "$rofi_theme" <<'MENU'
Freeform Prompt
Ask AI
Summarize Clipboard
Generate Shell Command
Debug Clipboard Error
MENU
  )"

  case "$choice" in
    'Freeform Prompt') raw_mode ;;
    'Ask AI') ask_mode ;;
    'Summarize Clipboard') clip_mode ;;
    'Generate Shell Command') shell_mode ;;
    'Debug Clipboard Error') debug_mode ;;
    *) exit 0 ;;
  esac
}

case "$mode" in
  raw) raw_mode ;;
  ask) ask_mode ;;
  clip) clip_mode ;;
  shell) shell_mode ;;
  debug) debug_mode ;;
  menu) menu_mode ;;
  *)
    echo "usage: $0 [raw|ask|clip|shell|debug|menu]" >&2
    exit 1
    ;;
esac
