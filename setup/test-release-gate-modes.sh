#!/usr/bin/env bash
# Regression test for the release gate's mode split.
#
# The gate used to require a logged-in Hyprland desktop for every check. The
# split only means something if the session-free modes really are
# session-free, so this test shadows the desktop tools with failing stubs and
# asserts that:
#
#   * verify-static still passes with no session at all (this is what CI runs);
#   * verify-live fails without them, because it is the mode that needs the
#     desktop.
set -uo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$repo_dir/setup/release-gate.sh"

failures=0

ok() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" = "$actual" ]; then
    ok "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

printf '== the gate advertises its modes ==\n'

help_output="$(bash "$gate" --help 2>&1)"
code=$?
assert_eq 0 "$code" "--help succeeds"

for mode in verify-static verify-integration verify-live; do
  if grep -q "$mode" <<<"$help_output"; then
    ok "help lists $mode"
  else
    fail "help lists $mode"
  fi
done

bash "$gate" not-a-mode >/dev/null 2>&1
code=$?
assert_eq 2 "$code" "an unknown mode is rejected"

printf '== no shared state in /tmp ==\n'

if grep -qE '/tmp/noxflow-release-gate\.(out|err)' "$gate"; then
  fail "the gate keeps no shared /tmp output files"
else
  ok "the gate keeps no shared /tmp output files"
fi

if grep -q 'mktemp -d' "$gate" && grep -q 'trap cleanup EXIT' "$gate"; then
  ok "the gate uses an isolated directory with a cleanup trap"
else
  fail "the gate uses an isolated directory with a cleanup trap"
fi

printf '== static mode needs no desktop session ==\n'

# Shadow the desktop tools. A session-free mode must not reach for them.
shim_dir="$tmp_root/shim"
mkdir -p "$shim_dir"
for tool in systemctl quickshell journalctl; do
  printf '#!/bin/sh\necho "%s is not available in this environment" >&2\nexit 127\n' "$tool" >"$shim_dir/$tool"
  chmod +x "$shim_dir/$tool"
done

PATH="$shim_dir:$PATH" bash "$gate" verify-static >"$tmp_root/static.log" 2>&1
code=$?
if [ "$code" -eq 0 ]; then
  ok "verify-static passes without a desktop session"
else
  fail "verify-static passes without a desktop session"
  sed -n '1,20p' "$tmp_root/static.log" >&2
fi

if grep -qE 'systemctl --user (daemon-reload|is-active|restart)' "$tmp_root/static.log"; then
  fail "verify-static does not touch the user service manager"
else
  ok "verify-static does not touch the user service manager"
fi

printf '== live mode does need the desktop ==\n'

PATH="$shim_dir:$PATH" bash "$gate" verify-live >"$tmp_root/live.log" 2>&1
code=$?
if [ "$code" -ne 0 ]; then
  ok "verify-live fails when the desktop session is unavailable"
else
  fail "verify-live fails when the desktop session is unavailable"
fi

printf '\n'
if [ "$failures" -eq 0 ]; then
  printf 'release gate modes: ok\n'
  exit 0
fi
printf 'release gate modes: %d failure(s)\n' "$failures" >&2
exit 1
