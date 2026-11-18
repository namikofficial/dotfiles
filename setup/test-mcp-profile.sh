#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
scoped="$root/configs/opencode/mcp-scoped.sh"
profile="$root/setup/mcp-profile.sh"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

expected='export NOXFLOW_MCP_PROFILE=notes'
[ "$("$profile" env notes)" = "$expected" ]
if "$profile" env invalid >/dev/null 2>&1; then
  printf 'invalid profile unexpectedly accepted\n' >&2
  exit 1
fi
for server in codegraph playwright obsidian local-docs; do
  for mode in minimal dev web notes mobile; do
    if NOXFLOW_MCP_PROFILE="$mode" "$scoped" "$server" >/dev/null 2>&1; then
      printf 'retired server %s unexpectedly available in %s\n' "$server" "$mode" >&2
      exit 1
    fi
  done
done
cat >"$test_dir/chrome-devtools-mcp" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*"
MOCK
cat >"$test_dir/maestro" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*"
MOCK
chmod +x "$test_dir/chrome-devtools-mcp" "$test_dir/maestro"
browser_args="$(NOXFLOW_MCP_PROFILE=web CHROME_DEVTOOLS_MCP_BIN="$test_dir/chrome-devtools-mcp" "$scoped" browser)"
[[ "$browser_args" == *--autoConnect* ]]
maestro_args="$(PATH="$test_dir:$PATH" NOXFLOW_MCP_PROFILE=mobile "$scoped" maestro --test)"
[ "$maestro_args" = 'mcp --test' ]
if NOXFLOW_MCP_PROFILE=minimal "$scoped" browser >/dev/null 2>&1; then
  printf 'minimal profile unexpectedly launched browser\n' >&2
  exit 1
fi
printf 'mcp profile: ok\n'
