#!/usr/bin/env bash
set -euo pipefail

if ((EUID != 0)); then
  echo "Run with sudo: sudo $0" >&2
  exit 2
fi

target=/etc/vconsole.conf
backup_dir=/var/lib/noxflow-workstation/backups/console-font
mkdir -p "$backup_dir"

if [[ -e "$target" || -L "$target" ]]; then
  backup="$backup_dir/vconsole.conf.$(date +%Y%m%d-%H%M%S)"
  cp -a "$target" "$backup"
  echo "backed up $target to $backup"
fi

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT
if [[ -f "$target" ]]; then
  grep -Ev '^(FONT|FONT_MAP|KEYMAP)=' "$target" >"$tmp_file" || true
fi
printf '%s\n' 'KEYMAP=us' 'FONT=ter-v24n' >>"$tmp_file"
install -m 0644 "$tmp_file" "$target"
echo "configured $target with Terminus ter-v24n"
echo "Note: raw TTYs use this fallback; graphical terminals use JetBrainsMono Nerd Font."
