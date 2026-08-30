#!/usr/bin/env bash
set -euo pipefail

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODE_ROOT="${CODE_ROOT:-$HOME/Documents/code}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

projects=(
  "$CODE_ROOT/trackMe"
  "$CODE_ROOT/noxorigin/nox-billings"
  "$CODE_ROOT/noxorigin/noxorigin-website"
  "$CODE_ROOT/noxorigin/workspace"
  "$CODE_ROOT/noxplay"
  "$CODE_ROOT/noxplate"
  "$CODE_ROOT/noxflow-dojo"
  "$CODE_ROOT/noxloops"
)

for project in "${projects[@]}"; do
  [ -d "$project" ] || continue
  if [ "$APPLY" -eq 0 ]; then
    printf 'WOULD CONFIGURE %s\n' "$project"
    continue
  fi
  mkdir -p "$project/scripts"
  cp "$DOTFILES_ROOT/scripts/verify" "$project/scripts/verify"
  cp "$DOTFILES_ROOT/scripts/verify-fast" "$project/scripts/verify-fast"
  cp "$DOTFILES_ROOT/scripts/verify-affected" "$project/scripts/verify-affected"
  cp "$DOTFILES_ROOT/scripts/verify-full" "$project/scripts/verify-full"
  chmod +x "$project/scripts/verify"
  chmod +x "$project/scripts/verify-fast" "$project/scripts/verify-affected" "$project/scripts/verify-full"
  if ! rg -q '^\.ai/$' "$project/.gitignore" 2>/dev/null; then
    printf '\n.ai/\n' >>"$project/.gitignore"
  fi
  printf 'CONFIGURED %s/scripts/verify\n' "$project"
done

if [ "$APPLY" -eq 0 ]; then
  printf '%s\n' 'Dry run only. Re-run with --apply to install adapters; no dependencies are installed.'
fi
