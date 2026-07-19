#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/workbench-runtime-env.sh"

mode="launch"
start_ai=0
focus_sidecar=1
restore_scratchpads=1
resume_session=1
selector=""
fallback_path=""

usage() {
  cat <<'USAGE'
Usage: project-resume [launch|restore] [options]

Options:
  --project <id|name|alias>  Resume an explicit registered project
  --ai, --start-ai           Include the AI scratchpad
  --no-sidecar               Do not restore Sidecar windows
  --no-scratchpads           Ignore manifest scratchpad preferences
  --no-session-resume        Do not resume the canonical shared session
  --fallback-path <path>     Explicit terminal-only fallback when no canonical project resolves

`launch` opens the manifest editor and tmux session. `restore` additionally
restores allowlisted manifest scratchpads. Canonical session mutations fail
closed; the offline fallback only opens local desktop tools.
USAGE
}

while (($#)); do
  case "$1" in
    --ai | --start-ai)
      start_ai=1
      ;;
    --no-sidecar)
      focus_sidecar=0
      ;;
    --no-scratchpads)
      restore_scratchpads=0
      ;;
    --no-session-resume)
      resume_session=0
      ;;
    --project)
      shift
      [ "$#" -gt 0 ] || {
        echo "--project requires a value" >&2
        exit 2
      }
      selector="$1"
      ;;
    --fallback-path)
      shift
      [ "$#" -gt 0 ] || {
        echo "--fallback-path requires a value" >&2
        exit 2
      }
      fallback_path="$1"
      ;;
    launch | restore)
      mode="$1"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown project-resume argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

workbench_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ai-workbench/project-status-v1.json"
registry_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ai-workbench/project-registry-v1.json"
project_profile="${NOXFLOW_PROJECT_PROFILE:-$(command -v project-profile 2>/dev/null || true)}"
[ -n "$project_profile" ] || project_profile="$HOME/Documents/code/dotfiles/setup/project-profile.sh"
scratchpad_manager="${NOXFLOW_SCRATCHPAD_MANAGER:-$SCRIPT_DIR/scratchpad-manager.sh}"
sidepanel="${NOXFLOW_SIDEPANEL:-$SCRIPT_DIR/sidepanel.sh}"

project_id=""
project_name=""
root=""
task_id=""
run_id=""
session_id=""
desktop_json=""
canonical=0

load_cached_work() {
  command -v jq >/dev/null 2>&1 || return 0
  [ -s "$workbench_cache" ] || return 0
  project_id="$(jq -r '.status.project.id // ""' "$workbench_cache" 2>/dev/null || true)"
  project_name="$(jq -r '.status.project.name // ""' "$workbench_cache" 2>/dev/null || true)"
  root="$(jq -r '.status.project.path // ""' "$workbench_cache" 2>/dev/null || true)"
  task_id="$(jq -r '.status.activeWork.taskId // ""' "$workbench_cache" 2>/dev/null || true)"
  run_id="$(jq -r '.status.activeWork.runId // ""' "$workbench_cache" 2>/dev/null || true)"
  session_id="$(jq -r '.status.activeWork.sessionId // ""' "$workbench_cache" 2>/dev/null || true)"
}

resolve_desktop() {
  local target="$selector"
  [ -x "$project_profile" ] || return 1
  if [ -z "$target" ]; then
    target="$project_id"
  fi
  if [ -z "$target" ] && command -v jq >/dev/null 2>&1 && [ -s "$registry_cache" ]; then
    target="$(jq -r '.selection.projectId // ""' "$registry_cache" 2>/dev/null || true)"
  fi
  [ -n "$target" ] || return 1
  desktop_json="$("$project_profile" desktop "$target" 2>/dev/null || true)"
  jq -e '.schemaVersion == 1 and (.project.id // "") != "" and (.project.path // "") != ""' \
    <<<"$desktop_json" >/dev/null 2>&1 || return 1
  root="$(jq -r '.project.path' <<<"$desktop_json")"
  [ -d "$root" ] || return 1
  project_id="$(jq -r '.project.id' <<<"$desktop_json")"
  project_name="$(jq -r '.project.name' <<<"$desktop_json")"
  root="$(cd "$root" 2>/dev/null && pwd -P)"
  canonical=1
}

warn() {
  printf '%s\n' "$*" >&2
  command -v notify-send >/dev/null 2>&1 && notify-send -a "Project Resume" "Resume degraded" "$*" >/dev/null 2>&1 || true
}

resume_shared_session() {
  [ "$resume_session" -eq 1 ] || return 0
  [ -n "$session_id" ] || return 0
  command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || return 0
  local cached_project resumable encoded response
  cached_project="$(jq -r '.status.project.id // ""' "$workbench_cache" 2>/dev/null || true)"
  resumable="$(jq -r '
    .status.activeWork as $work |
    ($work.resumable // (["starting","loading","ready","running","waiting","blocked"] | index($work.state) != null))
  ' "$workbench_cache" 2>/dev/null || printf 'false')"
  [ "$cached_project" = "$project_id" ] && [ "$resumable" = "true" ] || return 0
  encoded="$(jq -rn --arg value "$session_id" '$value|@uri')"
  response="$(curl --silent --show-error --fail-with-body --max-time 3 \
    -H 'accept: application/json' -H 'content-type: application/json' \
    --data-binary '{}' "${AI_WORKBENCH_API_URL%/}/sessions/$encoded/resume" 2>&1)" || {
    warn "Workbench session $session_id could not be resumed; desktop launch will continue"
    return 0
  }
  jq -e '.status == "ok"' <<<"$response" >/dev/null 2>&1 || \
    warn "Workbench rejected session resume for $session_id; desktop launch will continue"
}

restore_sidecar() {
  if [ "$focus_sidecar" -eq 1 ] && [ -x "$sidepanel" ]; then
    "$sidepanel" restore-all >/dev/null 2>&1 || true
  fi
}

start_local_ai_runtime() {
  [ "$start_ai" -eq 1 ] || return 0
  if command -v local-ai-runtime >/dev/null 2>&1; then
    local-ai-runtime start >/dev/null 2>&1 || true
  fi
}

launch_scratchpad() {
  local pad="$1"
  [ -x "$scratchpad_manager" ] || return 0
  env \
    NOXFLOW_AI_CONTEXT="$root" NOXFLOW_LOG_CONTEXT="$root" NOXFLOW_DB_CONTEXT="$root" \
    AI_WORKBENCH_PROJECT_ID="$project_id" AI_WORKBENCH_PROJECT_PATH="$root" \
    AI_WORKBENCH_PROJECT_NAME="$project_name" AI_WORKBENCH_TASK_ID="$task_id" \
    AI_WORKBENCH_RUN_ID="$run_id" AI_WORKBENCH_SESSION_ID="$session_id" \
    "$scratchpad_manager" launch "$pad" >/dev/null 2>&1 || true
}

restore_manifest_scratchpads() {
  local pad
  declare -A seen=()
  if [ "$mode" = "restore" ] && [ "$restore_scratchpads" -eq 1 ]; then
    while IFS= read -r pad; do
      case "$pad" in
        ai | logs | db | terminal | notes | browser-devtools) seen["$pad"]=1 ;;
      esac
    done < <(jq -r '.desktop.scratchpads[]?' <<<"$desktop_json" 2>/dev/null || true)
  fi
  [ "$start_ai" -eq 0 ] || seen[ai]=1
  for pad in ai logs db terminal notes browser-devtools; do
    [ "${seen[$pad]:-0}" = "1" ] && launch_scratchpad "$pad"
  done
}

launch_canonical_desktop() {
  resume_shared_session
  start_local_ai_runtime
  "$project_profile" launch "$project_id" >/dev/null 2>&1 &
  restore_sidecar
  restore_manifest_scratchpads
}

load_fallback_root() {
  if [ -n "$fallback_path" ]; then
    [ -d "$fallback_path" ] || {
      echo "fallback path is unavailable: $fallback_path" >&2
      exit 1
    }
    root="$(cd "$fallback_path" 2>/dev/null && pwd -P)"
  else
    local cwd
    cwd="$(noxflow_focused_cwd)"
    root="$(noxflow_git_root "$cwd")"
  fi
  project_name="$(basename "$root")"
}

open_fallback_editor() {
  if command -v code >/dev/null 2>&1; then
    code "$root" >/dev/null 2>&1 &
  elif command -v nvim >/dev/null 2>&1 && command -v kitty >/dev/null 2>&1; then
    kitty --directory "$root" --title "$project_name-editor" -e nvim >/dev/null 2>&1 &
  fi
}

start_fallback_tmux() {
  local tmux_session
  tmux_session="$(printf '%s' "$project_name" | tr -cs '[:alnum:]_-' '-')"
  tmux_session="${tmux_session%-}"
  [ -n "$tmux_session" ] || tmux_session="project"
  if command -v kitty >/dev/null 2>&1; then
    kitty --title "$tmux_session" -e tmux new-session -A -s "$tmux_session" -c "$root" >/dev/null 2>&1 &
  else
    tmux new-session -A -s "$tmux_session" -c "$root"
  fi
}

launch_offline_fallback() {
  load_fallback_root
  warn "No canonical project resolved; opening a terminal-only desktop fallback for $root"
  open_fallback_editor
  start_fallback_tmux
  restore_sidecar
  if [ "$start_ai" -eq 1 ]; then
    start_local_ai_runtime
    launch_scratchpad ai
  fi
}

load_cached_work
if resolve_desktop; then
  launch_canonical_desktop
else
  launch_offline_fallback
fi
