#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
cleanup() {
  find "$test_dir" -type l -delete 2>/dev/null || true
  find "$test_dir" -type f -delete 2>/dev/null || true
  find "$test_dir" -depth -type d -empty -delete 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$test_dir/nvm" "$test_dir/bin" "$test_dir/project/nested" "$test_dir/no-version"
cat >"$test_dir/nvm/nvm-exec" <<'MOCK'
#!/usr/bin/env bash
if [[ -n "${MOCK_PATH_FILE:-}" ]]; then
  printf '%s\n' "$PATH" >"$MOCK_PATH_FILE"
fi
printf '%s|%s\n' "${NODE_VERSION-unset}" "$*"
MOCK
chmod +x "$test_dir/nvm/nvm-exec"

for command_name in node npm npx; do
  ln -s "$repo_dir/system/node-runtime" "$test_dir/bin/$command_name"
done
ln -s "$repo_dir/system/pnpm" "$test_dir/bin/pnpm"

printf '22\n' >"$test_dir/project/.nvmrc"
project_result="$(cd "$test_dir/project/nested" && NODE_VERSION=24 NVM_DIR="$test_dir/nvm" \
  "$test_dir/bin/node" --version)"
[[ "$project_result" == 'unset|node --version' ]]

default_result="$(cd "$test_dir/no-version" && env -u NODE_VERSION NVM_DIR="$test_dir/nvm" \
  "$test_dir/bin/npm" run test -- --color)"
[[ "$default_result" == 'default|npm run test -- --color' ]]

path_file="$test_dir/path"
PATH="$test_dir/nvm/versions/node/v1/bin:$test_dir/bin:/usr/bin" \
  MOCK_PATH_FILE="$path_file" NVM_DIR="$test_dir/nvm" "$test_dir/bin/node" --version >/dev/null
[[ "$(<"$path_file")" == "$test_dir/bin:/usr/bin" ]]

override_result="$(cd "$test_dir/project" && NVM_DIR="$test_dir/nvm" \
  AI_WORKBENCH_NODE_VERSION=24.20.0 "$test_dir/bin/npx" expo --version)"
[[ "$override_result" == '24.20.0|npx expo --version' ]]

pnpm_result="$(cd "$test_dir/project" && NVM_DIR="$test_dir/nvm" \
  "$test_dir/bin/pnpm" typecheck --filter app)"
[[ "$pnpm_result" == 'unset|corepack pnpm typecheck --filter app' ]]

if NVM_DIR="$test_dir/missing" "$test_dir/bin/node" --version 2>"$test_dir/error"; then
  printf 'node runtime bridge must fail when NVM is unavailable\n' >&2
  exit 1
fi
grep -F 'NVM launcher is unavailable' "$test_dir/error" >/dev/null

printf 'node runtime bridge: ok\n'
