#!/usr/bin/env bash
set -euo pipefail

start_dir="${1:-$PWD}"

resolve_dir() {
  local dir="$1"
  if [ -d "$dir" ]; then
    (cd "$dir" 2>/dev/null && pwd) || printf '%s\n' "$HOME"
    return 0
  fi
  printf '%s\n' "$HOME"
}

find_root() {
  local dir="$1" root
  root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$root" ]; then
    printf '%s\n' "$root"
    return 0
  fi
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/justfile" ] || [ -f "$dir/Justfile" ] || [ -f "$dir/package.json" ] || [ -d "$dir/logs" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  printf '%s\n' "$start_dir"
}

has_just_recipe() {
  local root="$1" recipe="$2"
  local justfile="$root/justfile"
  command -v just >/dev/null 2>&1 || return 1
  [ -f "$justfile" ] || justfile="$root/Justfile"
  [ -f "$justfile" ] || return 1
  just --justfile "$justfile" --summary 2>/dev/null | tr ' ' '\n' | grep -qx "$recipe"
}

run_package_logs() {
  local root="$1"
  local script
  [ -f "$root/package.json" ] || return 1
  jq -e '.scripts.logs // .scripts.log' "$root/package.json" >/dev/null 2>&1 || return 1
  script="$(jq -r 'if .scripts.logs then "logs" else "log" end' "$root/package.json")"
  cd "$root"
  if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
    exec pnpm run "$script"
  fi
  if [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
    exec yarn "$script"
  fi
  if command -v npm >/dev/null 2>&1; then
    exec npm run "$script"
  fi
  return 1
}

tail_project_files() {
  local root="$1"
  [ -d "$root/logs" ] || return 1
  mapfile -t files < <(find "$root/logs" -maxdepth 2 -type f \( -name '*.log' -o -name '*.jsonl' -o -name '*.out' \) -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk '{ $1=""; sub(/^ /, ""); print }' | sed -n '1,8p')
  [ "${#files[@]}" -gt 0 ] || return 1
  if command -v multitail >/dev/null 2>&1 && [ "${#files[@]}" -gt 1 ]; then
    exec multitail "${files[@]}"
  fi
  exec tail -n 160 -F "${files[@]}"
}

run_compose_logs() {
  local root="$1"
  [ -f "$root/docker-compose.yml" ] || [ -f "$root/docker-compose.yaml" ] || [ -f "$root/compose.yml" ] || [ -f "$root/compose.yaml" ] || return 1
  command -v docker >/dev/null 2>&1 || return 1
  cd "$root"
  exec docker compose logs -f --tail=160
}

dir="$(resolve_dir "$start_dir")"
root="$(find_root "$dir")"

printf 'Project logs\n'
printf 'context: %s\n' "$dir"
printf 'root:    %s\n\n' "$root"

if has_just_recipe "$root" logs; then
  cd "$root"
  exec just logs
fi

run_package_logs "$root" || true
tail_project_files "$root" || true
run_compose_logs "$root" || true

printf 'No project log source found. Falling back to user journal.\n\n'
exec journalctl --user -f --no-hostname --no-pager
