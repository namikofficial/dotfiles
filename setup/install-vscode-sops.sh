#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_dir="$(cd -- "$script_dir/.." && pwd -P)"
managed_settings="$repo_dir/code/vscode-user-settings.json"
code_user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
live_settings="$code_user_dir/settings.json"
age_key_file="$repo_dir/private/scripts/noxorigin/sops/age/keys.txt"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

command -v sops >/dev/null 2>&1 || fail "sops is not installed or is not on PATH"
[[ -f "$managed_settings" ]] || fail "managed settings file is missing: $managed_settings"
[[ -f "$age_key_file" ]] || fail "age key file is missing: $age_key_file"
[[ -r "$age_key_file" ]] || fail "age key file is not readable: $age_key_file"

mkdir -p "$code_user_dir"

if [[ -e "$live_settings" || -L "$live_settings" ]]; then
  current_target="$(readlink -f "$live_settings" 2>/dev/null || true)"
  managed_target="$(readlink -f "$managed_settings")"
  if [[ "$current_target" != "$managed_target" ]]; then
    backup="$code_user_dir/settings.json.backup.$(date -u +%Y%m%dT%H%M%SZ)"
    mv -- "$live_settings" "$backup"
    printf 'Backed up existing VS Code settings to %s\n' "$backup"
  fi
fi

if [[ ! -e "$live_settings" && ! -L "$live_settings" ]]; then
  ln -s -- "$managed_settings" "$live_settings"
fi

chmod 600 "$age_key_file"

printf 'VS Code SOPS settings installed.\n'
printf 'Settings: %s\n' "$live_settings"
printf 'Age key: %s (mode %s)\n' "$age_key_file" "$(stat -c '%a' "$age_key_file")"
printf 'Open encrypted .sops files directly in VS Code and save normally.\n'
