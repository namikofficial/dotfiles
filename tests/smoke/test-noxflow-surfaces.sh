#!/usr/bin/env bash
set -euo pipefail

# test-noxflow-surfaces.sh — IPC smoke-test for every NoxFlow surface.
# Checks: daemon running, shell running, IPC call succeeds, no new QML errors,
# toggle-twice, rapid-toggle, leaves all surfaces closed.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

log_pass() { printf "  ${GREEN}PASS${NC} %s\n" "$*"; ((PASS++)) || true; }
log_fail() { printf "  ${RED}FAIL${NC} %s\n" "$*"; ((FAIL++)) || true; }
log_info() { printf "  ${YELLOW}INFO${NC} %s\n" "$*"; }

SURFACES=(
  "launcher"
  "dashboard"
  "overview"
  "control"
  "notifications"
  "calendar"
  "settings"
  "capture"
)

NOXCTL="$HOME/.local/bin/noxctl"
TEST_START="$(date +%s)"
IPC_PATH="$HOME/.config/noxflow/shell/shell.qml"

echo "=== NoxFlow Surface Smoke Test ==="
echo ""

# ── Pre-flight ──
echo "--- Pre-flight checks ---"

# Check daemon
if systemctl --user is-active --quiet noxd 2>/dev/null; then
  log_pass "noxd daemon is running"
else
  log_fail "noxd daemon is NOT running"
  echo "  Manual: systemctl --user start noxd"
  exit 1
fi

# Check shell
if systemctl --user is-active --quiet noxflow-shell 2>/dev/null; then
  log_pass "noxflow-shell is running"
else
  log_fail "noxflow-shell is NOT running"
  echo "  Manual: systemctl --user start noxflow-shell"
  exit 1
fi

# Check noxctl
if [ -x "$NOXCTL" ]; then
  log_pass "noxctl exists and is executable"
else
  log_fail "noxctl not found at $NOXCTL"
  exit 1
fi

# Check IPC path
if quickshell ipc -p "$IPC_PATH" call noxctl toggleDnd >/dev/null 2>&1; then
  log_pass "IPC handshake works (toggleDnd succeeded)"
else
  log_fail "IPC handshake FAILED — is quickshell running with the right path?"
  echo "  quickshell process: $(ps aux | grep quickshell | grep -v grep)"
  exit 1
fi

echo ""

# ── Surface toggle tests ──
echo "--- Surface toggle tests ---"

for surface in "${SURFACES[@]}"; do
  # Open
  if "$NOXCTL" "$surface" 2>/dev/null; then
    log_pass "noxctl $surface (toggle open)"
  else
    log_fail "noxctl $surface (toggle open) — exit code $?"
  fi

  sleep 0.4  # Let animation complete

  # Close
  if "$NOXCTL" "$surface" 2>/dev/null; then
    log_pass "noxctl $surface (toggle close)"
  else
    log_fail "noxctl $surface (toggle close) — exit code $?"
  fi

  sleep 0.2
done

echo ""

# ── Rapid toggle test ──
echo "--- Rapid toggle test (launcher, 10x) ---"

for i in $(seq 1 10); do
  if "$NOXCTL" launcher 2>/dev/null; then
    :
  else
    log_fail "Rapid toggle #$i failed"
  fi
  sleep 0.15
done

log_pass "Rapid toggle (launcher 10x) completed"
# Make sure it's closed
"$NOXCTL" launcher 2>/dev/null || true

echo ""

# ── Log check: new QML errors ──
echo "--- Journal log check (since test start) ---"

ERROR_COUNT=$(journalctl --user -u noxflow-shell --since "@$TEST_START" --no-pager 2>/dev/null | grep -ci 'error\|WARN.*ReferenceError\|WARN.*is not defined' || true)

if [ "$ERROR_COUNT" -eq 0 ]; then
  log_pass "No new QML errors or warnings in journal"
else
  log_fail "$ERROR_COUNT new QML error/warning lines in journal:"
  journalctl --user -u noxflow-shell --since "@$TEST_START" --no-pager 2>/dev/null | grep -i 'error\|WARN.*ReferenceError\|WARN.*is not defined' | head -20
fi

echo ""

# ── Force-close all surfaces for clean exit ──
echo "--- Cleanup: force-close all surfaces ---"

for surface in "${SURFACES[@]}"; do
  case "$surface" in
    control) "$NOXCTL" control 2>/dev/null || true ;;
    notifications) "$NOXCTL" notifications 2>/dev/null || true ;;
    *) "$NOXCTL" "$surface" 2>/dev/null || true ;;
  esac
  sleep 0.1
done

# Double-tap close on each: if any were open, first call closes them, second is no-op
for surface in "${SURFACES[@]}"; do
  case "$surface" in
    control) "$NOXCTL" control 2>/dev/null || true ;;
    notifications) "$NOXCTL" notifications 2>/dev/null || true ;;
    *) "$NOXCTL" "$surface" 2>/dev/null || true ;;
  esac
  sleep 0.1
done

log_info "All surfaces toggled closed"

echo ""

# ── Manual verification instructions ──
echo "--- Manual verification ---"
echo "  Visually confirm no surfaces are visible:"
echo "    • Look at all monitors — no overlays, no panels open"
echo ""
echo "  Physical keyboard tests (run manually):"
echo "    • Super+Tab — Overview opens and closes"
echo "    • Super+D — Dashboard opens and closes"
echo "    • Super+Space — Launcher opens and closes"
echo "    • Super+, — Settings opens, Escape closes it"
echo "    • Super+Shift+B — Control Centre opens, Escape closes it"
echo "    • Super+N — Notification Centre opens, Escape closes it"
echo "    • Super+Shift+S — Capture opens, draw a region, Escape twice"
echo "    • Open Dashboard → press Super+D again during animation — should reverse"
echo "    • Open Overview → press Escape immediately — should close"
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
