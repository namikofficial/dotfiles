#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
cleanup() {
  find "$test_dir" -type f -delete 2>/dev/null || true
  find "$test_dir" -depth -type d -empty -delete 2>/dev/null || true
}
trap cleanup EXIT

cache_dir="$test_dir/cache"
mock_bin="$test_dir/bin"
opened_url="$test_dir/opened-url"
mkdir -p "$cache_dir/ai-workbench" "$mock_bin"

jq -n --arg now "$(date --iso-8601=seconds)" --arg stale "$(date --iso-8601=seconds -d '+5 minutes')" '
  {
    schemaVersion: 1,
    generatedAt: $now,
    status: {
      project: {id:"project-id",name:"Example Project",path:"/tmp/example-project"},
      git: {branch:"main",dirty:true,modified:1,staged:2,untracked:0,deleted:0,renamed:0,conflicts:0,stashes:0,ahead:0,behind:0,detached:false,unborn:false,head:"abc"},
      checks: {state:"completed",passed:1,failed:0,running:0},
      index: {state:"ready",lastIndexedAt:$now,stale:false,progress:null},
      activeWork: {taskId:"task-id",taskTitle:"Implement status",runId:"run-id",sessionId:"session-id",state:"running",taskProgress:{completed:1,total:3},modelRole:"coding",approvalId:null},
      runtime: null,
      blockers: [],
      recommendedActions: [],
      generatedAt: $now,
      staleAfter: $stale,
      state: "running",
      context: {pinned:true,confidence:0.95},
      services: [],
      workbenchAvailable: true
    },
    compact: {
      schemaVersion:1,generatedAt:$now,staleAfter:$stale,state:"running",
      project:{id:"project-id",name:"Example Project",pinned:true,confidence:0.95},
      git:{branch:"main",dirty:1,staged:2,conflicts:0,state:"ready"},
      work:{label:"Implement status",state:"running",progress:"1/3"},
      ai:{label:"coding",state:"ready"},warnings:[],tooltip:"Example Project\nGit: main"
    }
  }
' >"$cache_dir/ai-workbench/project-status-v1.json"

for chip in project git work ai; do
  XDG_CACHE_HOME="$cache_dir" "$repo_dir/hypr/scripts/workbench-wayle-status" "$chip" |
    jq -e '.text != "" and .tooltip != ""' >/dev/null
done

cat >"$mock_bin/curl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat >"$mock_bin/xdg-open" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$1" >"$WORKBENCH_TEST_OPENED_URL"
MOCK
chmod +x "$mock_bin/curl" "$mock_bin/xdg-open"

PATH="$mock_bin:$PATH" XDG_CACHE_HOME="$cache_dir" WORKBENCH_TEST_OPENED_URL="$opened_url" \
  AI_WORKBENCH_URL="http://127.0.0.1:4317" "$repo_dir/hypr/scripts/open-ai-workbench.sh" work

for _ in {1..20}; do
  [ -s "$opened_url" ] && break
  sleep 0.01
done
grep -Fx 'http://127.0.0.1:4317/projects/project-id/work' "$opened_url" >/dev/null

: >"$opened_url"
PATH="$mock_bin:$PATH" XDG_CACHE_HOME="$cache_dir" WORKBENCH_TEST_OPENED_URL="$opened_url" \
  AI_WORKBENCH_URL="http://127.0.0.1:4317" "$repo_dir/hypr/scripts/open-ai-workbench.sh" retrieval
for _ in {1..20}; do
  [ -s "$opened_url" ] && break
  sleep 0.01
done
grep -Fx 'http://127.0.0.1:4317/projects/project-id/retrieval' "$opened_url" >/dev/null

runtime_env="$test_dir/runtime.env"
printf '%s\n' \
  'AI_API_PORT=5517' \
  'AI_WEB_PORT=5317' \
  'AI_LOCAL_BASE_URL=http://127.0.0.1:9080/v1' >"$runtime_env"
# shellcheck disable=SC2016
runtime_values="$(env -u AI_WORKBENCH_API_URL -u AI_WORKBENCH_URL -u LLM_BASE_URL \
  AI_WORKBENCH_RUNTIME_ENV="$runtime_env" bash -c '
  source "$1"
  printf "%s|%s|%s" "$AI_WORKBENCH_API_URL" "$AI_WORKBENCH_URL" "$LLM_BASE_URL"
' _ "$repo_dir/hypr/scripts/workbench-runtime-env.sh")"
[ "$runtime_values" = 'http://127.0.0.1:5517|http://127.0.0.1:5317|http://127.0.0.1:9080/v1' ]
grep -Fx 'EnvironmentFile=-%h/.config/ai-workbench/runtime.env' \
  "$repo_dir/systemd/user/ai-workbench-desktop-observer.service" >/dev/null
grep -Fx 'EnvironmentFile=-%h/.config/ai-workbench/runtime.env' \
  "$repo_dir/systemd/user/ai-workbench-notification-bridge.service" >/dev/null
grep -Fx 'EnvironmentFile=-%h/.config/ai-workbench/runtime.env' \
  "$repo_dir/systemd/user/ai-workbench-project-watch.service" >/dev/null
grep -F 'ai-workbench-notification-bridge.service' "$repo_dir/setup/bootstrap.sh" >/dev/null
grep -F 'ai-workbench-project-watch.service' "$repo_dir/setup/bootstrap.sh" >/dev/null
grep -F 'ExecStart=%h/.config/hypr/scripts/ai-workbench-project-watch.py' \
  "$repo_dir/systemd/user/ai-workbench-project-watch.service" >/dev/null
grep -F 'ProtectHome=read-only' "$repo_dir/systemd/user/ai-workbench-project-watch.service" >/dev/null
grep -F 'ai-workbench-project-watch.service' "$repo_dir/setup/install-workbench-desktop-services.sh" >/dev/null
grep -F 'socket.AF_UNIX' "$repo_dir/hypr/scripts/ai-workbench-observer" >/dev/null
grep -F 'discover_hypr_signature' "$repo_dir/hypr/scripts/ai-workbench-observer" >/dev/null
grep -F 'activewindowv2' "$repo_dir/hypr/scripts/ai-workbench-observer" >/dev/null
grep -F 'last_payload' "$repo_dir/hypr/scripts/ai-workbench-observer" >/dev/null
grep -F 'date -u +%Y-%m-%dT%H:%M:%S.%3NZ' "$repo_dir/hypr/scripts/ai-workbench-observer" >/dev/null
# shellcheck disable=SC2016 -- matching literal shell source in the observer
grep -F '"$project_id" != "$cached_project"' "$repo_dir/hypr/scripts/ai-workbench-observer" >/dev/null
if grep -F 'socat' "$repo_dir/hypr/scripts/ai-workbench-observer" >/dev/null; then
  printf 'observer must not depend on optional socat\n' >&2
  exit 1
fi
if grep -F 'get-project-context.sh' "$repo_dir/hypr/scripts/ai-helper-context.sh" \
  "$repo_dir/hypr/scripts/local-llm-chat-enhanced.sh" >/dev/null; then
  printf 'AI helpers must consume canonical Workbench context instead of the legacy detector\n' >&2
  exit 1
fi
if grep -F '/kage/project-current.json' "$repo_dir/hypr/scripts/ai-helper-context.sh" >/dev/null; then
  printf 'AI helper must not consume the legacy Kage project cache\n' >&2
  exit 1
fi
printf 'workbench desktop adapters: ok\n'
