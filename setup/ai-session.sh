#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ai-session.sh [--dry-run] [--explain] {opencode|codex} [tool args...]

Optional Codex overlay:
  AI_SESSION_PROFILE=design|notes
  AI_SESSION_NO_PROFILE=1       do not add an overlay; preserve normal Codex config

OpenCode uses the MCP profiles declared per server in its canonical config.
This launcher does not classify tasks, select agents, or delegate work.
EOF
}

dry_run=0
explain=0
while (($#)); do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --explain)
      explain=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) break ;;
  esac
done

tool="${1:-}"
shift || true
case "$tool" in opencode | codex) ;; *)
  usage >&2
  exit 2
  ;;
esac
command -v "$tool" >/dev/null 2>&1 || {
  printf 'ai-session: %s is not installed or not on PATH\n' "$tool" >&2
  exit 127
}

profile="${AI_SESSION_PROFILE:-}"
if [[ -n "$profile" ]]; then
  if [[ "$tool" != codex ]]; then
    printf 'ai-session: AI_SESSION_PROFILE applies only to Codex; OpenCode profiles are configured per MCP server\n' >&2
    exit 2
  fi
  case "$profile" in design | notes) ;; *)
    printf 'ai-session: unsupported Codex profile %s (use design or notes)\n' "$profile" >&2
    exit 2
    ;;
  esac
fi

has_profile_arg=0
for arg in "$@"; do
  [[ "$arg" == --profile=* || "$arg" == --profile || "$arg" == -p ]] && has_profile_arg=1
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
repo_name="$(basename "${repo_root:-$PWD}")"
profile_state=default
if [[ "$tool" == codex && "$has_profile_arg" == 1 ]]; then
  profile_state=cli-explicit
elif [[ "$tool" == codex && -n "$profile" && "${AI_SESSION_NO_PROFILE:-0}" != 1 ]]; then
  profile_state="$profile"
elif [[ "${AI_SESSION_NO_PROFILE:-0}" == 1 ]]; then
  profile_state=disabled
fi

printf 'ai-session: tool=%s repo=%s profile=%s routing=direct\n' "$tool" "$repo_name" "$profile_state" >&2
if ((explain)); then
  printf 'ai-session: repo_root=%s\n' "${repo_root:-unknown}" >&2
  printf 'ai-session: task classification=none; agent selection=none; delegation=none\n' >&2
fi
if ((dry_run)); then exit 0; fi

if [[ "$tool" == codex && -n "$profile" && "$has_profile_arg" == 0 && "${AI_SESSION_NO_PROFILE:-0}" != 1 ]]; then
  exec codex --profile "$profile" "$@"
fi
exec "$tool" "$@"
