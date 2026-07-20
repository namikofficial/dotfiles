#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
cleanup() {
  find "$test_dir" -type f -delete 2>/dev/null || true
  find "$test_dir" -depth -type d -empty -delete 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$test_dir/nvm" "$test_dir/project/nested" "$test_dir/no-version"
cat >"$test_dir/nvm/nvm-exec" <<'MOCK'
#!/usr/bin/env bash
printf '%s|%s\n' "${NODE_VERSION:-}" "$*"
MOCK
chmod +x "$test_dir/nvm/nvm-exec"

default_result="$(cd "$test_dir/no-version" && NVM_DIR="$test_dir/nvm" \
  "$repo_dir/system/pnpm" lint --no-color)"
[[ "$default_result" == 'lts/*|pnpm lint --no-color' ]]

printf 'v24\n' >"$test_dir/project/.nvmrc"
project_result="$(cd "$test_dir/project/nested" && env -u NODE_VERSION \
  NVM_DIR="$test_dir/nvm" "$repo_dir/system/pnpm" typecheck)"
[[ "$project_result" == '|pnpm typecheck' ]]

override_result="$(cd "$test_dir/no-version" && NVM_DIR="$test_dir/nvm" \
  AI_WORKBENCH_NODE_VERSION='v22' "$repo_dir/system/pnpm" test:fast)"
[[ "$override_result" == 'v22|pnpm test:fast' ]]

missing_error="$test_dir/missing-error"
if NVM_DIR="$test_dir/missing" "$repo_dir/system/pnpm" lint 2>"$missing_error"; then
  printf 'pnpm bridge must fail when nvm-exec is unavailable\n' >&2
  exit 1
fi
grep -F 'NVM launcher is unavailable' "$missing_error" >/dev/null

printf 'pnpm runtime bridge: ok\n'
