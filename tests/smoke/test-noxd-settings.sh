#!/usr/bin/env bash
# Smoke test: verifies noxd settings persistence and basic IPC.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

log_pass() { printf "  ${GREEN}PASS${NC} %s\n" "$*"; ((PASS++)) || true; }
log_fail() { printf "  ${RED}FAIL${NC} %s\n" "$*"; ((FAIL++)) || true; }
log_info() { printf "  ${YELLOW}INFO${NC} %s\n" "$*"; }

NOXD_BIN="$HOME/.local/bin/noxd"
SOCK_DIR=$(mktemp -d /tmp/noxd-smoke-XXXXXX)
STATE_DIR=$(mktemp -d /tmp/noxd-state-XXXXXX)
SOCKET="$SOCK_DIR/noxflow/noxd.sock"
KEY="appearance.profile"
VALUE="material-oled"

cleanup() {
  log_info "Cleaning up..."
  kill "$NOXD_PID" 2>/dev/null || true
  rm -rf "$SOCK_DIR" "$STATE_DIR"
}
trap cleanup EXIT

send_ipc() {
  local request="$1"
  python3 -c "
import socket, json, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
s.sendall((sys.argv[2] + '\n').encode())
s.shutdown(socket.SHUT_WR)
resp = s.makefile().readline().strip()
print(resp)
" "$SOCKET" "$request"
}

echo "=== NoxD Settings Persistence Smoke Test ==="
echo ""

# ── Start daemon ──
echo "--- Starting noxd ---"
XDG_RUNTIME_DIR="$SOCK_DIR" XDG_STATE_HOME="$STATE_DIR" "$NOXD_BIN" &
NOXD_PID=$!

# Wait for socket
echo "Waiting for socket..."
for i in $(seq 1 10); do
  if [ -S "$SOCKET" ]; then
    log_pass "Socket appeared at $SOCKET"
    break
  fi
  if ! kill -0 "$NOXD_PID" 2>/dev/null; then
    log_fail "noxd died before socket appeared"
    exit 1
  fi
  sleep 0.3
done

if [ ! -S "$SOCKET" ]; then
  log_fail "Socket never appeared (timeout)"
  exit 1
fi

# ── Set setting via IPC ──
echo "--- Setting $KEY = $VALUE ---"
SET_RESP=$(send_ipc '{"version":1,"id":"test-1","method":"set_setting","params":{"key":"'"$KEY"'","value":"'"$VALUE"'"}}')
echo "  Response: $SET_RESP"

if echo "$SET_RESP" | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r.get('id') == 'test-1', f'Wrong id: {r.get(\"id\")}'
assert r.get('result', {}).get('type') == 'setting_updated', f'Unexpected result type: {r}'
d = r['result'].get('data', {})
assert d.get('key') == '$KEY', f'Wrong key: {d}'
assert d.get('value') == '$VALUE', f'Wrong value: {d}'
assert r.get('error') is None, f'Got error: {r[\"error\"]}'
"; then
  log_pass "set_setting succeeded"
else
  log_fail "set_setting failed or unexpected response"
  echo "  Response: $SET_RESP"
fi

# ── Read setting back ──
echo "--- Reading $KEY back ---"
GET_RESP=$(send_ipc '{"version":1,"id":"test-2","method":"get_setting","params":{"key":"'"$KEY"'"}}')
echo "  Response: $GET_RESP"

if echo "$GET_RESP" | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r.get('id') == 'test-2', f'Wrong id: {r.get(\"id\")}'
assert r.get('result', {}).get('type') == 'setting', f'Unexpected result type: {r}'
d = r['result'].get('data', {})
assert d.get('key') == '$KEY', f'Wrong key: {d}'
assert d.get('value') == '$VALUE', f'Wrong value: {d}'
assert r.get('error') is None, f'Got error: {r[\"error\"]}'
"; then
  log_pass "get_setting returned correct value"
else
  log_fail "get_setting failed or wrong value"
  echo "  Response: $GET_RESP"
fi

# ── Kill and restart with same state dir ──
echo "--- Restarting noxd with same state ---"
kill "$NOXD_PID" 2>/dev/null || true
wait "$NOXD_PID" 2>/dev/null || true
sleep 0.5

rm -rf "$SOCK_DIR"
mkdir -p "$SOCK_DIR"

XDG_RUNTIME_DIR="$SOCK_DIR" XDG_STATE_HOME="$STATE_DIR" "$NOXD_BIN" &
NOXD_PID=$!

# Wait for socket again
for i in $(seq 1 10); do
  if [ -S "$SOCKET" ]; then
    log_pass "Socket reappeared after restart"
    break
  fi
  if ! kill -0 "$NOXD_PID" 2>/dev/null; then
    log_fail "noxd died on restart"
    exit 1
  fi
  sleep 0.3
done

# ── Verify setting persisted ──
echo "--- Verifying setting survived restart ---"
GET_RESP2=$(send_ipc '{"version":1,"id":"test-3","method":"get_setting","params":{"key":"'"$KEY"'"}}')
echo "  Response: $GET_RESP2"

if echo "$GET_RESP2" | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r.get('id') == 'test-3', f'Wrong id: {r.get(\"id\")}'
assert r.get('result', {}).get('type') == 'setting', f'Unexpected result type: {r}'
d = r['result'].get('data', {})
assert d.get('key') == '$KEY', f'Wrong key: {d}'
assert d.get('value') == '$VALUE', f'Wrong value: {d} (persistence failed)'
assert r.get('error') is None, f'Got error: {r[\"error\"]}'
"; then
  log_pass "Setting persisted across restart!"
else
  log_fail "Setting did not survive restart"
  echo "  Response: $GET_RESP2"
fi

echo ""
echo "--- Results ---"
echo "  Passes: $PASS"
echo "  Failures: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  Status: ${RED}FAILED${NC}"
  exit 1
else
  echo "  Status: ${GREEN}PASSED${NC}"
  exit 0
fi
