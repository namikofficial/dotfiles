#!/usr/bin/env bash
set -uo pipefail

# Behavioural tests for hypr/scripts/minimize-window.sh.
#
# The bug these guard against: a window parked in the hidden workspace with no
# entry in minimized-windows.json is unreachable forever, because `restore`
# only ever looks at the state file. Two mechanisms produced it:
#
#   * two concurrent `minimize` runs read the same pre-state and each wrote a
#     single-entry array (lost update);
#   * `restore` wrote the reduced state *before* attempting the move, so a
#     failed move dropped the entry while the window stayed parked.
#
# The suite drives the real script against a fake `hyprctl` (hypr/tests/
# fixtures/hyprctl) that mimics Hyprland's two relevant eval behaviours:
# "ok" for a stale window address, exit 7 for an invalid workspace.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Overridable so the suite can be pointed at the pre-fix script to prove the
# regression tests actually catch the bug.
SCRIPT="${MINIMIZE_WINDOW_SCRIPT:-$ROOT/hypr/scripts/minimize-window.sh}"
FIXTURE="$ROOT/hypr/tests/fixtures/hyprctl"

pass_count=0
fail_count=0

ok() {
  printf '  ok   %s\n' "$1"
  pass_count=$((pass_count + 1))
}

fail() {
  printf '  FAIL %s\n' "$1"
  fail_count=$((fail_count + 1))
}

assert_eq() {
  expected="$1"
  actual="$2"
  label="$3"
  if [ "$expected" = "$actual" ]; then
    ok "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

setup() {
  TEST_DIR="$(mktemp -d)"
  export XDG_STATE_HOME="$TEST_DIR/state"
  export FAKE_HYPR_STATE="$TEST_DIR/hypr.json"
  export FAKE_HYPR_ACTIVE_SEQ_COUNTER="$TEST_DIR/active.count"
  export NOTIFY_LOG="$TEST_DIR/notify.log"
  export PATH="$TEST_DIR/bin:$PATH"
  unset FAKE_HYPR_FAIL_WORKSPACES FAKE_HYPR_EVAL_SLEEP FAKE_HYPR_ACTIVE_SEQ

  mkdir -p "$XDG_STATE_HOME" "$TEST_DIR/bin"
  install -m 0755 "$FIXTURE" "$TEST_DIR/bin/hyprctl"
  cat >"$TEST_DIR/bin/notify-send" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${NOTIFY_LOG:-/dev/null}"
EOF
  chmod +x "$TEST_DIR/bin/notify-send"

  cat >"$FAKE_HYPR_STATE" <<'EOF'
{
  "active": "0xaaa",
  "active_workspace": 1,
  "workspaces": [
    {"id": 1, "name": "1"},
    {"id": 2, "name": "2"}
  ],
  "clients": [
    {"address": "0xaaa", "title": "Alpha", "class": "kitty", "fullscreen": 0, "workspace": {"id": 1, "name": "1"}},
    {"address": "0xbbb", "title": "Beta", "class": "kitty", "fullscreen": 0, "workspace": {"id": 2, "name": "2"}}
  ]
}
EOF
}

teardown() {
  [ -n "${TEST_DIR:-}" ] && rm -rf "$TEST_DIR"
}

state_file() {
  printf '%s\n' "$XDG_STATE_HOME/noxflow/minimized-windows.json"
}

state_count() {
  local file
  file="$(state_file)"
  if [ ! -f "$file" ]; then
    printf '0\n'
    return 0
  fi
  jq -r 'length' "$file" 2>/dev/null || printf '0\n'
}

state_has_address() {
  local file
  file="$(state_file)"
  [ -f "$file" ] || return 1
  jq -e --arg addr "$1" 'any(.[]; .address == $addr)' "$file" >/dev/null 2>&1
}

client_workspace_name() {
  jq -r --arg addr "$1" '
    [ .clients[] | select(.address == $addr) | .workspace.name ] | first // empty' "$FAKE_HYPR_STATE"
}

park_orphan() {
  jq '.workspaces += [{"id": -97, "name": "special:minimized"}]
      | .clients += [{"address": "0xccc", "title": "Orphan", "class": "kitty",
                      "fullscreen": 0,
                      "workspace": {"id": -97, "name": "special:minimized"}}]' \
    "$FAKE_HYPR_STATE" >"$FAKE_HYPR_STATE.new"
  mv "$FAKE_HYPR_STATE.new" "$FAKE_HYPR_STATE"
}

test_round_trip() {
  printf '\n== minimize / restore round trip ==\n'
  setup

  "$SCRIPT" minimize >/dev/null 2>&1
  assert_eq "1" "$(state_count)" "minimize records exactly one entry"
  if state_has_address 0xaaa; then
    ok "entry points at the minimized window"
  else
    fail "entry points at the minimized window"
  fi
  assert_eq "special:minimized" "$(client_workspace_name 0xaaa)" \
    "window is parked in the hidden workspace"

  "$SCRIPT" restore >/dev/null 2>&1
  assert_eq "1" "$(client_workspace_name 0xaaa)" "restore returns the window to workspace 1"
  assert_eq "0" "$(state_count)" "state file is empty after restore"

  teardown
}

test_concurrent_minimize() {
  printf '\n== concurrent minimize keeps both windows tracked ==\n'
  setup

  # The fake hands out a different active window per invocation and sleeps
  # inside eval, so the two runs genuinely overlap.
  FAKE_HYPR_ACTIVE_SEQ="0xaaa,0xbbb" FAKE_HYPR_EVAL_SLEEP=0.4 "$SCRIPT" minimize >/dev/null 2>&1 &
  first_pid=$!
  FAKE_HYPR_ACTIVE_SEQ="0xaaa,0xbbb" FAKE_HYPR_EVAL_SLEEP=0.4 "$SCRIPT" minimize >/dev/null 2>&1 &
  second_pid=$!
  wait "$first_pid"
  first_code=$?
  wait "$second_pid"
  second_code=$?

  assert_eq "0" "$first_code" "first concurrent minimize succeeds"
  assert_eq "0" "$second_code" "second concurrent minimize succeeds"
  assert_eq "2" "$(state_count)" "both windows stay tracked"
  if state_has_address 0xaaa; then
    ok "first window is tracked"
  else
    fail "first window is tracked"
  fi
  if state_has_address 0xbbb; then
    ok "second window is tracked"
  else
    fail "second window is tracked"
  fi

  teardown
}

test_failed_restore_keeps_entry() {
  printf '\n== a failed restore keeps the window reachable ==\n'
  setup

  "$SCRIPT" minimize >/dev/null 2>&1

  # The move back to workspace 1 fails; the entry must survive.
  FAKE_HYPR_FAIL_WORKSPACES="1" "$SCRIPT" restore >/dev/null 2>&1
  restore_code=$?

  if [ "$restore_code" -ne 0 ]; then
    ok "restore reports failure"
  else
    fail "restore reports failure"
  fi
  if state_has_address 0xaaa; then
    ok "entry survives the failed restore"
  else
    fail "entry survives the failed restore"
  fi
  assert_eq "special:minimized" "$(client_workspace_name 0xaaa)" \
    "window stays parked in the hidden workspace"

  teardown
}

test_recover_registers_untracked() {
  printf '\n== recover re-registers an untracked window ==\n'
  setup
  park_orphan

  "$SCRIPT" recover >/dev/null 2>&1
  recover_code=$?

  assert_eq "0" "$recover_code" "recover succeeds"
  if state_has_address 0xccc; then
    ok "orphan is now tracked"
  else
    fail "orphan is now tracked"
  fi
  assert_eq "true" \
    "$(jq -r --arg addr 0xccc '[ .[] | select(.address == $addr) | .recovered ] | first // "false"' "$(state_file)")" \
    "orphan is flagged as recovered"
  assert_eq "1" \
    "$(jq -r --arg addr 0xccc '[ .[] | select(.address == $addr) | .workspace_id ] | first // ""' "$(state_file)")" \
    "orphan is bound to the active workspace"

  teardown
}

test_list_flags_untracked() {
  printf '\n== list flags untracked windows ==\n'
  setup
  park_orphan

  output="$("$SCRIPT" list 2>/dev/null)"
  case "$output" in
    *UNTRACKED*) ok "list flags the untracked window" ;;
    *) fail "list flags the untracked window" ;;
  esac

  teardown
}

test_round_trip
test_concurrent_minimize
test_failed_restore_keeps_entry
test_recover_registers_untracked
test_list_flags_untracked

printf '\n%s passed, %s failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
