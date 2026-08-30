#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
cleanup() {
  find "$test_dir" -type f -delete 2>/dev/null || true
  find "$test_dir" -depth -type d -empty -delete 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$test_dir/bin" "$test_dir/runtime"
log_file="$test_dir/launch.log"

cat >"$test_dir/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' 'WAYLAND_DISPLAY=wayland-test' 'DISPLAY=:99' 'XDG_CURRENT_DESKTOP=Hyprland'
MOCK
cat >"$test_dir/bin/uwsm" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == check && "$2" == is-active ]]; then
  [[ "${MOCK_UWSM_ACTIVE:-1}" == 1 ]]
  exit
fi
printf 'env=%s|%s|%s\n' "$WAYLAND_DISPLAY" "$DISPLAY" "$XDG_CURRENT_DESKTOP" >>"$DESKTOP_TEST_LOG"
printf 'args=' >>"$DESKTOP_TEST_LOG"
printf '<%s>' "$@" >>"$DESKTOP_TEST_LOG"
printf '\n' >>"$DESKTOP_TEST_LOG"
MOCK
cat >"$test_dir/bin/code-real" <<'MOCK'
#!/usr/bin/env bash
printf 'code=' >>"$DESKTOP_TEST_LOG"
printf '<%s>' "$@" >>"$DESKTOP_TEST_LOG"
printf '\n' >>"$DESKTOP_TEST_LOG"
MOCK
chmod +x "$test_dir/bin/systemctl" "$test_dir/bin/uwsm" "$test_dir/bin/code-real"

PATH="$test_dir/bin:$PATH" XDG_RUNTIME_DIR="$test_dir/runtime" DESKTOP_TEST_LOG="$log_file" \
  "$repo_dir/system/desktop-launch" sample-app 'argument with spaces'
grep -F 'env=wayland-test|:99|Hyprland' "$log_file" >/dev/null
grep -F 'args=<app><-t><service><-S><both><--><sample-app><argument with spaces>' "$log_file" >/dev/null

if PATH="$test_dir/bin:$PATH" XDG_RUNTIME_DIR="$test_dir/runtime" MOCK_UWSM_ACTIVE=0 \
  DESKTOP_TEST_LOG="$log_file" "$repo_dir/system/desktop-launch" sample-app 2>"$test_dir/error"; then
  printf 'desktop-launch must fail without an active session\n' >&2
  exit 1
fi
grep -F 'no active UWSM graphical session' "$test_dir/error" >/dev/null

: >"$log_file"
PATH="$test_dir/bin:$PATH" XDG_RUNTIME_DIR="$test_dir/runtime" DESKTOP_TEST_LOG="$log_file" \
  NOXFLOW_CODE_BIN="$test_dir/bin/code-real" "$repo_dir/system/code" --status
grep -F 'code=<--status>' "$log_file" >/dev/null
if grep -F 'args=' "$log_file" >/dev/null; then
  printf 'code query command must not use the graphical launcher\n' >&2
  exit 1
fi

: >"$log_file"
PATH="$test_dir/bin:$PATH" XDG_RUNTIME_DIR="$test_dir/runtime" DESKTOP_TEST_LOG="$log_file" \
  NOXFLOW_CODE_BIN="$test_dir/bin/code-real" "$repo_dir/system/code" .
grep -F "args=<app><-t><service><-S><both><--><$test_dir/bin/code-real><.>" "$log_file" >/dev/null

printf 'desktop launch bridge: ok\n'
