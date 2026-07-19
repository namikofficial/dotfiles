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
project_dir="$test_dir/project"
mock_bin="$test_dir/bin"
git_called="$test_dir/git-called"
mkdir -p "$home_dir" "$cache_dir/ai-workbench" "$cache_dir/kage" "$project_dir" "$mock_bin"

cat >"$mock_bin/git" <<'MOCK'
#!/usr/bin/env bash
printf 'called\n' >"$WORKBENCH_TEST_GIT_CALLED"
exit 88
MOCK
chmod +x "$mock_bin/git"

future="$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%S.000Z)"
jq -n --arg path "$project_dir" --arg future "$future" '
  {
    schemaVersion: 1,
    generatedAt: "2026-07-20T00:00:00.000Z",
    status: {
      schemaVersion: 1,
      project: {id:"project-id",name:"Canonical Project",path:$path},
      context: {source:"focused-editor",confidence:0.96,activeFile:($path + "/src/main.ts")},
      git: {branch:"main",modified:2,deleted:1,renamed:1,untracked:3,staged:2,dirty:true},
      activeWork: {taskId:"task-id",runId:"run-id",sessionId:"session-id"},
      staleAfter: $future,
      workbenchAvailable: true
    },
    compact: {ai:{label:"Coding",state:"ready"}}
  }
' >"$cache_dir/ai-workbench/project-status-v1.json"

# A conflicting legacy cache must never influence the helper.
jq -n '{name:"Legacy Wrong",path:"/tmp/legacy-wrong",branch:"wrong"}' \
  >"$cache_dir/kage/project-current.json"

summary="$(
  cd "$home_dir"
  PATH="$mock_bin:$PATH" HOME="$home_dir" XDG_CACHE_HOME="$cache_dir" \
    WORKBENCH_TEST_GIT_CALLED="$git_called" \
    "$repo_dir/hypr/scripts/ai-helper-context.sh" summary
)"

grep -F "Canonical Project at $project_dir | id project-id | branch main | dirty: 7 changed, 2 staged" <<<"$summary" >/dev/null
grep -F "focus $project_dir/src/main.ts" <<<"$summary" >/dev/null
grep -F 'Workbench context: focused-editor | confidence 0.96 | API true | cache fresh' <<<"$summary" >/dev/null
grep -F 'Local AI: Coding [ready]' <<<"$summary" >/dev/null
grep -F 'Active task: task-id' <<<"$summary" >/dev/null
grep -F 'Active run: run-id' <<<"$summary" >/dev/null
grep -F 'Shared session: session-id' <<<"$summary" >/dev/null
if grep -F 'Legacy Wrong' <<<"$summary" >/dev/null; then
  printf 'legacy cache leaked into canonical summary\n' >&2
  exit 1
fi
[ ! -e "$git_called" ]

find "$cache_dir/ai-workbench" -type f -delete
fallback="$(
  cd "$project_dir"
  PATH="$mock_bin:$PATH" HOME="$home_dir" XDG_CACHE_HOME="$cache_dir" \
    WORKBENCH_TEST_GIT_CALLED="$git_called" NOXFLOW_AI_CONTEXT="$project_dir" \
    "$repo_dir/hypr/scripts/ai-helper-context.sh" summary
)"

grep -F "Project: project at $project_dir | clean" <<<"$fallback" >/dev/null
grep -F 'Workbench context: offline-fallback | confidence 0 | API false | cache stale' <<<"$fallback" >/dev/null
if grep -F 'branch ' <<<"$fallback" >/dev/null; then
  printf 'offline fallback unexpectedly inferred a Git branch\n' >&2
  exit 1
fi
if grep -F 'Legacy Wrong' <<<"$fallback" >/dev/null; then
  printf 'legacy cache leaked into offline fallback\n' >&2
  exit 1
fi
[ ! -e "$git_called" ]

launch="$(
  cd "$home_dir"
  PATH="$mock_bin:$PATH" HOME="$home_dir" XDG_CACHE_HOME="$cache_dir" \
    WORKBENCH_TEST_GIT_CALLED="$git_called" \
    AI_WORKBENCH_PROJECT_ID='launch-id' AI_WORKBENCH_PROJECT_NAME='Pinned Scratchpad' \
    AI_WORKBENCH_PROJECT_PATH="$project_dir" AI_WORKBENCH_TASK_ID='launch-task' \
    AI_WORKBENCH_RUN_ID='launch-run' AI_WORKBENCH_SESSION_ID='launch-session' \
    "$repo_dir/hypr/scripts/ai-helper-context.sh" summary
)"

grep -F "Pinned Scratchpad at $project_dir | id launch-id | clean" <<<"$launch" >/dev/null
grep -F 'Workbench context: scratchpad-launch | confidence 1 | API false | cache stale' <<<"$launch" >/dev/null
grep -F 'Active task: launch-task' <<<"$launch" >/dev/null
grep -F 'Active run: launch-run' <<<"$launch" >/dev/null
grep -F 'Shared session: launch-session' <<<"$launch" >/dev/null
[ ! -e "$git_called" ]

printf 'ai helper canonical context tests passed\n'
