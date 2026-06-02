#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_DIR"

fail=0

section() {
  printf '\n## %s\n' "$1"
}

check_absent() {
  local label="$1"
  local pattern="$2"
  shift 2
  local tmp
  tmp="$(mktemp)"
  if rg -n -i "$pattern" "$@" >"$tmp" 2>/dev/null; then
    printf 'FAIL  stale %s references found\n' "$label"
    sed -n '1,80p' "$tmp"
    fail=1
  else
    printf 'OK    no stale %s references\n' "$label"
  fi
  rm -f "$tmp"
}

check_missing_executable() {
  local file
  while IFS= read -r file; do
    head -n1 "$file" | rg -q '^#!' || continue
    case "$file" in
      */*-common.sh | */lib/*.sh) continue ;;
    esac
    [ -x "$file" ] || {
      printf 'FAIL  script is not executable: %s\n' "$file"
      fail=1
    }
  done < <(find setup hypr/scripts system -type f -name '*.sh' -print)
}

section "Retired Desktop Stack"
check_absent "retired panel stack" 'waybar|swaync' \
  README.md SHELL_CHEATSHEET.md docs setup hypr/scripts aliases.zsh aliases.local.zsh \
  -g '!setup/check-stale-references.sh' \
  -g '!setup/remove-legacy-shell-packages.sh'
check_absent "retired power stack" 'tlp|tlp-stat' \
  README.md SHELL_CHEATSHEET.md docs setup hypr/scripts aliases.zsh aliases.local.zsh \
  -g '!setup/check-stale-references.sh' \
  -g '!setup/remove-legacy-shell-packages.sh'

section "Retired Local AI Paths"
check_absent "old local AI manager" 'llm-manager|127\.0\.0\.1:8000|port-8000' \
  README.md SHELL_CHEATSHEET.md docs setup hypr/scripts aliases.zsh aliases.local.zsh \
  -g '!setup/check-stale-references.sh' \
  -g '!setup/install-local-llm-stack.sh' \
  -g '!docs/LLM_SETUP.md' \
  -g '!docs/QUICK_START.md'

section "Script Executability"
check_missing_executable

section "Result"
if [ "$fail" -eq 0 ]; then
  echo "PASS stale-reference guardrails"
else
  echo "FAIL stale-reference guardrails"
fi

exit "$fail"
