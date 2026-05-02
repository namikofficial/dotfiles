#!/usr/bin/env bash
# scratch-launchpad.sh — Super+Alt+` launcher pad
# Opens tools as floating kitty windows (large or small) or delegates
# to existing scripts.  Think: Windows Game Bar, but useful.
set -euo pipefail

THEME="$HOME/.config/rofi/launchpad.rasi"
LARGE_CLASS="noxflow-tool-large"
SMALL_CLASS="noxflow-tool-small"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Detect the cwd of the currently focused window (for git-aware tools).
focused_cwd() {
  local pid
  pid="$(hyprctl -j activewindow 2>/dev/null | python3 -c \
    "import json,sys; d=json.load(sys.stdin); print(d.get('pid',''))" 2>/dev/null || true)"
  if [ -n "$pid" ]; then
    readlink "/proc/${pid}/cwd" 2>/dev/null || echo "$HOME"
  else
    echo "$HOME"
  fi
}

git_root() {
  local d="$1"
  git -C "$d" rev-parse --show-toplevel 2>/dev/null || echo "$d"
}

float_large() {
  kitty --class "$LARGE_CLASS" --title "$1" -e "${@:2}" >/dev/null 2>&1 &
}

float_small() {
  kitty --class "$SMALL_CLASS" --title "$1" -e "${@:2}" >/dev/null 2>&1 &
}

# ── Entries ──────────────────────────────────────────────────────────────────
# Format:  DISPLAY_LINE\tACTION_KEY
# The tab-separated action key is hidden from rofi (using \0info) so
# it doesn't appear in the menu.

entries() {
  printf '%s\0info\x1f%s\n' \
    "󰌠  terminal scratchpad  Drop-down dev terminal"   "scratch-terminal" \
    "󰏚  ai scratchpad        Project AI workspace"     "scratch-ai" \
    "󰍹  notes scratchpad     Notes and clipboard"      "scratch-notes" \
    "󰇬  db scratchpad        SQL console"              "scratch-db" \
    "󰠩  browser devtools     Chrome/Chromium devtools" "scratch-browser" \
    "󰍛  btop                System monitor"           "btop"       \
    "󰚩  lazygit             Visual git client"        "lazygit"    \
    "󰆩  qalc                Calculator"               "qalc"       \
    "  Clipboard           Browse & paste history"    "clipboard"  \
    "  System logs         journalctl (live)"         "logs"       \
    "󰻠  fastfetch           System information"        "fastfetch"  \
    "  Python REPL         Interactive Python shell"  "python"     \
    "  JSON viewer         Explore JSON (python)"     "json"       \
    "󰌌  Hash / encode       md5, sha256, base64"       "hash"
}

# ── Rofi ─────────────────────────────────────────────────────────────────────

action="$(entries | rofi \
  -dmenu \
  -p "  Launch" \
  -theme "$THEME" \
  -format 'i' \
  2>/dev/null || true)"

[ -n "$action" ] || exit 0

# Map index → action key
mapfile -t keys < <(printf '%s\n' \
  scratch-terminal scratch-ai scratch-notes scratch-db scratch-browser btop lazygit qalc clipboard logs fastfetch python json hash)

key="${keys[$action]:-}"

# ── Dispatch ─────────────────────────────────────────────────────────────────

focused_cwd() {
  local pid
  pid="$(hyprctl -j activewindow 2>/dev/null | python3 -c \
    "import json,sys; d=json.load(sys.stdin); print(d.get('pid',''))" 2>/dev/null || true)"
  if [ -n "$pid" ]; then
    readlink "/proc/${pid}/cwd" 2>/dev/null || echo "$HOME"
  else
    echo "$HOME"
  fi
}

cwd="$(focused_cwd)"

case "$key" in
  lazygit)
    root="$(git_root "$cwd")"
    float_large "lazygit" lazygit -p "$root"
    ;;

  scratch-terminal)
    "$HOME/.config/hypr/scripts/scratchpad-manager.sh" terminal
    ;;

  scratch-ai)
    "$HOME/.config/hypr/scripts/scratchpad-manager.sh" ai
    ;;

  scratch-notes)
    "$HOME/.config/hypr/scripts/scratchpad-manager.sh" notes
    ;;

  scratch-db)
    "$HOME/.config/hypr/scripts/scratchpad-manager.sh" db
    ;;

  scratch-browser)
    "$HOME/.config/hypr/scripts/scratchpad-manager.sh" browser-devtools
    ;;

  btop)
    float_large "btop — system monitor" btop
    ;;

  yazi)
    float_large "yazi — files" yazi "$cwd"
    ;;

  gitlog)
    root="$(git_root "$cwd")"
    float_large "git log" bash -c \
      "git -C '$root' log --oneline --color --graph --decorate | \
       fzf --ansi --no-sort --reverse --tiebreak=index \
           --preview 'git -C \"$root\" show --stat --color {1}' \
           --preview-window=right:55% \
           --bind 'enter:execute(git -C \"$root\" show --color {1} | less -R)+abort'"
    ;;

  qalc)
    float_small "qalc — calculator" qalc
    ;;

  clipboard)
    # Delegate to the existing cliphist-rofi script.
    if [ -x "$HOME/.config/hypr/scripts/cliphist-rofi.sh" ]; then
      "$HOME/.config/hypr/scripts/cliphist-rofi.sh" &
    fi
    ;;

  logs)
    float_large "system logs" bash -c \
      "journalctl -f --output=short-precise --no-pager \
         --no-hostname -p 0..6 2>/dev/null | less -R +F"
    ;;

  fastfetch)
    float_small "fastfetch" bash -c \
      "command -v fastfetch >/dev/null && fastfetch || neofetch; read -r -p 'press enter…'"
    ;;

  python)
    float_small "Python REPL" python3 -q
    ;;

  json)
    float_small "JSON viewer" python3 -c "
import json, sys, pprint, pathlib, subprocess, tempfile, os

print('  JSON Viewer — paste JSON then Ctrl+D, or drag a .json file')
print()

data = sys.stdin.read().strip()
if not data:
    print('(no input)')
    sys.exit(0)
try:
    parsed = json.loads(data)
    pretty = json.dumps(parsed, indent=2, ensure_ascii=False)
    tmp = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False)
    tmp.write(pretty); tmp.close()
    subprocess.run(['less', '-R', tmp.name])
    os.unlink(tmp.name)
except json.JSONDecodeError as e:
    print(f'Invalid JSON: {e}')
    input('press enter…')
"
    ;;

  hash)
    float_small "Hash / encode" python3 -c "
import hashlib, base64, sys

print('  Hash & Encode — type/paste text then Enter')
print('  Commands: md5  sha1  sha256  sha512  b64enc  b64dec  exit')
print()
while True:
    try:
        raw = input('  text> ')
    except (EOFError, KeyboardInterrupt):
        break
    if raw.strip() in ('exit', 'quit', 'q'):
        break
    b = raw.encode()
    print(f'  md5      : {hashlib.md5(b).hexdigest()}')
    print(f'  sha1     : {hashlib.sha1(b).hexdigest()}')
    print(f'  sha256   : {hashlib.sha256(b).hexdigest()}')
    print(f'  sha512   : {hashlib.sha512(b).hexdigest()}')
    print(f'  base64   : {base64.b64encode(b).decode()}')
    try:
        print(f'  b64dec   : {base64.b64decode(raw.strip()).decode(\"utf-8\", errors=\"replace\")}')
    except Exception:
        pass
    print()
"
    ;;
esac
