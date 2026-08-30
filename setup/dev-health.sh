#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FULL=0
FIX=0
JSON_MODE=0
TMP_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/dev-health"
if ! mkdir -p "$TMP_DIR" 2>/dev/null; then
  TMP_DIR="/tmp/dev-health"
  mkdir -p "$TMP_DIR"
fi
JSON_FILE="$TMP_DIR/dev-health-json.$$"
trap 'rm -f "$JSON_FILE"' EXIT

usage() {
  cat <<USAGE
Usage: dev-health [--full] [--fix] [--json]

Fast local developer readiness check for this workstation.
  --full   Also run setup/weekly-health-check.sh for deep logs.
  --fix    Run safe repair actions where available.
  --json   Emit a machine-readable summary to stdout.
USAGE
}

while (($#)); do
  case "$1" in
    --full) FULL=1 ;;
    --fix) FIX=1 ;;
    --json) JSON_MODE=1 ;;
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

if [ "$JSON_MODE" -eq 1 ]; then
  exec 3>&1 1>&2
fi

warns=0
fails=0

record_json() {
  [ "$JSON_MODE" -eq 1 ] || return 0
  printf '%s\t%s\n' "$1" "$2" >>"$JSON_FILE"
}

json_print() {
  python3 - "$JSON_FILE" "$warns" "$fails" "$REPO_DIR" <<'PY'
import json
import sys
from collections import defaultdict
from pathlib import Path

path = Path(sys.argv[1])
warns = int(sys.argv[2])
fails = int(sys.argv[3])
repo = sys.argv[4]

sections = defaultdict(list)
if path.exists():
    for line in path.read_text().splitlines():
        if "\t" not in line:
            continue
        section, value = line.split("\t", 1)
        sections[section].append(value)

print(json.dumps({
    "repo": repo,
    "warnings": warns,
    "failures": fails,
    "sections": dict(sections),
}, indent=2))
PY
}

ok() {
  if [ "$JSON_MODE" -eq 1 ]; then
    printf 'OK    %s\n' "$*" >&2
  else
    printf 'OK    %s\n' "$*"
  fi
}
warn() {
  if [ "$JSON_MODE" -eq 1 ]; then
    printf 'WARN  %s\n' "$*" >&2
  else
    printf 'WARN  %s\n' "$*"
  fi
  warns=$((warns + 1))
}
fail() {
  if [ "$JSON_MODE" -eq 1 ]; then
    printf 'FAIL  %s\n' "$*" >&2
  else
    printf 'FAIL  %s\n' "$*"
  fi
  fails=$((fails + 1))
}
info() {
  if [ "$JSON_MODE" -eq 1 ]; then
    printf 'INFO  %s\n' "$*" >&2
  else
    printf 'INFO  %s\n' "$*"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

run_optional() {
  local label="$1" out_file
  shift
  out_file="$TMP_DIR/${label//[^A-Za-z0-9_.-]/_}.$$"
  if "$@" >"$out_file" 2>&1; then
    ok "$label"
    record_json guards "$label:ok"
  else
    warn "$label"
    record_json guards "$label:fail"
    if [ "$JSON_MODE" -eq 1 ]; then
      sed -n '1,12p' "$out_file" | sed 's/^/      /' >&2
    else
      sed -n '1,12p' "$out_file" | sed 's/^/      /'
    fi
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
  record_json repo "branch:${branch:-detached}"
  if git -C "$REPO_DIR" diff --quiet --ignore-submodules -- && git -C "$REPO_DIR" diff --cached --quiet --ignore-submodules --; then
    ok "tracked tree clean"
    record_json repo "clean:true"
  else
    warn "tracked tree has changes"
    record_json repo "clean:false"
    git -C "$REPO_DIR" status --short | sed -n '1,20p' | sed 's/^/      /'
  fi
else
  fail "not a git worktree"
  record_json repo "clean:false"
fi

section "Core Tools"
for tool in git rg jq zsh fzf tmux nvim code kitty; do
  if have "$tool"; then
    ok "$tool available"
    record_json core_tools "$tool:ok"
  else
    warn "$tool missing"
    record_json core_tools "$tool:missing"
  fi
done

for bridge in node npm npx pnpm desktop-launch code; do
  bridge_path="$HOME/.local/bin/$bridge"
  case "$bridge" in
    node | npm | npx) expected="$REPO_DIR/system/node-runtime" ;;
    *) expected="$REPO_DIR/system/$bridge" ;;
  esac
  if [ -L "$bridge_path" ] && [ "$(readlink -f "$bridge_path" 2>/dev/null || true)" = "$expected" ]; then
    ok "$bridge runtime link is repo-managed"
    record_json core_tools "$bridge-bridge:ok"
  else
    warn "$bridge runtime link is missing or overridden"
    record_json core_tools "$bridge-bridge:overridden"
  fi
done

section "Dotfiles Guardrails"
run_optional "settings doctor" "$REPO_DIR/hypr/scripts/settings/doctor.sh"
run_optional "stale-reference check" "$REPO_DIR/setup/check-stale-references.sh"
run_optional "keybind docs parity" "$REPO_DIR/setup/check-keybinds.sh"
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
    record_json desktop_runtime "provider:${provider}"
  else
    warn "Hyprland provider unknown"
    record_json desktop_runtime "provider:unknown"
  fi
else
  warn "hyprctl missing or not in Hyprland session"
  record_json desktop_runtime "hyprctl:missing"
fi

for svc in wayle xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk; do
  state="$(service_state "$svc")"
  case "$state" in
    active)
      ok "user service $svc active"
      record_json services "$svc:active"
      ;;
    inactive | failed | '')
      warn "user service $svc ${state:-unknown}"
      record_json services "$svc:${state:-unknown}"
      ;;
    *)
      info "user service $svc $state"
      record_json services "$svc:$state"
      ;;
  esac
done

if pgrep -af 'wl-paste --type text --watch .*cliphist store' >/dev/null 2>&1; then
  ok "cliphist text watcher running"
  record_json desktop_runtime "cliphist:text:running"
else
  warn "cliphist text watcher not detected"
  record_json desktop_runtime "cliphist:text:missing"
fi

section "Local AI / RAG"
LOCAL_AI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/local-ai"
if have local-ai-runtime; then
  local_ai_state="$TMP_DIR/local-ai-runtime.$$"
  local-ai-runtime status 2>"$local_ai_state" | sed -n '1,12p' | sed 's/^/      /' || warn "local-ai-runtime status failed"
  rm -f "$local_ai_state"
  record_json local_ai "local-ai-runtime:ok"
else
  warn "local-ai-runtime missing"
  record_json local_ai "local-ai-runtime:missing"
fi
if [ -f "$LOCAL_AI_DIR/current-model.env" ]; then
  ok "current-model.env present"
  record_json local_ai "current-model.env:present"
else
  warn "current-model.env missing"
  record_json local_ai "current-model.env:missing"
fi
if [ -f "$LOCAL_AI_DIR/rag.json" ]; then
  ok "rag.json present"
  record_json local_ai "rag.json:present"
else
  warn "rag.json missing"
  record_json local_ai "rag.json:missing"
fi
if curl -fsS --max-time 2 http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
  ok "local AI endpoint reachable"
  record_json local_ai "endpoint:reachable"
else
  warn "local AI endpoint unreachable at http://127.0.0.1:8080/v1/models"
  record_json local_ai "endpoint:unreachable"
fi
if have llama-swap-manager; then
  run_optional "llama-swap-manager status" llama-swap-manager status
else
  warn "llama-swap-manager missing"
  record_json local_ai "llama-swap-manager:missing"
fi
if have rag; then
  run_optional "rag doctor" rag doctor
else
  warn "rag CLI missing"
  record_json local_ai "rag:missing"
fi

section "Projects"
"$REPO_DIR/setup/project-profile.sh" status | sed 's/^/      /' || warn "project-profile status failed"
record_json projects "project-profile:checked"

section "Storage"
df -h / "$HOME" 2>/dev/null | sed 's/^/      /' || true
storage_status="ok"
while read -r _fs _sz _used _avail pct mount; do
  pct="${pct%%%}"
  if [ -n "$pct" ] && [ "$pct" -ge 90 ]; then
    fail "low disk space on $mount (${pct}%)"
    storage_status="low:${mount}:${pct}"
  fi
done < <(df -P / "$HOME" 2>/dev/null | awk 'NR>1')
record_json storage "$storage_status"

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
if [ "$JSON_MODE" -eq 1 ]; then
  json_print >&3
fi
if [ "$fails" -gt 0 ]; then
  exit 1
fi
exit 0
