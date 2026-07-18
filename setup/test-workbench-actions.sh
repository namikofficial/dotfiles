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
request_file="$test_dir/request"
notification_file="$test_dir/notifications"
open_file="$test_dir/opened"
launch_file="$test_dir/launched"
mkdir -p "$cache_dir/ai-workbench" "$mock_bin" "$test_dir/home"

jq -n --arg now "$(date --iso-8601=seconds)" --arg stale "$(date --iso-8601=seconds -d '+5 minutes')" '
  {
    schemaVersion:1,generatedAt:$now,
    status:{
      project:{id:"project-id",name:"Example",path:"/tmp/example"},
      activeWork:{sessionId:"session-id",taskId:"task-id"},
      checks:{failed:0},index:{stale:false},
      recommendedActions:[
        {label:"Verify",workflowId:"verify",disabledReason:null,approvalRequired:false},
        {label:"Deploy",workflowId:"deploy",disabledReason:null,approvalRequired:true},
        {label:"Interactive",workflowId:"interactive",disabledReason:null,approvalRequired:false}
      ]
    },
    compact:{schemaVersion:1,project:{name:"Example"},git:{branch:"main",dirty:0,staged:0},work:{label:"Verify",state:"ready"}}
  }
' >"$cache_dir/ai-workbench/project-status-v1.json"

cat >"$mock_bin/rofi" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "${WORKBENCH_TEST_ROFI_CHOICE:-[Run] Verify}"
MOCK
cat >"$mock_bin/curl" <<'MOCK'
#!/usr/bin/env bash
payload=""
url=""
while (($#)); do
  case "$1" in
    --data-binary)
      payload="$2"
      shift 2
      ;;
    http://* | https://*)
      url="$1"
      shift
      ;;
    *) shift ;;
  esac
done
printf '%s\n%s\n' "$url" "$payload" >"$WORKBENCH_ACTION_REQUEST_FILE"
if [[ "$url" == */actions/deploy/run ]]; then
  printf '{"status":"ok","data":{"execution":{"state":"waiting"},"deepLink":"/approvals/approval-id"}}\n'
elif [[ "$url" == */actions/interactive/run ]]; then
  printf '{"status":"ok","data":{"execution":{"state":"ready"},"launch":{"executionId":"execution-id"}}}\n'
else
  printf '{"status":"ok","data":{"execution":{"state":"completed"}}}\n'
fi
MOCK
cat >"$mock_bin/xdg-open" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$1" >"$WORKBENCH_ACTION_OPEN_FILE"
MOCK
cat >"$mock_bin/notify-send" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$WORKBENCH_ACTION_NOTIFICATION_FILE"
MOCK
chmod +x "$mock_bin/rofi" "$mock_bin/curl" "$mock_bin/xdg-open" "$mock_bin/notify-send"
mkdir -p "$test_dir/home/.config/hypr/scripts"
cat >"$test_dir/home/.config/hypr/scripts/workbench-workflow-launch.py" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$1" >"$WORKBENCH_ACTION_LAUNCH_FILE"
MOCK
chmod +x "$test_dir/home/.config/hypr/scripts/workbench-workflow-launch.py"

PATH="$mock_bin:$PATH" HOME="$test_dir/home" XDG_CACHE_HOME="$cache_dir" \
  AI_WORKBENCH_API_URL="http://127.0.0.1:5517" \
  AI_WORKBENCH_URL="http://127.0.0.1:5317" \
  WORKBENCH_ACTION_REQUEST_FILE="$request_file" \
  WORKBENCH_ACTION_OPEN_FILE="$open_file" \
  WORKBENCH_ACTION_LAUNCH_FILE="$launch_file" \
  WORKBENCH_ACTION_NOTIFICATION_FILE="$notification_file" \
  "$repo_dir/hypr/scripts/kage-project-rofi.sh"

sed -n '1p' "$request_file" | grep -Fx 'http://127.0.0.1:5517/actions/verify/run' >/dev/null
sed -n '2p' "$request_file" | jq -e '
  .projectId == "project-id" and .sessionId == "session-id" and .taskId == "task-id"
' >/dev/null
grep -F 'Workflow started Verify' "$notification_file" >/dev/null
grep -F 'Workflow completed Verify' "$notification_file" >/dev/null

WORKBENCH_TEST_ROFI_CHOICE='[Request] Deploy' \
  PATH="$mock_bin:$PATH" HOME="$test_dir/home" XDG_CACHE_HOME="$cache_dir" \
  AI_WORKBENCH_API_URL="http://127.0.0.1:5517" AI_WORKBENCH_URL="http://127.0.0.1:5317" \
  WORKBENCH_ACTION_REQUEST_FILE="$request_file" WORKBENCH_ACTION_OPEN_FILE="$open_file" \
  WORKBENCH_ACTION_LAUNCH_FILE="$launch_file" \
  WORKBENCH_ACTION_NOTIFICATION_FILE="$notification_file" \
  "$repo_dir/hypr/scripts/kage-project-rofi.sh"

sed -n '1p' "$request_file" | grep -Fx 'http://127.0.0.1:5517/actions/deploy/run' >/dev/null
grep -F 'Workflow waiting Deploy' "$notification_file" >/dev/null
grep -Fx 'http://127.0.0.1:5317/approvals/approval-id' "$open_file" >/dev/null

WORKBENCH_TEST_ROFI_CHOICE='[Run] Interactive' \
  PATH="$mock_bin:$PATH" HOME="$test_dir/home" XDG_CACHE_HOME="$cache_dir" \
  AI_WORKBENCH_API_URL="http://127.0.0.1:5517" AI_WORKBENCH_URL="http://127.0.0.1:5317" \
  WORKBENCH_ACTION_REQUEST_FILE="$request_file" WORKBENCH_ACTION_OPEN_FILE="$open_file" \
  WORKBENCH_ACTION_LAUNCH_FILE="$launch_file" WORKBENCH_ACTION_NOTIFICATION_FILE="$notification_file" \
  "$repo_dir/hypr/scripts/kage-project-rofi.sh"

sed -n '1p' "$request_file" | grep -Fx 'http://127.0.0.1:5517/actions/interactive/run' >/dev/null
for _attempt in $(seq 1 50); do
  [ -s "$launch_file" ] && break
  sleep 0.01
done
grep -Fx 'execution-id' "$launch_file" >/dev/null
printf 'workbench canonical action adapter: ok\n'
