#!/usr/bin/env bash
set -euo pipefail

profiles=(dotfiles noxcrm nox-billings nox-tickets wellvantage trackme)

path_for() {
  case "$1" in
    dotfiles) printf '%s\n' "$HOME/Documents/code/dotfiles" ;;
    noxcrm) printf '%s\n' "$HOME/Documents/code/workspace" ;;
    nox-billings) printf '%s\n' "$HOME/Documents/code/nox-billings" ;;
    nox-tickets) printf '%s\n' "$HOME/Documents/code/nox-tickets" ;;
    wellvantage) printf '%s\n' "$HOME/Documents/code/WellVantage" ;;
    trackme) printf '%s\n' "$HOME/Documents/code/trackMe" ;;
    *) return 1 ;;
  esac
}

check_cmd_for() {
  case "$1" in
    dotfiles) printf '%s\n' 'setup/dev-health.sh' ;;
    noxcrm) printf '%s\n' 'just lint' ;;
    nox-billings) printf '%s\n' 'pnpm verify' ;;
    nox-tickets) printf '%s\n' 'pnpm lint && pnpm typecheck' ;;
    wellvantage) printf '%s\n' 'pnpm lint && pnpm build' ;;
    trackme) printf '%s\n' 'pnpm typecheck' ;;
    *) return 1 ;;
  esac
}

dev_cmd_for() {
  local profile="$1" pane="$2"
  case "$profile:$pane" in
    nox-billings:api) printf '%s\n' 'just api' ;;
    nox-billings:web) printf '%s\n' 'just web' ;;
    nox-billings:mobile) printf '%s\n' 'just mobile' ;;
    nox-billings:logs) printf '%s\n' 'just logs' ;;
    noxcrm:api) printf '%s\n' 'just up' ;;
    noxcrm:web) printf '%s\n' 'just web-dev' ;;
    noxcrm:mobile) printf '%s\n' 'just mobile-dev' ;;
    noxcrm:logs) printf '%s\n' 'just logs' ;;
    trackme:api) printf '%s\n' 'just api' ;;
    trackme:web) printf '%s\n' 'just web' ;;
    trackme:mobile) printf '%s\n' 'just mobile' ;;
    trackme:logs) printf '%s\n' 'just logs' ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<USAGE
Usage: project-profile <command> [profile]

Commands:
  list                 List known project profiles
  status               Show path/git state for all profiles
  path <profile>       Print profile path
  cd <profile>         Print a cd command for eval usage
  edit <profile>       Open the profile in VS Code
  shell <profile>      Open a project-rooted Kitty shell
  tmux <profile>       Attach/create a project tmux session
  dev <profile>        Attach/create the project's API, web, mobile, and logs layout
  check <profile>      Run the profile's default verification command
  launch <profile>     Open editor and project tmux shell
USAGE
}

ensure_dev_layout() {
  local profile="$1" path="$2" session window pane command
  session="$profile"
  window="dev"

  if ! dev_cmd_for "$profile" api >/dev/null; then
    echo "no development layout for profile: $profile" >&2
    return 2
  fi

  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -n "$window" -c "$path"
  elif ! tmux list-windows -t "$session" -F '#W' | grep -Fxq "$window"; then
    tmux new-window -d -t "$session" -n "$window" -c "$path"
  else
    return 0
  fi

  tmux split-window -d -h -t "$session:$window" -c "$path"
  tmux split-window -d -v -t "$session:$window.0" -c "$path"
  tmux split-window -d -v -t "$session:$window.2" -c "$path"
  tmux select-layout -t "$session:$window" tiled

  for pane in api web mobile logs; do
    case "$pane" in
      api) target=0 ;;
      web) target=1 ;;
      mobile) target=2 ;;
      logs) target=3 ;;
    esac
    command="$(dev_cmd_for "$profile" "$pane")"
    tmux select-pane -t "$session:$window.$target" -T "$pane"
    tmux send-keys -t "$session:$window.$target" "cd $(printf '%q' "$path") && $command" Enter
  done
}

open_tmux() {
  local session="$1" window="${2:-}"
  if [ -n "$window" ]; then
    tmux select-window -t "$session:$window"
  fi
  if [ -n "${TMUX:-}" ]; then
    exec tmux switch-client -t "$session${window:+:$window}"
  fi
  exec tmux attach-session -t "$session${window:+:$window}"
}

require_profile() {
  local profile="${1:-}"
  [ -n "$profile" ] || {
    echo "profile required" >&2
    usage >&2
    exit 2
  }
  path_for "$profile" >/dev/null || {
    echo "unknown profile: $profile" >&2
    exit 2
  }
}

profile_status() {
  local profile="$1" path branch dirty marker
  path="$(path_for "$profile")"
  if [ ! -d "$path" ]; then
    printf '%-12s missing %s\n' "$profile" "$path"
    return 0
  fi
  if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch="$(git -C "$path" branch --show-current 2>/dev/null || printf 'detached')"
    if git -C "$path" diff --quiet --ignore-submodules -- && git -C "$path" diff --cached --quiet --ignore-submodules --; then
      dirty="clean"
    else
      dirty="dirty"
    fi
    marker="$branch/$dirty"
  else
    marker="not-git"
  fi
  printf '%-12s %-18s %s\n' "$profile" "$marker" "$path"
}

cmd="${1:-list}"
profile="${2:-}"

case "$cmd" in
  list)
    printf '%s\n' "${profiles[@]}"
    ;;
  status)
    for p in "${profiles[@]}"; do profile_status "$p"; done
    ;;
  path)
    require_profile "$profile"
    path_for "$profile"
    ;;
  cd)
    require_profile "$profile"
    printf 'cd %q\n' "$(path_for "$profile")"
    ;;
  edit)
    require_profile "$profile"
    exec code "$(path_for "$profile")"
    ;;
  shell)
    require_profile "$profile"
    path="$(path_for "$profile")"
    printf -v quoted_path '%q' "$path"
    exec kitty --title "$profile" -e zsh -lc "cd $quoted_path && exec zsh"
    ;;
  tmux)
    require_profile "$profile"
    path="$(path_for "$profile")"
    if dev_cmd_for "$profile" api >/dev/null; then
      ensure_dev_layout "$profile" "$path"
      open_tmux "$profile" dev
    fi
    exec tmux new-session -A -s "$profile" -c "$path"
    ;;
  dev)
    require_profile "$profile"
    path="$(path_for "$profile")"
    ensure_dev_layout "$profile" "$path"
    open_tmux "$profile" dev
    ;;
  check)
    require_profile "$profile"
    path="$(path_for "$profile")"
    check_cmd="$(check_cmd_for "$profile")"
    cd "$path"
    exec zsh -lc "$check_cmd"
    ;;
  launch)
    require_profile "$profile"
    path="$(path_for "$profile")"
    code "$path" >/dev/null 2>&1 &
    if dev_cmd_for "$profile" api >/dev/null; then
      ensure_dev_layout "$profile" "$path"
      exec kitty --title "$profile" -e tmux attach-session -t "$profile:dev"
    fi
    exec kitty --title "$profile" -e tmux new-session -A -s "$profile" -c "$path"
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    echo "unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
