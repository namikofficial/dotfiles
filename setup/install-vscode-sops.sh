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
command -v code >/dev/null 2>&1 || fail "code command is not installed or is not on PATH"
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

install_extension() {
  local extension_id="$1"
  if ! code --list-extensions | grep -Fxq "$extension_id"; then
    printf 'Installing VS Code extension %s\n' "$extension_id"
    code --install-extension "$extension_id" --force >/dev/null
  fi
}

install_extension "signageos.signageos-vscode-sops"
install_extension "mikestead.dotenv"

code --list-extensions | grep -Fxq "signageos.signageos-vscode-sops" ||
  fail "SOPS VS Code extension is not installed"
code --list-extensions | grep -Fxq "mikestead.dotenv" ||
  fail "dotenv VS Code extension is not installed"

printf 'VS Code SOPS settings installed.\n'
printf 'Settings: %s\n' "$live_settings"
printf 'Age key: %s (mode %s)\n' "$age_key_file" "$(stat -c '%a' "$age_key_file")"
printf 'Extensions: signageos.signageos-vscode-sops, mikestead.dotenv\n'
printf 'Reload VS Code, then open encrypted .env.sops files and save normally.\n'
