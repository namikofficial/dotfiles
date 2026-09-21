#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
opencode="$root/configs/opencode/opencode.local-llamacpp.json"
runtime="$root/configs/opencode/mcp-runtime-package.json"
quota="$root/configs/opencode/opencode-quota/quota-toast.json"
cli="$root/configs/opencode/cli.json"
chrome_launcher="$root/configs/opencode/chrome-devtools-mcp.sh"

command -v jq >/dev/null 2>&1 || {
  printf 'jq is required\n' >&2
  exit 1
}
jq -e --argjson root "$(jq -c . "$opencode")" '.model == "minimax-coding-plan/MiniMax-M2.7" and .small_model == "minimax-coding-plan/MiniMax-M2.7" and (["build", "plan", "explore", "worker", "review", "web-verifier", "android-verifier", "ui-specialist", "ask", "security-audit", "devops-run"] | all(.[]; $root.agent[.].model == "minimax-coding-plan/MiniMax-M2.7")) and .agent["worker-m3"].model == "minimax-coding-plan/MiniMax-M3" and .agent["explore-m3"].model == "minimax-coding-plan/MiniMax-M3" and .agent["worker-luna"].model == "openai/gpt-5.6-luna" and .agent["worker-luna"].variant == "medium" and .agent.expert.model == "openai/gpt-5.6-luna" and (.enabled_providers | index("opencode-go") | not) and (.enabled_providers | index("google") | not)' "$opencode" >/dev/null
jq -e '.provider.openai.models | has("gpt-5.6-luna") and has("gpt-5.6-luna-fast") and has("gpt-5.6-terra")' "$opencode" >/dev/null
jq -e '.provider["minimax-coding-plan"].models | has("MiniMax-M3") and has("MiniMax-M2.7") and has("MiniMax-M2.5") and has("MiniMax-M2.1")' "$opencode" >/dev/null
jq -e '([.provider[].models | keys[]] + [.small_model] + [.agent[].model // empty] | map(tostring)) | all(. != "" and (contains("google/") | not) and (contains("highspeed") | not))' "$opencode" >/dev/null
jq -e '.permissions == [{action:"*",resource:"*",effect:"allow"}] and .experimental.subagent_depth == 2 and ([.agent[] | .permission.question] | all(. == "allow"))' "$opencode" >/dev/null
# Implementation/verification agents retain full access
jq -e '([.agent["build"], .agent["worker"], .agent["worker-m3"], .agent["worker-luna"], .agent["web-verifier"], .agent["android-verifier"], .agent["ui-specialist"], .agent["devops-run"]] | map(.permission["*"]) | all(. == "allow"))' "$opencode" >/dev/null
jq -e '([.agent["build"], .agent["worker"], .agent["worker-m3"], .agent["worker-luna"], .agent["web-verifier"], .agent["android-verifier"], .agent["ui-specialist"], .agent["devops-run"]] | map(.permission.read["*.env"]) | all(. == "allow"))' "$opencode" >/dev/null
jq -e '([.agent["build"], .agent["worker"], .agent["worker-m3"], .agent["worker-luna"], .agent["web-verifier"], .agent["android-verifier"], .agent["ui-specialist"], .agent["devops-run"]] | map(.permission.external_directory["*"]) | all(. == "allow"))' "$opencode" >/dev/null
# Read-only agents have explicit denies
jq -e '([.agent["plan"], .agent["explore"], .agent["review"], .agent["ask"], .agent["expert"], .agent["security-audit"], .agent["explore-m3"]] | map(.permission.shell) | all(. == "deny"))' "$opencode" >/dev/null
jq -e '([.agent["plan"], .agent["explore"], .agent["review"], .agent["ask"], .agent["expert"], .agent["security-audit"], .agent["explore-m3"]] | map(.permission.external_directory) | all(. == "deny"))' "$opencode" >/dev/null
jq -e '(.agent | {build: .build.steps, plan: .plan.steps, explore: .explore.steps, worker: .worker.steps, review: .review.steps, "worker-m3": .["worker-m3"].steps, "worker-luna": .["worker-luna"].steps, expert: .expert.steps, "web-verifier": .["web-verifier"].steps, "android-verifier": .["android-verifier"].steps, "ui-specialist": .["ui-specialist"].steps, ask: .ask.steps, "security-audit": .["security-audit"].steps, "devops-run": .["devops-run"].steps, "explore-m3": .["explore-m3"].steps}) == {build: 180, plan: 120, explore: 60, worker: 140, review: 100, "worker-m3": 220, "worker-luna": 160, expert: 80, "web-verifier": 100, "android-verifier": 100, "ui-specialist": 140, ask: 20, "security-audit": 100, "devops-run": 100, "explore-m3": 80}' "$opencode" >/dev/null
jq -e '.mcp.browser.enabled == false and .mcp.browser.environment.NOXFLOW_MCP_PROFILE == "web" and .mcp.playwright.enabled == false and .mcp.playwright.environment.NOXFLOW_MCP_PROFILE == "web" and .mcp.codegraph.enabled == true and .mcp.maestro.enabled == false and .mcp.maestro.environment.NOXFLOW_MCP_PROFILE == "mobile" and .mcp.stitch.enabled == false' "$opencode" >/dev/null
jq -e '.tool_output.max_lines == 800 and .tool_output.max_bytes == 65536 and .compaction.auto == true and .compaction.keep.tokens == 8000 and .compaction.buffer == 16000' "$opencode" >/dev/null
jq -e '([.instructions[]] | any(contains("NOXORIGIN_SYSTEM.md"))) | not' "$opencode" >/dev/null
jq -e '.commands | keys == ["auto", "fix", "handoff", "ui"]' "$opencode" >/dev/null
jq -e '(.plugins | length) == 2 and ([.plugins[] | contains("tmux-tools") or contains("safety-guards")] | all)' "$opencode" >/dev/null
jq -e '(.plugins? // []) == []' "$cli" >/dev/null
rg -q 'force_link .*plugins/quota-v2' "$root/setup/normalize-links.sh"
jq -e '(.mcp? // {}) | (has("maestro") | not)' "$root/.opencode/opencode.json" >/dev/null
jq -e '.plugin == []' "$root/configs/opencode/tui.json" >/dev/null
rg -q 'Plugin.define' "$root/configs/opencode/plugins/quota-v2/tui.ts"
rg -q 'dist/tui-v2.js' "$root/configs/opencode/plugins/quota-v2/tui.ts"
rg -q 'upstream.setup' "$root/configs/opencode/plugins/quota-v2/tui.ts"
rg -q 'keymap.layer' "$root/configs/opencode/plugins/quota-v2/tui.ts"
jq -e '.exports["./tui"] == "./tui.ts"' "$root/configs/opencode/plugins/quota-v2/package.json" >/dev/null
rg -q 'id: "nox.linux-notify"' "$root/configs/opencode/plugins/linux-notify/tui.ts"
node --test "$root/configs/opencode/plugins/__tests__/quota-command-filter.test.mjs" >/dev/null
jq -e '.["$schema"] == "https://opencode.ai/v2/cli.json" and .theme == {name: "system", mode: "light"} and .diffs.wrap == "word" and .session.sidebar == "auto" and .session.scrollbar == false and .session.thinking == "show" and .animations == true' "$cli" >/dev/null
jq -e '(.dependencies | has("mcp-orchestrate") | not)' "$runtime" >/dev/null
jq -e '.tuiSidebarPanel.enabled == true and .enableToast == false and .tuiCompactStatus.enabled == true and .enabledProviders == "auto" and .requestTimeoutMs == 15000' "$quota" >/dev/null
rg -q '75d9b5dbc01ed2e3e4ad1a609f9203912a2a4f8f' "$root/setup/install-opencode-quota-v2.sh"
! rg -n -- '--autoConnect' "$chrome_launcher" >/dev/null
rg -n -- '--userDataDir' "$chrome_launcher" >/dev/null

if rg -n -i 'mcp-orchestrate|orchestrate-mcp|opencode-goal-plugin|opencode-snip|opencode-go' \
  "$root/configs" "$root/setup" "$root/ai" "$root/docs" "$root/README.md" \
  --glob '!*.jsonl' --glob '!setup/test-ai-config.sh' >/dev/null; then
  printf 'retired AI integration reference found\n' >&2
  exit 1
fi

printf 'AI configuration and retired-integration checks: ok\n'
