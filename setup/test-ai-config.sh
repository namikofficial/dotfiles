#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
opencode="$root/configs/opencode/opencode.local-llamacpp.json"
runtime="$root/configs/opencode/mcp-runtime-package.json"
quota="$root/configs/opencode/opencode-quota/quota-toast.json"
tui="$root/configs/opencode/tui.json"

command -v jq >/dev/null 2>&1 || {
  printf 'jq is required\n' >&2
  exit 1
}
jq -e --argjson root "$(jq -c . "$opencode")" '.model == "minimax-coding-plan/MiniMax-M2.7" and .small_model == "minimax-coding-plan/MiniMax-M2.7" and (["build", "plan", "explore", "worker", "review", "web-verifier", "android-verifier", "ui-specialist", "ask"] | all(.[]; $root.agent[.].model == "minimax-coding-plan/MiniMax-M2.7")) and .agent["worker-m3"].model == "minimax-coding-plan/MiniMax-M3" and .agent.expert.model == "openai/gpt-5.6-luna" and (.enabled_providers | index("opencode-go") | not) and (.enabled_providers | index("google") | not)' "$opencode" >/dev/null
jq -e '.provider.openai.models | has("gpt-5.6-luna") and has("gpt-5.6-luna-fast") and has("gpt-5.6-terra")' "$opencode" >/dev/null
jq -e '.provider["minimax-coding-plan"].models | has("MiniMax-M3") and has("MiniMax-M2.7") and has("MiniMax-M2.5") and has("MiniMax-M2.1")' "$opencode" >/dev/null
jq -e '([.provider[].models | keys[]] + [.small_model] + [.agent[].model // empty] | map(tostring)) | all(. != "" and (contains("google/") | not) and (contains("highspeed") | not))' "$opencode" >/dev/null
jq -e '.permission["codegraph_*"] == "deny" and .permission["maestro_*"] == "deny" and .permission["browser_*"] == "deny" and .permission["stitch_*"] == "deny" and .agent.explore.permission["codegraph_*"] == "allow" and .agent["web-verifier"].permission["browser_*"] == "allow" and .agent["android-verifier"].permission["maestro_*"] == "allow" and .agent["ui-specialist"].permission["stitch_*"] == "allow"' "$opencode" >/dev/null
jq -e '.permission.skill["*"] == "deny" and .agent.build.permission.skill["code-intelligence"] == "allow" and .agent.review.permission.skill["regression-hunter"] == "allow" and .agent.expert.permission.skill["architecture-fitness"] == "allow" and .agent["ui-specialist"].permission.skill["nox-ui-judge"] == "allow"' "$opencode" >/dev/null
jq -e '.agent.build.permission.task["*"] == "deny" and .agent.build.permission.task.worker == "allow" and .agent.build.permission.task.review == "allow" and .agent.build.permission.task.expert == "allow"' "$opencode" >/dev/null
jq -e '.compaction.prune == true and (.plugin | map(tostring) | any(contains("@slkiser/opencode-quota@4.8.0"))) and (.plugin | map(tostring) | any(contains("opencode-tool-search@0.4.3")))' "$opencode" >/dev/null
jq -e '(.dependencies | has("mcp-orchestrate") | not)' "$runtime" >/dev/null
jq -e '.tuiSidebarPanel.enabled == true and .enableToast == false and .tuiCompactStatus.enabled == false and .enabledProviders == "auto"' "$quota" >/dev/null
jq -e '(.plugin | index("@slkiser/opencode-quota@4.8.0")) != null' "$tui" >/dev/null

if rg -n -i 'mcp-orchestrate|orchestrate-mcp|opencode-goal-plugin|opencode-snip|opencode-go' \
  "$root/configs" "$root/setup" "$root/ai" "$root/docs" "$root/README.md" \
  --glob '!*.jsonl' --glob '!setup/test-ai-config.sh' >/dev/null; then
  printf 'retired AI integration reference found\n' >&2
  exit 1
fi

printf 'AI configuration and retired-integration checks: ok\n'
