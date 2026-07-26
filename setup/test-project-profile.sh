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
project_dir="$test_dir/example"
curl_log="$test_dir/curl.log"
tmux_log="$test_dir/tmux.log"
editor_log="$test_dir/editor.log"
kitty_log="$test_dir/kitty.log"
mkdir -p "$cache_dir/ai-workbench" "$mock_bin" "$project_dir"

jq -n --arg path "$project_dir" '{
  schemaVersion:1,
  generatedAt:"2026-01-01T00:00:00Z",
  selection:{projectId:"project-one",pinScope:null},
  projects:[
    {id:"project-one",name:"Project One",path:$path,repositoryRoot:$path,aliases:["one"],packageManager:"pnpm",tmuxSession:"project-one-dev",preferredEditor:"nvim",scratchpads:["ai","logs"],scene:"full-development"},
    {id:"project-two",name:"Project Two",path:"/missing/project-two",repositoryRoot:"/missing/project-two",aliases:[],packageManager:"npm",tmuxSession:null}
  ]
}' >"$cache_dir/ai-workbench/project-registry-v1.json"

jq -n --arg path "$project_dir" '{
  schemaVersion:1,
  status:{project:{id:"project-one",name:"Project One",path:$path},git:{branch:"main",dirty:true},state:"running"}
}' >"$cache_dir/ai-workbench/project-status-v1.json"

cat >"$mock_bin/curl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PROJECT_PROFILE_CURL_LOG"
url="${*: -1}"
case "$url" in
  */registry) exit 1 ;;
  */projects/project-one/manifest)
    printf '%s\n' '{"status":"ok","data":{"desktop":{"scene":"full-development"}}}'
    ;;
  */actions\?projectId=project-one)
    printf '%s\n' '{"status":"ok","data":[{"workflowId":"full-development","label":"Full development","category":"development","disabledReason":null},{"workflowId":"verify","label":"Verify","category":"check","disabledReason":null}]}'
    ;;
  */actions/full-development/run)
    printf '%s\n' '{"status":"ok","data":{"execution":{"state":"completed"},"launch":null}}'
    ;;
  */actions/verify/run)
    printf '%s\n' '{"status":"ok","data":{"execution":{"state":"completed"},"launch":null}}'
    ;;
  */context/selection)
    printf '%s\n' '{"status":"ok","data":{"projectId":"project-one","pinScope":"persistent"}}'
    ;;
  */project-status/compact*) printf '%s\n' '{"status":"ok","data":{}}' ;;
  *) exit 1 ;;
esac
MOCK

cat >"$mock_bin/tmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PROJECT_PROFILE_TMUX_LOG"
exit 0
MOCK
cat >"$mock_bin/nvim" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PROJECT_PROFILE_EDITOR_LOG"
MOCK
cat >"$mock_bin/kitty" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PROJECT_PROFILE_KITTY_LOG"
MOCK
chmod +x "$mock_bin/curl" "$mock_bin/tmux" "$mock_bin/nvim" "$mock_bin/kitty"

run_profile() {
  env PATH="$mock_bin:$PATH" XDG_CACHE_HOME="$cache_dir" \
    AI_WORKBENCH_RUNTIME_ENV="$test_dir/missing-runtime.env" \
    PROJECT_PROFILE_CURL_LOG="$curl_log" PROJECT_PROFILE_TMUX_LOG="$tmux_log" \
    PROJECT_PROFILE_EDITOR_LOG="$editor_log" PROJECT_PROFILE_KITTY_LOG="$kitty_log" \
    AI_WORKBENCH_API_URL="http://127.0.0.1:4317" \
    "$repo_dir/setup/project-profile.sh" "$@"
}

run_profile list | grep -F $'*\tproject-one\tProject One' >/dev/null
[ "$(run_profile path one)" = "$project_dir" ]
[ "$(run_profile current)" = "project-one" ]
run_profile status | grep -F 'project-one' | grep -F 'main/dirty/running' >/dev/null
run_profile status | grep -F 'project-two' | grep -F 'missing' >/dev/null
run_profile dev one | grep -F 'dev: full-development (completed)' >/dev/null
run_profile check project-one | grep -F 'check: verify (completed)' >/dev/null
run_profile pin one | grep -F 'pinned project-one' >/dev/null
run_profile tmux one
grep -F 'new-session -A -s project-one-dev' "$tmux_log" >/dev/null
run_profile desktop one | jq -e '
  .schemaVersion == 1 and .project.id == "project-one" and
  .desktop.tmuxSession == "project-one-dev" and .desktop.preferredEditor == "nvim" and
  .desktop.scratchpads == ["ai","logs"] and .desktop.scene == "full-development"
' >/dev/null
run_profile edit one
grep -Fx "$project_dir" "$editor_log" >/dev/null
run_profile launch one
for _attempt in $(seq 1 50); do
  grep -F -- "--title project-one-dev-editor" "$kitty_log" >/dev/null 2>&1 && break
  sleep 0.01
done
grep -F -- "--directory $project_dir --title project-one-dev-editor -e nvim $project_dir" "$kitty_log" >/dev/null
grep -F -- "--title project-one-dev -e tmux new-session -A -s project-one-dev -c $project_dir" "$kitty_log" >/dev/null
grep -F '/actions/full-development/run' "$curl_log" >/dev/null
grep -F '/actions/verify/run' "$curl_log" >/dev/null
grep -F '/context/selection' "$curl_log" >/dev/null

if grep -Eq 'nox-billings|noxcrm|wellvantage|trackme' "$repo_dir/setup/project-profile.sh"; then
  echo 'project-profile must not contain hard-coded project ownership' >&2
  exit 1
fi

printf 'workbench project profile adapter: ok\n'
