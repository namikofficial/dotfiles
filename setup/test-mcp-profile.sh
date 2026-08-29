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

test_dir="$(mktemp -d)"
cleanup() {
  find "$test_dir" -type f -delete 2>/dev/null || true
  find "$test_dir" -depth -type d -empty -delete 2>/dev/null || true
}
trap cleanup EXIT
mkdir -p "$test_dir/node_modules/.bin"
cat >"$test_dir/node_modules/.bin/codegraph" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*"
MOCK
chmod +x "$test_dir/node_modules/.bin/codegraph"
codegraph_args="$(NOXFLOW_MCP_PROFILE=dev OPENCODE_MCP_HOME="$test_dir" "$scoped" codegraph --no-watch)"
[ "$codegraph_args" = 'serve --mcp --no-watch' ] || {
  printf 'unexpected codegraph launcher args: %s\n' "$codegraph_args" >&2
  exit 1
}

cat >"$test_dir/obsidian-mcp-server" <<'MOCK'
#!/usr/bin/env bash
printf 'obsidian-launcher-ok\n'
MOCK
cat >"$test_dir/mcp-orchestrate" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*"
MOCK
chmod +x "$test_dir/obsidian-mcp-server" "$test_dir/mcp-orchestrate"

obsidian_result="$(OBSIDIAN_ENV_FILE="$test_dir/missing.env" \
  OBSIDIAN_REST_CONFIG="$test_dir/missing.json" OBSIDIAN_CERT_PATH="$test_dir/missing.crt" \
  OBSIDIAN_VAULT_PATH="$test_dir" OBSIDIAN_MCP_BIN="$test_dir/obsidian-mcp-server" \
  "$root/configs/opencode/obsidian-mcp.sh")"
[ "$obsidian_result" = 'obsidian-launcher-ok' ] || {
  printf 'unexpected obsidian launcher result: %s\n' "$obsidian_result" >&2
  exit 1
}

orchestrate_args="$(MCP_ORCHESTRATE_BIN="$test_dir/mcp-orchestrate" \
  "$root/configs/opencode/orchestrate-mcp.sh" --check router.json)"
[ "$orchestrate_args" = '--check router.json' ] || {
  printf 'unexpected orchestrate launcher args: %s\n' "$orchestrate_args" >&2
  exit 1
}

printf 'mcp profile: ok\n'
