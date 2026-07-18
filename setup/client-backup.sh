#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nox-backup"
CONFIG_FILE="$CONFIG_DIR/client-backup.conf"
DEFAULT_REPOSITORY="$HOME/syncthing/client-backups/restic"
REPOSITORIES=(
  "$HOME/Documents/code/noxorigin/nox-billings"
  "$HOME/Documents/code/noxorigin/workspace"
  "$HOME/Documents/code/trackMe"
)

usage() {
  cat <<'USAGE'
Usage: client-backup {run|verify|status|init-config}

Configuration lives outside Git at ~/.config/nox-backup/client-backup.conf.
The config defines BACKUP_TARGETS as project:environment:ssh-host entries. Each
remote host must expose /usr/local/libexec/client-db-backup-dump, which writes
one PostgreSQL custom-format dump to stdout for its allow-listed target.
USAGE
}

init_config() {
  mkdir -p "$CONFIG_DIR"
  if [ -e "$CONFIG_FILE" ]; then
    echo "config already exists: $CONFIG_FILE" >&2
    return 1
  fi
  install -m 600 "$(dirname "$0")/client-backup.conf.example" "$CONFIG_FILE"
  echo "Created $CONFIG_FILE. Set the backup hosts and password file before running a backup."
}

load_config() {
  local credential_password_file="${RESTIC_PASSWORD_FILE:-}"
  [ -r "$CONFIG_FILE" ] || {
    echo "missing backup configuration: $CONFIG_FILE (run: client-backup init-config)" >&2
    exit 2
  }
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  if [ -n "$credential_password_file" ]; then
    RESTIC_PASSWORD_FILE="$credential_password_file"
  fi
  RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-$DEFAULT_REPOSITORY}"
  : "${RESTIC_PASSWORD_FILE:?RESTIC_PASSWORD_FILE must point to a mode-600 password file}"
  [ -r "$RESTIC_PASSWORD_FILE" ] || { echo "unreadable RESTIC_PASSWORD_FILE" >&2; exit 2; }
  case "$(stat -c '%a' "$RESTIC_PASSWORD_FILE")" in
    400|600) ;;
    *) echo "RESTIC_PASSWORD_FILE must have mode 600 (or 400 when supplied by systemd)" >&2; exit 2 ;;
  esac
  : "${BACKUP_TARGETS:?BACKUP_TARGETS must contain project:environment:ssh-host entries}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "required command not found: $1" >&2; exit 2; }
}

verify() {
  load_config
  require_command restic
  require_command ssh
  [ -d "${RESTIC_REPOSITORY%/*}" ] || { echo "backup parent is missing: ${RESTIC_REPOSITORY%/*}" >&2; exit 1; }
  for repo in "${REPOSITORIES[@]}"; do [ -d "$repo/.git" ] || { echo "not a git repository: $repo" >&2; exit 1; }; done
  local target project environment host
  for target in "${BACKUP_TARGETS[@]}"; do
    IFS=: read -r project environment host <<<"$target"
    [ -n "$project" ] && [ -n "$environment" ] && [ -n "$host" ] || { echo "invalid target: $target" >&2; exit 2; }
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" /usr/local/libexec/client-db-backup-dump --check "$project" "$environment"
  done
  echo "backup configuration is ready"
}

run() {
  load_config
  require_command restic
  require_command ssh
  verify
  local temp target project environment host dump
  temp="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/client-backup.XXXXXX")"
  trap 'rm -rf "$temp"' EXIT
  for target in "${BACKUP_TARGETS[@]}"; do
    IFS=: read -r project environment host <<<"$target"
    dump="$temp/$project-$environment.dump"
    ssh -o BatchMode=yes "$host" /usr/local/libexec/client-db-backup-dump "$project" "$environment" >"$dump"
    [ -s "$dump" ] || { echo "empty remote dump: $target" >&2; exit 1; }
  done
  export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE
  if ! restic snapshots >/dev/null 2>&1; then restic init; fi
  restic backup --one-file-system --exclude-file "$(dirname "$0")/client-backup.exclude" --tag repositories "${REPOSITORIES[@]}"
  restic backup --tag databases "$temp"
  restic forget --keep-daily 30 --prune
  restic check
}

status() {
  load_config
  require_command restic
  export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE
  restic snapshots --latest 1
}

case "${1:-}" in
  run) run ;;
  verify) verify ;;
  status) status ;;
  init-config) init_config ;;
  -h|--help|help|'') usage ;;
  *) usage >&2; exit 2 ;;
esac
