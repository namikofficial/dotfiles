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
# docs/archive/ is excluded throughout: it is historical by definition and its
# whole purpose is to keep superseded claims findable. shell-diagnostics is
# excluded because detecting a stray retired daemon is exactly its job — it
# greps for them on purpose. The two shell-repair documents are dated audit
# records that say what was running on 2026-07-29.
check_absent "retired panel stack" 'waybar|swaync' \
  README.md SHELL_CHEATSHEET.md docs setup hypr/scripts aliases.zsh aliases.local.zsh \
  -g '!setup/check-stale-references.sh' \
  -g '!setup/remove-legacy-shell-packages.sh' \
  -g '!docs/archive/**' \
  -g '!docs/NOXFLOW_REPAIR_PLAN.md' \
  -g '!docs/shell-repair-audit.md' \
  -g '!docs/shell-repair-validation.md' \
  -g '!hypr/scripts/shell-diagnostics'
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

section "Archived NoxOrigin Projects"
# workspace (NoxCRM), nox-billings and nox-tickets moved to archive-code; the
# live repos are noxorigin/{noxorigin,noxorigin-docs,noxorigin-website}.
check_absent "archived noxorigin project" 'noxorigin/(workspace|nox-billings|nox-tickets)|nox-(billings|tickets)-(edit|env-edit|up|log|emulator)\b' \
  README.md SHELL_CHEATSHEET.md docs setup hypr/scripts android aliases.zsh aliases.local.zsh configs/claude \
  -g '!setup/check-stale-references.sh'

section "Superseded NoxFlow Plans"
# PLAN.md, PLAN_v2.md, theplan.md and OPENCODE_TASK.md were archived to
# docs/archive/ on 2026-10-09 and replaced by docs/NOXFLOW_REPAIR_PLAN.md.
# Several of their claims were checked and found false — most importantly
# "most power/media/lock buttons are rejected by noxd", which live probes
# disproved. Guidance, skills and docs must not point at them as current.
check_absent "superseded plan used as current guidance" \
  '(?<![_[:alnum:]])(PLAN\.md|PLAN_v2\.md|theplan\.md|OPENCODE_TASK\.md)' \
  README.md SHELL_CHEATSHEET.md AGENTS.md setup configs ai \
  -g '!setup/check-stale-references.sh' \
  -g '!setup/remove-legacy-shell-packages.sh' \
  -g '!**/skills/task-board/SKILL.md' \
  -g '!**/skills/task-execute/SKILL.md' \
  -P

# Those two skills are exempt above because they are required to *name* the
# archived files in order to tell an agent not to use them. Everything else that
# mentions one is treated as guidance and must be updated.

# The archive must state that it is not current, so an agent that lands there
# does not follow it as a plan.
if [ -f docs/archive/README.md ] && rg -q 'superseded|not current|history' docs/archive/README.md; then
  printf 'OK    docs/archive/README.md marks the archive as historical\n'
else
  printf 'FAIL  docs/archive/README.md must say the archive is historical\n'
  fail=1
fi

section "VS Code SOPS Settings"
vscode_settings="code/vscode-user-settings.json"
if jq -e '.["sops.enabled"] == true
    and (.["sops.defaults.ageKeyFile"] | type == "string")
    and .["files.associations"]["*.env.sops"] == "dotenv"' "$vscode_settings" >/dev/null 2>&1; then
  printf 'OK    %s keeps the SOPS decrypt-on-open settings\n' "$vscode_settings"
else
  printf 'FAIL  %s is missing sops.enabled, sops.defaults.ageKeyFile or the *.env.sops -> dotenv association\n' "$vscode_settings"
  fail=1
fi

section "Script Executability"
check_missing_executable

section "Result"
if [ "$fail" -eq 0 ]; then
  echo "PASS stale-reference guardrails"
else
  echo "FAIL stale-reference guardrails"
fi

exit "$fail"
