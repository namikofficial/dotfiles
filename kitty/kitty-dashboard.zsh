kitty__trim_text() {
  emulate -L zsh
  local text="${1:-}"
  local limit="${2:-72}"

  if (( ${#text} <= limit )); then
    printf '%s' "$text"
    return 0
  fi

  printf '%s...' "${text[1,$((limit - 3))]}"
}

kitty__current_repo_root() {
  emulate -L zsh
  git rev-parse --show-toplevel 2>/dev/null || true
}

kitty__current_branch() {
  emulate -L zsh
  local branch
  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ -n "$branch" ]; then
    printf '%s' "$branch"
    return 0
  fi

  branch="$(git rev-parse --short HEAD 2>/dev/null || true)"
  printf '%s' "$branch"
}

kitty__shell_context() {
  emulate -L zsh
  local cwd repo_root repo_name branch rel_path
  cwd="${PWD/#$HOME/~}"
  repo_root="$(kitty__current_repo_root)"

  if [ -n "$repo_root" ]; then
    repo_name="${repo_root:t}"
    branch="$(kitty__current_branch)"
    rel_path="${PWD#${repo_root}/}"
    if [ "$rel_path" = "$PWD" ]; then
      rel_path="."
    fi
    if [ "$rel_path" = "." ]; then
      printf '%s:%s' "$repo_name" "$branch"
    else
      printf '%s:%s %s' "$repo_name" "$branch" "${rel_path/#$HOME/~}"
    fi
    return 0
  fi

  printf '%s' "$cwd"
}

kitty__set_title() {
  emulate -L zsh
  local title="${1:-}"
  title="${title//$'\a'/ }"
  title="${title//$'\r'/ }"
  title="${title//$'\n'/ }"
  printf '\033]2;%s\a' "$title"
}

kitty_dashboard() {
  emulate -L zsh
  local context repo_root branch cwd
  context="$(kitty__shell_context)"
  cwd="${PWD/#$HOME/~}"
  repo_root="$(kitty__current_repo_root)"
  branch=""
  [ -n "$repo_root" ] && branch="$(kitty__current_branch)"

  printf '\n'
  printf '╭────────────────────────────────────────────╮\n'
  printf '│ Kitty Dashboard                           │\n'
  printf '╰────────────────────────────────────────────╯\n'
  printf '\n'
  printf '  context : %s\n' "$context"
  printf '  cwd     : %s\n' "$cwd"
  if [ -n "$repo_root" ]; then
    printf '  repo    : %s\n' "${repo_root:t}"
    printf '  branch  : %s\n' "$branch"
  fi

  if command -v fastfetch >/dev/null 2>&1; then
    printf '\n'
    fastfetch --logo none
  else
    printf '\n'
    printf '  system  : %s\n' "$(uname -srmo 2>/dev/null || uname -a)"
    printf '  uptime  : %s\n' "$(uptime 2>/dev/null | sed 's/^.*up //')"
  fi

  printf '\n'
  printf '  quick actions\n'
  printf '    Ctrl+Shift+D  dashboard\n'
  printf '    Ctrl+Shift+1  scratch shell\n'
  printf '    Ctrl+Shift+2  live logs\n'
  printf '    Ctrl+Shift+3  repo client\n'
  printf '    Ctrl+Shift+4  AI session\n'
  printf '    Ctrl+Shift+Y  clipboard picker\n'
  printf '\n'
}

kitty_dashboard_maybe_show() {
  emulate -L zsh
  [[ -o interactive ]] || return 0
  [[ -n "${KITTY_WINDOW_ID:-}" || "${TERM:-}" == xterm-kitty ]] || return 0
  [[ "${NOXFLOW_KITTY_DASHBOARD:-0}" == "1" ]] || return 0
  [[ -n "${NOXFLOW_KITTY_DASHBOARD_SHOWN:-}" ]] && return 0

  export NOXFLOW_KITTY_DASHBOARD_SHOWN=1
  kitty_dashboard
}

kitty_update_title_precmd() {
  emulate -L zsh
  [[ -o interactive ]] || return 0
  [[ -n "${KITTY_WINDOW_ID:-}" || "${TERM:-}" == xterm-kitty ]] || return 0
  kitty__set_title "$(kitty__shell_context)"
}

kitty_update_title_preexec() {
  emulate -L zsh
  local cmd
  cmd="$(kitty__trim_text "${1:-}" 56)"
  [[ -n "$cmd" ]] || return 0
  [[ -n "${KITTY_WINDOW_ID:-}" || "${TERM:-}" == xterm-kitty ]] || return 0
  kitty__set_title "$(kitty__shell_context) > $cmd"
}

kitty_app_logs() {
  emulate -L zsh
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -f --output=short-precise --no-pager --no-hostname -p 0..6
  else
    printf 'journalctl not available\n'
  fi
  exec zsh -i
}

kitty_app_repo() {
  emulate -L zsh
  if command -v lazygit >/dev/null 2>&1; then
    lazygit
  else
    git status -sb 2>/dev/null || printf 'Not inside a git repo\n'
  fi
  exec zsh -i
}

kitty_app_ai() {
  emulate -L zsh
  if command -v codex >/dev/null 2>&1; then
    codex
  else
    printf 'codex not available on PATH\n'
  fi
  exec zsh -i
}

kitty_clipboard_picker() {
  emulate -L zsh
  if ! command -v cliphist >/dev/null 2>&1 || ! command -v fzf >/dev/null 2>&1 || ! command -v wl-copy >/dev/null 2>&1; then
    printf 'clipboard picker needs cliphist, fzf, and wl-copy\n'
    exec zsh -i
  fi

  local selection
  selection="$(cliphist list | fzf --prompt='Clipboard> ' --height=60% --border --reverse || true)"
  if [ -n "$selection" ]; then
    printf '%s' "$selection" | cliphist decode | wl-copy
    printf 'clipboard entry copied\n'
  fi
  exec zsh -i
}
