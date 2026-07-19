#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/workbench-runtime-env.sh"

action="${1:-prompt}"
mode="${2:-ask}"

workbench_status_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ai-workbench/project-status-v1.json"
# shellcheck disable=SC2153
llm_base_url="$LLM_BASE_URL"
llm_model_alias="${LLM_CHAT_MODEL:-local}"

project_id=""
project_path=""
project_name=""
project_branch=""
project_modified="0"
project_staged="0"
project_dirty="false"
current_file=""
context_source="offline-fallback"
context_confidence="0"
workbench_available="false"
cache_stale="true"
active_task=""
active_run=""
active_session=""
ai_label="$llm_model_alias"
ai_state="unknown"
machine_arch="$(uname -m 2>/dev/null || printf 'unknown')"

load_offline_directory() {
  local dir="${1:-}"
  [ -d "$dir" ] || return 1

  project_path="$(cd "$dir" 2>/dev/null && pwd -P)"
  project_name="$(basename "$project_path")"
  context_source="offline-fallback"
  return 0
}

load_workbench_status() {
  command -v jq >/dev/null 2>&1 || return 1
  [ -s "$workbench_status_cache" ] || return 1
  jq -e '.schemaVersion == 1 and .status.schemaVersion == 1' "$workbench_status_cache" >/dev/null 2>&1 || return 1

  workbench_available="$(jq -r '.status.workbenchAvailable // false' "$workbench_status_cache")"
  cache_stale="$(jq -r --arg now "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
    '((.status.staleAfter // "") == "") or ((.status.staleAfter // "") <= $now)' "$workbench_status_cache")"
  project_id="$(jq -r '.status.project.id // ""' "$workbench_status_cache")"
  project_path="$(jq -r '.status.project.path // ""' "$workbench_status_cache")"
  project_name="$(jq -r '.status.project.name // ""' "$workbench_status_cache")"
  project_branch="$(jq -r '.status.git.branch // ""' "$workbench_status_cache")"
  project_modified="$(jq -r '(.status.git.modified // 0) + (.status.git.deleted // 0) + (.status.git.renamed // 0) + (.status.git.untracked // 0)' "$workbench_status_cache")"
  project_staged="$(jq -r '.status.git.staged // 0' "$workbench_status_cache")"
  project_dirty="$(jq -r '.status.git.dirty // false' "$workbench_status_cache")"
  context_source="$(jq -r '.status.context.source // "unresolved"' "$workbench_status_cache")"
  context_confidence="$(jq -r '.status.context.confidence // 0' "$workbench_status_cache")"
  current_file="$(jq -r '.status.context.activeFile // ""' "$workbench_status_cache")"
  active_task="$(jq -r '.status.activeWork.taskId // ""' "$workbench_status_cache")"
  active_run="$(jq -r '.status.activeWork.runId // ""' "$workbench_status_cache")"
  active_session="$(jq -r '.status.activeWork.sessionId // ""' "$workbench_status_cache")"
  ai_label="$(jq -r '.compact.ai.label // "AI"' "$workbench_status_cache")"
  ai_state="$(jq -r '.compact.ai.state // "unknown"' "$workbench_status_cache")"
  return 0
}

load_project_context() {
  local cached_project_id cached_project_path explicit_path
  load_workbench_status || true
  cached_project_id="$project_id"
  cached_project_path="$project_path"
  explicit_path="${AI_WORKBENCH_PROJECT_PATH:-${NOXFLOW_AI_CONTEXT:-}}"

  if [ -n "${AI_WORKBENCH_PROJECT_ID:-}" ] && [ -n "$explicit_path" ] && [ -d "$explicit_path" ]; then
    project_id="$AI_WORKBENCH_PROJECT_ID"
    project_path="$(cd "$explicit_path" 2>/dev/null && pwd -P)"
    project_name="${AI_WORKBENCH_PROJECT_NAME:-$(basename "$project_path")}"
    context_source="scratchpad-launch"
    context_confidence="1"
    active_task="${AI_WORKBENCH_TASK_ID:-$active_task}"
    active_run="${AI_WORKBENCH_RUN_ID:-$active_run}"
    active_session="${AI_WORKBENCH_SESSION_ID:-$active_session}"
    if [ "$cached_project_id" != "$project_id" ] || [ "$cached_project_path" != "$project_path" ]; then
      project_branch=""
      project_modified="0"
      project_staged="0"
      project_dirty="false"
      current_file=""
      cache_stale="true"
    fi
  elif [ -n "$project_path" ] && [ -d "$project_path" ]; then
    [ -n "$project_name" ] || project_name="$(basename "$project_path")"
  elif [ -n "$explicit_path" ] && [ -d "$explicit_path" ]; then
    load_offline_directory "$explicit_path"
  else
    case "$(pwd -P)" in
      "$HOME" | /) load_offline_directory "$HOME" ;;
      *) load_offline_directory "$(pwd -P)" ;;
    esac
  fi
}

distribution_name() {
  if [ -f /etc/arch-release ]; then
    printf 'Arch Linux\n'
  else
    printf 'Linux\n'
  fi
}

shell_summary() {
  local shell_bin shell_name version
  shell_bin="${SHELL:-/bin/sh}"
  shell_name="$(basename "$shell_bin")"
  version="$("$shell_bin" --version 2>/dev/null | head -n1 || true)"
  if [ -n "$version" ]; then
    printf '%s\n' "$version"
  else
    printf '%s\n' "$shell_name"
  fi
}

join_available() {
  local max="$1"
  shift
  local out=()
  local cmd
  for cmd in "$@"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      out+=("$cmd")
    fi
    [ "${#out[@]}" -ge "$max" ] && break
  done
  if [ "${#out[@]}" -eq 0 ]; then
    return 0
  fi
  printf '%s' "${out[0]}"
  local i
  for ((i = 1; i < ${#out[@]}; i++)); do
    printf ', %s' "${out[i]}"
  done
}

project_line() {
  local status="clean"
  if [ "${project_dirty:-false}" = "true" ] || [ "${project_modified:-0}" -gt 0 ]; then
    status="dirty: ${project_modified} modified"
    [ "${project_staged:-0}" -gt 0 ] && status="${status}, ${project_staged} staged"
  fi

  printf '%s at %s' "${project_name:-workspace}" "${project_path:-$HOME}"
  [ -n "${project_id:-}" ] && printf ' | id %s' "$project_id"
  [ -n "${project_branch:-}" ] && printf ' | branch %s' "$project_branch"
  printf ' | %s' "$status"
  [ -n "${current_file:-}" ] && printf ' | focus %s' "$current_file"
}

print_summary() {
  local modern workstation devtools
  modern="$(join_available 6 rg fd bat eza jq gh)"
  workstation="$(join_available 8 rofi kitty wl-copy wl-paste codex opencode llama-swap-manager)"
  devtools="$(join_available 8 docker kubectl tmux nvim atuin lazygit btop duf procs dust hyperfine pipx)"

  printf 'Workstation: %s %s on Hyprland | shell %s\n' "$(distribution_name)" "$machine_arch" "$(shell_summary)"
  printf 'Local AI: %s [%s] | llama-swap-manager at %s\n' "$ai_label" "$ai_state" "$llm_base_url"
  printf 'Workbench context: %s | confidence %s | API %s | cache %s\n' \
    "$context_source" "$context_confidence" "$workbench_available" "$([ "$cache_stale" = "true" ] && printf stale || printf fresh)"
  printf 'Project: %s\n' "$(project_line)"
  [ -n "$active_task" ] && printf 'Active task: %s\n' "$active_task"
  [ -n "$active_run" ] && printf 'Active run: %s\n' "$active_run"
  [ -n "$active_session" ] && printf 'Shared session: %s\n' "$active_session"
  printf 'Conventions: prefer %s; aliases include dc, k, gss, glg, gcm, reload, hreload, clipcopy/clippaste/jclip.\n' "${modern:-rg, fd, bat, eza, jq, gh}"
  [ -n "$workstation" ] && printf 'Helper tools: %s\n' "$workstation"
  [ -n "$devtools" ] && printf 'Common tools: %s\n' "$devtools"
}

print_prompt() {
  cat <<EOF
You are the local AI helper for this laptop. Ground answers in the real workstation context below instead of generic defaults.

$(print_summary)

EOF

  case "$mode" in
    ask)
      cat <<'EOF'
Mode: answer direct questions for this machine and the active project.
- Be concise but complete.
- Prefer exact local commands, aliases, or file paths when they help.
- State assumptions clearly instead of inventing missing facts.
EOF
      ;;
    clip)
      cat <<'EOF'
Mode: summarize clipboard content for quick reuse.
- Assume pasted code/logs/commands came from this Arch/Hyprland/zsh environment unless the text says otherwise.
- Return: 1) one-line summary 2) key points 3) action items 4) risks or ambiguities.
- Do not invent context that is not present in the clipboard.
EOF
      ;;
    shell)
      cat <<'EOF'
Mode: generate shell guidance for this machine.
- Prefer the smallest safe command sequence that is easy to verify and roll back.
- Prefer local conventions and tools above (for example rg/fd/bat/eza/jq/gh, dc for docker compose, k for kubectl).
- Put commands in one fenced bash block.
- Flag sudo, destructive actions, or risky assumptions before the command block.
- Include short validation steps; include rollback only when it matters.
EOF
      ;;
    debug)
      cat <<'EOF'
Mode: debug errors, logs, or broken commands from this machine.
- Interpret logs in the context of Arch Linux, Hyprland, zsh, and the active project when relevant.
- Return: 1) likely root causes in probability order 2) next checks/commands 3) minimal fix plan 4) what evidence would confirm or rule out each guess.
- Prefer practical commands that use the installed tools listed above.
EOF
      ;;
    scratchpad)
      cat <<'EOF'
Mode: persistent local scratchpad chat.
- Stay practical, terse, and action-oriented.
- Use the workstation/project context above in every answer.
- When suggesting commands, prefer local tools and aliases when useful and call out risky steps.
- Use markdown code fences for commands or code; avoid long preambles.
EOF
      ;;
    raw)
      cat <<'EOF'
Mode: preserve the user's freeform prompt.
- Keep the user's wording primary.
- Only apply the workstation context above when it helps with commands, tooling, paths, or system-specific advice.
EOF
      ;;
    *)
      printf 'Unknown mode: %s\n' "$mode" >&2
      exit 1
      ;;
  esac
}

load_project_context

case "$action" in
  prompt) print_prompt ;;
  summary) print_summary ;;
  *)
    printf 'usage: %s [prompt <ask|clip|shell|debug|scratchpad|raw>|summary]\n' "$0" >&2
    exit 1
    ;;
esac
