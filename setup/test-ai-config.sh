#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
opencode="$root/configs/opencode/opencode.local-llamacpp.json"
runtime="$root/configs/opencode/mcp-runtime-package.json"

command -v jq >/dev/null 2>&1 || {
  printf 'jq is required\n' >&2
  exit 1
}
jq -e '.model == "minimax-coding-plan/MiniMax-M2.7" and (.enabled_providers | index("opencode-go") | not)' "$opencode" >/dev/null
jq -e '(.dependencies | has("mcp-orchestrate") | not)' "$runtime" >/dev/null

if rg -n -i 'mcp-orchestrate|orchestrate-mcp|opencode-goal-plugin|opencode-snip|opencode-go' \
  "$root/configs" "$root/setup" "$root/ai" "$root/docs" "$root/README.md" \
  --glob '!*.jsonl' --glob '!setup/test-ai-config.sh' >/dev/null; then
  printf 'retired AI integration reference found\n' >&2
  exit 1
fi

printf 'AI configuration and retired-integration checks: ok\n'
