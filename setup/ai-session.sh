#!/usr/bin/env bash
set -euo pipefail

# Bounded AI session router. It classifies context and reports its decision,
# but never edits files, changes a project, or silently delegates work.
usage() {
  cat <<'EOF'
Usage: ai-session.sh [--dry-run] [--explain] {opencode|codex} [tool args...]

Environment overrides:
  AI_SESSION_PROFILE=dev|web|mobile|notes|minimal
  AI_SESSION_TASK=ui|web|mobile|backend|database|security|docs|plan|explore|fix
  AI_SESSION_NO_PROFILE=1       do not add a Codex profile overlay
EOF
}

dry_run="${AI_SESSION_DRY_RUN:-0}"
explain=0
while (($#)); do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --explain) explain=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) break ;;
  esac
done

tool="${1:-}"
shift || true
case "$tool" in codex|opencode) ;; *) usage >&2; exit 2 ;; esac
command -v "$tool" >/dev/null 2>&1 || { printf 'ai-session: %s is not installed or not on PATH\n' "$tool" >&2; exit 127; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
repo_name="$(basename "${repo_root:-$PWD}")"
task_text="${AI_SESSION_TASK:-${*:-}}"

if [[ -n "${AI_SESSION_PROFILE:-}" ]]; then profile="$AI_SESSION_PROFILE"
elif [[ "$PWD" == */notes/* || "$PWD" == */DocsVault/* ]]; then profile=notes
elif printf '%s\n' "$task_text" | grep -Eiq 'android|expo|react[[:space:]-]?native|maestro|device|mobile|emulator'; then profile=mobile
elif printf '%s\n' "$task_text" | grep -Eiq 'ui|ux|design|screenshot|figma|browser|web|playwright|css|component'; then profile=web
elif [[ "$repo_root" == */noxorigin* || "$repo_root" == */dotfiles* || "$PWD" == */noxorigin* || "$PWD" == */dotfiles* ]]; then profile=dev
else profile=minimal
fi
case "$profile" in minimal|dev|web|mobile|notes) ;; *) printf 'ai-session: invalid profile %s\n' "$profile" >&2; exit 2 ;; esac

if [[ -n "${AI_SESSION_TASK:-}" ]]; then task="$AI_SESSION_TASK"
elif printf '%s\n' "$task_text" | grep -Eiq 'security|auth|permission|secret|tenant|rls'; then task=security
elif printf '%s\n' "$task_text" | grep -Eiq 'database|sql|migration|postgres|redis|transaction'; then task=database
elif printf '%s\n' "$task_text" | grep -Eiq 'android|expo|react[[:space:]-]?native|maestro|device|mobile'; then task=mobile
elif printf '%s\n' "$task_text" | grep -Eiq 'ui|ux|design|screenshot|figma|browser|web|css|component'; then task=ui
elif printf '%s\n' "$task_text" | grep -Eiq 'plan|design the approach|spec|proposal'; then task=plan
elif printf '%s\n' "$task_text" | grep -Eiq 'explore|where is|find|map|trace|explain'; then task=explore
elif printf '%s\n' "$task_text" | grep -Eiq 'docs|documentation|readme'; then task=docs
else task=implementation
fi

agent=build
case "$task" in
  plan) agent=plan ;; explore) agent=explore ;; ui) agent=ui-specialist ;;
  mobile) agent=android-verifier ;; security) agent=security-audit ;;
  web) agent=web-verifier ;; database|backend|implementation|docs) agent=build ;;
esac

printf 'ai-session: tool=%s repo=%s profile=%s task=%s agent=%s capability=codegraph\n' "$tool" "$repo_name" "$profile" "$task" "$agent" >&2
if ((explain)); then
  printf 'ai-session: repo_root=%s\n' "${repo_root:-unknown}" >&2
  printf 'ai-session: handoff=bounded-only; coordinator owns integration and final verification\n' >&2
  printf 'ai-session: state_changes=none before tool startup\n' >&2
fi
if ((dry_run)); then exit 0; fi

if [[ "$tool" == opencode ]]; then
  export NOXFLOW_MCP_PROFILE="$profile"
  exec opencode "$@"
fi

has_profile_arg=0
for arg in "$@"; do [[ "$arg" == --profile=* || "$arg" == --profile || "$arg" == -p ]] && has_profile_arg=1; done
if [[ "${AI_SESSION_NO_PROFILE:-0}" != 1 && "$has_profile_arg" == 0 ]]; then
  if [[ "$profile" == web ]]; then exec codex --profile design "$@"; fi
  if [[ "$profile" == notes ]]; then exec codex --profile notes "$@"; fi
fi
exec codex "$@"
