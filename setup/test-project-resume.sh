#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
cleanup() {
  find "$test_dir" -type f -delete 2>/dev/null || true
  find "$test_dir" -depth -type d -empty -delete 2>/dev/null || true
}
trap cleanup EXIT

home_dir="$test_dir/home"
cache_dir="$test_dir/cache"
project_dir="$test_dir/project space"
mock_bin="$test_dir/bin"
profile="$test_dir/project-profile"
scratch="$test_dir/scratchpad-manager"
sidepanel="$test_dir/sidepanel"
profile_log="$test_dir/profile.log"
scratch_log="$test_dir/scratch.log"
sidepanel_log="$test_dir/sidepanel.log"
curl_log="$test_dir/curl.log"
kitty_log="$test_dir/kitty.log"
editor_log="$test_dir/editor.log"
mkdir -p "$home_dir" "$cache_dir/ai-workbench" "$project_dir" "$mock_bin"

jq -n --arg path "$project_dir" '{
  schemaVersion:1,
  status:{
    project:{id:"project-id",name:"Canonical Project",path:$path},
    activeWork:{taskId:"task-id",runId:"run-id",sessionId:"session with space",state:"waiting",resumable:true}
  }
}' >"$cache_dir/ai-workbench/project-status-v1.json"

jq -n --arg path "$project_dir" '{
  schemaVersion:1,selection:{projectId:"project-id"},
  projects:[{id:"project-id",name:"Canonical Project",path:$path,tmuxSession:"canonical-session"}]
}' >"$cache_dir/ai-workbench/project-registry-v1.json"

cat >"$profile" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  desktop)
    jq -cn --arg path "$PROJECT_RESUME_PROJECT_PATH" '{
      schemaVersion:1,
      project:{id:"project-id",name:"Canonical Project",path:$path},
      desktop:{tmuxSession:"canonical-session",preferredEditor:"nvim",scratchpads:["ai","logs","db","malicious"],scene:"full-development"}
    }'
    ;;
  launch)
    printf '%s\n' "$*" >>"$PROJECT_RESUME_PROFILE_LOG"
    ;;
  *) exit 1 ;;
esac
MOCK

cat >"$scratch" <<'MOCK'
#!/usr/bin/env bash
printf '%s|%s|%s|%s|%s|%s|%s\n' \
  "$2" "$AI_WORKBENCH_PROJECT_ID" "$AI_WORKBENCH_PROJECT_PATH" \
  "$AI_WORKBENCH_TASK_ID" "$AI_WORKBENCH_RUN_ID" "$AI_WORKBENCH_SESSION_ID" \
  "${NOXFLOW_AI_CONTEXT:-${NOXFLOW_LOG_CONTEXT:-${NOXFLOW_DB_CONTEXT:-}}}" \
  >>"$PROJECT_RESUME_SCRATCH_LOG"
MOCK

cat >"$sidepanel" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PROJECT_RESUME_SIDEPANEL_LOG"
MOCK

cat >"$mock_bin/curl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PROJECT_RESUME_CURL_LOG"
printf '%s\n' '{"status":"ok","data":{"status":"running"}}'
MOCK

cat >"$mock_bin/notify-send" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat >"$mock_bin/kitty" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PROJECT_RESUME_KITTY_LOG"
MOCK

cat >"$mock_bin/code" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PROJECT_RESUME_EDITOR_LOG"
MOCK

cat >"$mock_bin/tmux" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

chmod +x "$profile" "$scratch" "$sidepanel" "$mock_bin/curl" "$mock_bin/notify-send" \
  "$mock_bin/kitty" "$mock_bin/code" "$mock_bin/tmux"

common_env=(
  PATH="$mock_bin:$PATH"
  HOME="$home_dir"
  XDG_CACHE_HOME="$cache_dir"
  AI_WORKBENCH_RUNTIME_ENV="$test_dir/missing-runtime.env"
  AI_WORKBENCH_API_URL="http://127.0.0.1:5517"
  NOXFLOW_PROJECT_PROFILE="$profile"
  NOXFLOW_SCRATCHPAD_MANAGER="$scratch"
  NOXFLOW_SIDEPANEL="$sidepanel"
  PROJECT_RESUME_PROJECT_PATH="$project_dir"
  PROJECT_RESUME_PROFILE_LOG="$profile_log"
  PROJECT_RESUME_SCRATCH_LOG="$scratch_log"
  PROJECT_RESUME_SIDEPANEL_LOG="$sidepanel_log"
  PROJECT_RESUME_CURL_LOG="$curl_log"
  PROJECT_RESUME_KITTY_LOG="$kitty_log"
  PROJECT_RESUME_EDITOR_LOG="$editor_log"
)

env "${common_env[@]}" "$repo_dir/hypr/scripts/project-resume.sh" restore
for _ in {1..50}; do
  [ -s "$profile_log" ] && break
  sleep 0.01
done

grep -Fx 'launch project-id' "$profile_log" >/dev/null
grep -F 'http://127.0.0.1:5517/sessions/session%20with%20space/resume' "$curl_log" >/dev/null
grep -Fx 'restore-all' "$sidepanel_log" >/dev/null
for pad in ai logs db; do
  grep -F "$pad|project-id|$project_dir|task-id|run-id|session with space|$project_dir" "$scratch_log" >/dev/null
done
if grep -F 'malicious' "$scratch_log" >/dev/null; then
  printf 'unallowlisted manifest scratchpad was launched\n' >&2
  exit 1
fi

# An explicit project must never inherit active-work identifiers from another
# cached project.
jq -n --arg path "$project_dir" '{
  schemaVersion:1,
  status:{
    project:{id:"other-project",name:"Other",path:$path},
    activeWork:{taskId:"other-task",runId:"other-run",sessionId:"other-session",state:"waiting",resumable:true}
  }
}' >"$cache_dir/ai-workbench/project-status-v1.json"
: >"$scratch_log"
env "${common_env[@]}" "$repo_dir/hypr/scripts/project-resume.sh" restore \
  --project project-id --no-sidecar --no-session-resume
grep -F "ai|project-id|$project_dir||||$project_dir" "$scratch_log" >/dev/null
if grep -E 'other-(task|run|session)' "$scratch_log" >/dev/null; then
  printf 'cross-project active-work identifiers leaked into scratchpad launch\n' >&2
  exit 1
fi

find "$cache_dir/ai-workbench" -type f -delete
: >"$profile_log"
: >"$curl_log"
env "${common_env[@]}" "$repo_dir/hypr/scripts/project-resume.sh" launch \
  --fallback-path "$project_dir" --no-sidecar --no-session-resume
for _ in {1..50}; do
  [ -s "$kitty_log" ] && break
  sleep 0.01
done

[ ! -s "$profile_log" ]
[ ! -s "$curl_log" ]
grep -F -- "--title project-space -e tmux new-session -A -s project-space -c $project_dir" "$kitty_log" >/dev/null
grep -Fx "$project_dir" "$editor_log" >/dev/null

printf 'project resume canonical coordinator: ok\n'
