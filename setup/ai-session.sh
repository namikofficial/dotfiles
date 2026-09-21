#!/usr/bin/env bash
set -euo pipefail

# Safe launcher for deliberate automatic routing. It never replaces `codex` or
# `opencode`; use `ai-session codex` or `ai-session opencode` explicitly.
tool="${1:-}"
shift || true
case "$tool" in codex|opencode) ;; *) printf 'usage: %s {codex|opencode} [args...]\n' "$0" >&2; exit 2 ;; esac

if [[ -n "${AI_SESSION_PROFILE:-}" ]]; then profile="$AI_SESSION_PROFILE"
elif [[ "$PWD" == */noxorigin/* || "$PWD" == */noxorigin || "$PWD" == */dotfiles/* || "$PWD" == */dotfiles ]]; then profile=dev
elif [[ "$PWD" == */notes/* || "$PWD" == */DocsVault/* ]]; then profile=notes
elif printf '%s\n' "$*" | grep -Eiq 'ui|ux|design|screenshot|figma|browser|web'; then profile=web
elif printf '%s\n' "$*" | grep -Eiq 'android|expo|react native|maestro|device|mobile'; then profile=mobile
else profile=minimal
fi

printf 'ai-session: tool=%s profile=%s (override with AI_SESSION_PROFILE)\n' "$tool" "$profile" >&2
if [[ "${AI_SESSION_DRY_RUN:-0}" == 1 ]]; then
  printf 'ai-session: dry-run command=%s\n' "$tool" >&2
  exit 0
fi
if [[ "$tool" == opencode ]]; then
  export NOXFLOW_MCP_PROFILE="$profile"
  exec opencode "$@"
fi

# Codex profiles are overlays. Only opt into design for web/UI work; otherwise
# normal config plus AGENTS.md routing remain in control. Explicit --profile wins.
if [[ "$profile" == web && " $* " != *" --profile "* && " $* " != *" -p "* ]]; then exec codex --profile design "$@"; fi
exec codex "$@"
