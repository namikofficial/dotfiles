#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
scoped="$root/configs/opencode/mcp-scoped.sh"
profile="$root/setup/mcp-profile.sh"

test_rc=0
NOXFLOW_MCP_PROFILE=minimal "$scoped" codegraph >/dev/null 2>&1 || test_rc=$?
[ "$test_rc" -eq 78 ] || {
  printf 'expected minimal/codegraph to exit 78, got %s\n' "$test_rc" >&2
  exit 1
}

expected='export NOXFLOW_MCP_PROFILE=notes'
actual="$($profile env notes)"
[ "$actual" = "$expected" ] || {
  printf 'unexpected profile export: %s\n' "$actual" >&2
  exit 1
}

if "$profile" env invalid >/dev/null 2>&1; then
  printf 'invalid profile unexpectedly accepted\n' >&2
  exit 1
fi

status_output="$($profile status)"
printf '%s\n' "$status_output" | grep -Fq 'profile=' || {
  printf 'status did not report the active profile\n' >&2
  exit 1
}

printf 'mcp profile: ok\n'
