#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"

for tool in codex opencode; do
  cat >"$test_dir/bin/$tool" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@"
MOCK
  chmod +x "$test_dir/bin/$tool"
done

launcher="$root/setup/ai-session.sh"
export PATH="$test_dir/bin:$PATH"

actual="$("$launcher" opencode --yolo --session 'session id')"
expected=$'--yolo\n--session\nsession id'
[[ "$actual" == "$expected" ]] || {
  printf 'OpenCode arguments changed: %s\n' "$actual" >&2
  exit 1
}

actual="$(AI_SESSION_PROFILE=design "$launcher" codex exec --json)"
expected=$'--profile\ndesign\nexec\n--json'
[[ "$actual" == "$expected" ]] || {
  printf 'Codex explicit overlay was not applied: %s\n' "$actual" >&2
  exit 1
}

actual="$(AI_SESSION_PROFILE=design "$launcher" codex --profile notes exec)"
expected=$'--profile\nnotes\nexec'
[[ "$actual" == "$expected" ]] || {
  printf 'Explicit CLI profile was not preserved: %s\n' "$actual" >&2
  exit 1
}

if AI_SESSION_PROFILE=design "$launcher" opencode >/dev/null 2>&1; then
  printf 'OpenCode unexpectedly accepted a Codex-only overlay\n' >&2
  exit 1
fi

explanation="$("$launcher" --explain --dry-run opencode 2>&1)"
[[ "$explanation" == *'routing=direct'* && "$explanation" == *'agent selection=none'* && "$explanation" != *'agent='* ]] || {
  printf 'launcher explanation is misleading\n' >&2
  exit 1
}

printf 'AI session launcher: ok\n'
