#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      cat <<'USAGE'
Usage: install-vscode-development.sh [--dry-run]
Installs the managed VS Code development extensions.
USAGE
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

command -v code >/dev/null 2>&1 || {
  printf 'ERROR: code command is not installed or is not on PATH\n' >&2
  exit 1
}

extensions=(
  rust-lang.rust-analyzer
  timonwong.shellcheck
  redhat.vscode-yaml
  tamasfe.even-better-toml
  ms-azuretools.vscode-docker
  eamodio.gitlens
  usernamehw.errorlens
  yzhang.markdown-all-in-one
)

for extension in "${extensions[@]}"; do
  if code --list-extensions | grep -Fxq "$extension"; then
    printf 'ok   %s\n' "$extension"
  elif ((DRY_RUN)); then
    printf '[dry-run] install %s\n' "$extension"
  else
    printf 'installing %s\n' "$extension"
    code --install-extension "$extension" --force >/dev/null
  fi
done

printf 'VS Code development extensions are ready. Reload the window if VS Code is open.\n'
