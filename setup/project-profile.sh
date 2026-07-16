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
  check <profile>      Run the profile's default verification command
  launch <profile>     Open editor and project tmux shell
USAGE
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
    exec tmux new-session -A -s "$profile" -c "$(path_for "$profile")"
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
