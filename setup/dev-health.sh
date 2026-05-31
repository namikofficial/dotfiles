#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FULL=0
FIX=0
TMP_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/dev-health"
mkdir -p "$TMP_DIR"

usage() {
  cat <<USAGE
Usage: dev-health [--full] [--fix]

Fast local developer readiness check for this workstation.
  --full   Also run setup/weekly-health-check.sh for deep logs.
  --fix    Run safe repair actions where available.
USAGE
}

while (($#)); do
  case "$1" in
    --full) FULL=1 ;;
    --fix) FIX=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

warns=0
fails=0

ok() { printf 'OK    %s\n' "$*"; }
warn() {
  printf 'WARN  %s\n' "$*"
  warns=$((warns + 1))
}
fail() {
  printf 'FAIL  %s\n' "$*"
  fails=$((fails + 1))
}
info() { printf 'INFO  %s\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

run_optional() {
  local label="$1" out_file
  shift
  out_file="$TMP_DIR/${label//[^A-Za-z0-9_.-]/_}.$$"
  if "$@" >"$out_file" 2>&1; then
    ok "$label"
  else
    warn "$label"
    sed -n '1,12p' "$out_file" | sed 's/^/      /'
  fi
  rm -f "$out_file"
}

service_state() {
  local svc="$1"
  systemctl --user is-active "$svc" 2>/dev/null || true
}

section() { printf '\n## %s\n' "$1"; }

printf '=== Noxflow Dev Health ===\n'
printf 'Time: %s\n' "$(date '+%F %T %Z')"
printf 'Repo: %s\n' "$REPO_DIR"

section "Repo"
if git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git -C "$REPO_DIR" branch --show-current 2>/dev/null || true)"
  info "branch ${branch:-detached}"
  if git -C "$REPO_DIR" diff --quiet --ignore-submodules -- && git -C "$REPO_DIR" diff --cached --quiet --ignore-submodules --; then
    ok "tracked tree clean"
  else
    warn "tracked tree has changes"
    git -C "$REPO_DIR" status --short | sed -n '1,20p' | sed 's/^/      /'
  fi
else
  fail "not a git worktree"
fi

section "Core Tools"
for tool in git rg jq zsh fzf tmux nvim code kitty; do
  if have "$tool"; then ok "$tool available"; else warn "$tool missing"; fi
done

section "Dotfiles Guardrails"
run_optional "settings doctor" "$REPO_DIR/hypr/scripts/settings/doctor.sh"
run_optional "stale-reference check" "$REPO_DIR/setup/check-stale-references.sh"
if have shellcheck && have shfmt; then
  run_optional "shell lint/format check" "$REPO_DIR/setup/check-shell.sh"
else
  warn "shellcheck or shfmt missing; skipped shell lint"
fi

section "Desktop Runtime"
if have hyprctl; then
  provider="$("$REPO_DIR/hypr/scripts/hypr-reload-safe.sh" --probe 2>/dev/null || true)"
  if [ -n "$provider" ] && [ "$provider" != "unknown" ]; then
    ok "Hyprland provider: $provider"
  else
    warn "Hyprland provider unknown"
  fi
else
  warn "hyprctl missing or not in Hyprland session"
fi

for svc in wayle xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk; do
  state="$(service_state "$svc")"
  case "$state" in
    active) ok "user service $svc active" ;;
    inactive | failed | '') warn "user service $svc ${state:-unknown}" ;;
    *) info "user service $svc $state" ;;
  esac
done

if pgrep -af 'wl-paste --type text --watch .*cliphist store' >/dev/null 2>&1; then
  ok "cliphist text watcher running"
else
  warn "cliphist text watcher not detected"
fi

section "Local AI / RAG"
LOCAL_AI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/local-ai"
if have local-ai-runtime; then
  local_ai_state="$TMP_DIR/local-ai-runtime.$$"
  local-ai-runtime status 2>"$local_ai_state" | sed -n '1,12p' | sed 's/^/      /' || warn "local-ai-runtime status failed"
  rm -f "$local_ai_state"
else
  warn "local-ai-runtime missing"
fi
if [ -f "$LOCAL_AI_DIR/current-model.env" ]; then
  ok "current-model.env present"
else
  warn "current-model.env missing"
fi
if [ -f "$LOCAL_AI_DIR/rag.json" ]; then
  ok "rag.json present"
else
  warn "rag.json missing"
fi
if curl -fsS --max-time 2 http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
  ok "local AI endpoint reachable"
else
  warn "local AI endpoint unreachable at http://127.0.0.1:8080/v1/models"
fi
if have llama-swap-manager; then
  run_optional "llama-swap-manager status" llama-swap-manager status
else
  warn "llama-swap-manager missing"
fi
if have rag; then
  run_optional "rag doctor" rag doctor
else
  warn "rag CLI missing"
fi

section "Projects"
"$REPO_DIR/setup/project-profile.sh" status | sed 's/^/      /' || warn "project-profile status failed"

section "Storage"
df -h / "$HOME" 2>/dev/null | sed 's/^/      /' || true
while read -r _fs _sz _used _avail pct mount; do
  pct="${pct%%%}"
  if [ -n "$pct" ] && [ "$pct" -ge 90 ]; then
    fail "low disk space on $mount (${pct}%)"
  fi
done < <(df -P / "$HOME" 2>/dev/null | awk 'NR>1')

if [ "$FIX" -eq 1 ]; then
  section "Safe Repairs"
  if [ -x "$REPO_DIR/setup/normalize-links.sh" ]; then
    "$REPO_DIR/setup/normalize-links.sh" || warn "normalize-links failed"
  fi
  if [ -x "$REPO_DIR/hypr/scripts/panel-switch.sh" ]; then
    "$REPO_DIR/hypr/scripts/panel-switch.sh" show || warn "panel restore failed"
  fi
fi

if [ "$FULL" -eq 1 ]; then
  section "Full Weekly Health"
  "$REPO_DIR/setup/weekly-health-check.sh" || warn "weekly health check reported issues"
fi

section "Summary"
printf 'Warnings: %s\n' "$warns"
printf 'Failures: %s\n' "$fails"
if [ "$fails" -gt 0 ]; then
  exit 1
fi
exit 0
