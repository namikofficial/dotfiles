#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/../hypr/scripts/workbench-runtime-env.sh"

registry_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ai-workbench/project-registry-v1.json"
status_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ai-workbench/project-status-v1.json"
workflow_launcher="${HOME}/.config/hypr/scripts/workbench-workflow-launch.py"
api_url="${AI_WORKBENCH_API_URL%/}"

usage() {
  cat <<'USAGE'
Usage: project-profile <command> [project]

Projects are resolved from the canonical Workbench registry by ID, name, or alias.

Commands:
  list                    List registered projects
  status                  Show registry and cached active-project status
  current                 Print the selected project ID
  path <project>          Print the canonical project path
  cd <project>            Print a safely quoted cd command
  select <project>        Select the project through Workbench
  pin <project>           Persistently pin the project through Workbench
  edit <project>          Open the canonical project path in an editor
  shell <project>         Open a project-rooted Kitty shell
  tmux <project>          Attach/create the manifest-named tmux session
  dev <project>           Run the manifest scene/development workflow
  check <project>         Run the manifest verification/check workflow
  launch <project>        Open the editor and manifest-named tmux session

Offline behavior:
  list/status/path/cd/edit/shell/tmux/launch use the read-only XDG registry cache.
  select/pin/dev/check require Workbench and never create divergent local state.
USAGE
}

require_tools() {
  command -v jq >/dev/null 2>&1 || {
    echo "project-profile requires jq" >&2
    exit 1
  }
}

api_get() {
  local path="$1"
  command -v curl >/dev/null 2>&1 || return 1
  curl --silent --show-error --fail --max-time 3 -H 'accept: application/json' "$api_url$path"
}

load_registry() {
  local response
  response="$(api_get "/registry" 2>/dev/null || true)"
  if jq -e '.status == "ok" and (.data.manifests | type == "array")' <<<"$response" >/dev/null 2>&1; then
    jq -c '
      .data as $data |
      {
        schemaVersion: 1,
        generatedAt: (now | todateiso8601),
        selection: $data.selection,
        projects: [
          $data.manifests[] | {
            id, name, path, repositoryRoot,
            aliases: (.detection.aliases // []),
            packageManager,
            tmuxSession: (.desktop.tmuxSession // null)
          }
        ]
      }
    ' <<<"$response"
    return 0
  fi
  if [ -s "$registry_cache" ] && jq -e '.schemaVersion == 1 and (.projects | type == "array")' \
    "$registry_cache" >/dev/null 2>&1; then
    jq -c '.' "$registry_cache"
    return 0
  fi
  echo "Workbench is offline and no valid registry cache is available" >&2
  return 1
}

resolve_project() {
  local selector="$1" matches count
  if [ -z "$selector" ]; then
    selector="$(jq -r '.selection.projectId // ""' <<<"$registry")"
  fi
  [ -n "$selector" ] || {
    echo "project required; run: project-profile list" >&2
    return 2
  }
  matches="$(jq -c --arg selector "${selector,,}" '
    [.projects[] |
      select(
        ((.id | ascii_downcase) == $selector) or
        ((.name | ascii_downcase) == $selector) or
        ((.aliases // [] | map(ascii_downcase) | index($selector)) != null)
      )]
  ' <<<"$registry")"
  count="$(jq 'length' <<<"$matches")"
  if [ "$count" -eq 0 ]; then
    echo "unknown registered project: $selector" >&2
    return 2
  fi
  if [ "$count" -ne 1 ]; then
    echo "ambiguous project selector: $selector" >&2
    jq -r '.[].id' <<<"$matches" >&2
    return 2
  fi
  jq -c '.[0]' <<<"$matches"
}

project_path() {
  local project="$1" path
  path="$(jq -r '.path' <<<"$project")"
  [ -d "$path" ] || {
    echo "registered project path is unavailable: $path" >&2
    return 1
  }
  printf '%s\n' "$path"
}

project_session() {
  local project="$1" session
  session="$(jq -r '.tmuxSession // ""' <<<"$project")"
  if [ -z "$session" ]; then
    session="$(jq -r '.id' <<<"$project" | tr -cs '[:alnum:]_-' '-')"
    session="${session%-}"
  fi
  printf '%s\n' "${session:-project}"
}

list_projects() {
  local selected
  selected="$(jq -r '.selection.projectId // ""' <<<"$registry")"
  jq -r --arg selected "$selected" '
    .projects[] |
    (if .id == $selected then "*" else " " end) +
    "\t" + .id + "\t" + .name + "\t" + .path
  ' <<<"$registry"
}

project_status() {
  local selected active_id
  selected="$(jq -r '.selection.projectId // ""' <<<"$registry")"
  active_id="$(jq -r '.status.project.id // ""' "$status_cache" 2>/dev/null || true)"
  while IFS=$'\t' read -r id name path; do
    local marker="registered"
    if [ "$id" = "$active_id" ]; then
      marker="$(jq -r '
        (.status.git.branch // "no-branch") + "/" +
        (if (.status.git.dirty // false) then "dirty" else "clean" end) + "/" +
        (.status.state // "unknown")
      ' "$status_cache" 2>/dev/null || printf 'cached-status-invalid')"
    elif [ "$id" = "$selected" ]; then
      marker="selected/cache-unavailable"
    fi
    [ -d "$path" ] || marker="missing"
    printf '%-22s %-24s %-28s %s\n' "$id" "$name" "$marker" "$path"
  done < <(jq -r '.projects[] | [.id, .name, .path] | @tsv' <<<"$registry")
}

select_project() {
  local project="$1" pin_scope="$2" id payload response
  id="$(jq -r '.id' <<<"$project")"
  payload="$(jq -cn --arg projectId "$id" --arg pinScope "$pin_scope" \
    '{projectId:$projectId,source:"project-profile",pinScope:(if $pinScope == "" then null else $pinScope end)}')"
  response="$(curl --silent --show-error --fail-with-body --max-time 3 \
    -H 'accept: application/json' -H 'content-type: application/json' \
    --data-binary "$payload" "$api_url/context/selection" 2>&1)" || {
    echo "Workbench is unavailable; canonical project selection was not changed" >&2
    [ -n "$response" ] && printf '%s\n' "$response" >&2
    return 1
  }
  jq -e '.status == "ok"' <<<"$response" >/dev/null 2>&1 || {
    echo "Workbench rejected project selection" >&2
    return 1
  }
  api_get "/project-status/compact?projectId=$(jq -rn --arg value "$id" '$value|@uri')" >/dev/null 2>&1 || true
  printf '%s %s\n' "$([ -n "$pin_scope" ] && printf 'pinned' || printf 'selected')" "$id"
}

choose_action() {
  local project="$1" purpose="$2" id manifest actions scene candidates count
  id="$(jq -r '.id' <<<"$project")"
  manifest="$(api_get "/projects/$(jq -rn --arg value "$id" '$value|@uri')/manifest" 2>/dev/null || true)"
  actions="$(api_get "/actions?projectId=$(jq -rn --arg value "$id" '$value|@uri')" 2>/dev/null || true)"
  if ! jq -e '.status == "ok" and (.data | type == "array")' <<<"$actions" >/dev/null 2>&1; then
    echo "Workbench is unavailable; $purpose requires a canonical workflow" >&2
    return 1
  fi
  if [ "$purpose" = "dev" ]; then
    scene="$(jq -r '.data.desktop.scene // ""' <<<"$manifest" 2>/dev/null || true)"
    candidates="$(jq -c --arg scene "$scene" '
      [.data[] | select(.disabledReason == null and (
        ($scene != "" and .workflowId == $scene) or
        (.workflowId == "dev") or
        (.category == "development")
      ))] |
      if $scene != "" and any(.workflowId == $scene) then [.[] | select(.workflowId == $scene)]
      elif any(.workflowId == "dev") then [.[] | select(.workflowId == "dev")]
      else . end
    ' <<<"$actions")"
  else
    candidates="$(jq -c '
      [.data[] | select(.disabledReason == null and (
        (.workflowId == "verify") or (.workflowId == "check") or (.category == "check")
      ))] |
      if any(.workflowId == "verify") then [.[] | select(.workflowId == "verify")]
      elif any(.workflowId == "check") then [.[] | select(.workflowId == "check")]
      else . end
    ' <<<"$actions")"
  fi
  count="$(jq 'length' <<<"$candidates")"
  if [ "$count" -ne 1 ]; then
    echo "Expected one canonical $purpose workflow for $id; found $count" >&2
    jq -r '.data[] | select(.category == (if "'"$purpose"'" == "dev" then "development" else "check" end)) | "  \(.workflowId): \(.label)"' \
      <<<"$actions" >&2 || true
    return 1
  fi
  jq -c '.[0]' <<<"$candidates"
}

run_action() {
  local project="$1" purpose="$2" id action workflow_id payload response state execution_id deep_link
  id="$(jq -r '.id' <<<"$project")"
  action="$(choose_action "$project" "$purpose")" || return
  workflow_id="$(jq -r '.workflowId' <<<"$action")"
  payload="$(jq -cn --arg projectId "$id" '{projectId:$projectId}')"
  response="$(curl --silent --show-error --fail-with-body --max-time 900 \
    -H 'accept: application/json' -H 'content-type: application/json' \
    --data-binary "$payload" \
    "$api_url/actions/$(jq -rn --arg value "$workflow_id" '$value|@uri')/run" 2>&1)" || {
    echo "Workbench workflow failed: $workflow_id" >&2
    [ -n "$response" ] && printf '%s\n' "$response" >&2
    return 1
  }
  state="$(jq -r '.data.execution.state // "unknown"' <<<"$response")"
  execution_id="$(jq -r '.data.launch.executionId // ""' <<<"$response")"
  deep_link="$(jq -r '.data.deepLink // ""' <<<"$response")"
  printf '%s: %s (%s)\n' "$purpose" "$workflow_id" "$state"
  if [ "$state" = "ready" ] && [ -n "$execution_id" ] && [ -x "$workflow_launcher" ]; then
    "$workflow_launcher" "$execution_id"
  elif [ "$state" = "waiting" ] && [ -n "$deep_link" ]; then
    printf 'approval: %s%s\n' "$AI_WORKBENCH_URL" "$deep_link"
  fi
}

open_editor() {
  local path="$1"
  if command -v code >/dev/null 2>&1; then
    code "$path"
  elif command -v nvim >/dev/null 2>&1; then
    nvim "$path"
  else
    echo "no supported editor is installed" >&2
    return 1
  fi
}

open_tmux() {
  local project="$1" path session
  path="$(project_path "$project")"
  session="$(project_session "$project")"
  if [ -n "${TMUX:-}" ] && tmux has-session -t "$session" 2>/dev/null; then
    exec tmux switch-client -t "$session"
  fi
  exec tmux new-session -A -s "$session" -c "$path"
}

require_tools
registry="$(load_registry)" || exit 1
command_name="${1:-list}"
selector="${2:-}"

case "$command_name" in
  list)
    list_projects
    ;;
  status)
    project_status
    ;;
  current)
    jq -r '.selection.projectId // ""' <<<"$registry"
    ;;
  path | cd | select | pin | edit | shell | tmux | dev | check | launch)
    project="$(resolve_project "$selector")"
    case "$command_name" in
      path) project_path "$project" ;;
      cd) printf 'cd %q\n' "$(project_path "$project")" ;;
      select) select_project "$project" "" ;;
      pin) select_project "$project" "persistent" ;;
      edit) open_editor "$(project_path "$project")" ;;
      shell)
        path="$(project_path "$project")"
        session="$(project_session "$project")"
        exec kitty --title "$session" --directory "$path"
        ;;
      tmux) open_tmux "$project" ;;
      dev | check) run_action "$project" "$command_name" ;;
      launch)
        path="$(project_path "$project")"
        open_editor "$path" >/dev/null 2>&1 &
        if command -v kitty >/dev/null 2>&1; then
          session="$(project_session "$project")"
          exec kitty --title "$session" -e tmux new-session -A -s "$session" -c "$path"
        fi
        open_tmux "$project"
        ;;
    esac
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    echo "unknown command: $command_name" >&2
    usage >&2
    exit 2
    ;;
esac
