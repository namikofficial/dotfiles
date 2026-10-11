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
jq -e --argjson root "$(jq -c . "$opencode")" '.model == "minimax-coding-plan/MiniMax-M2.7" and .small_model == "minimax-coding-plan/MiniMax-M2.7" and (["build", "plan", "explore-m2.7", "worker-m2.7"] | all(.[]; $root.agent[.].model == "minimax-coding-plan/MiniMax-M2.7")) and .agent["explore-m2.5"].model == "minimax-coding-plan/MiniMax-M2.5" and .agent["worker-m3"].model == "minimax-coding-plan/MiniMax-M3" and .agent["worker-m3.1"].model == "minimax-coding-plan/MiniMax-M3.1-Flash-Preview" and .agent["worker-m3.1"].mode == "subagent" and .agent["worker-luna"].model == "openai/gpt-5.6-luna" and .agent["worker-luna"].variant == "medium" and (.enabled_providers | index("opencode-go") | not) and (.enabled_providers | index("google") | not)' "$opencode" >/dev/null
jq -e '.provider.openai.models | has("gpt-5.6-luna") and has("gpt-5.6-luna-fast") and has("gpt-5.6-terra")' "$opencode" >/dev/null
jq -e '.provider["minimax-coding-plan"].models | has("MiniMax-M3.1-Flash-Preview") and has("MiniMax-M3") and has("MiniMax-M2.7") and has("MiniMax-M2.5") and has("MiniMax-M2.1")' "$opencode" >/dev/null
jq -e '([.provider[].models | keys[]] + [.small_model] + [.agent[].model // empty] | map(tostring)) | all(. != "" and (contains("google/") | not) and (contains("highspeed") | not))' "$opencode" >/dev/null
jq -e '.experimental.subagent_depth == 1 and .agent.general.disable == true and (.agent | keys) == ["build", "explore-m2.5", "explore-m2.7", "general", "plan", "worker-luna", "worker-m2.7", "worker-m3", "worker-m3.1"]' "$opencode" >/dev/null
jq -e '([.permissions[] | select(.action == "skill" or .action == "browser_*" or .action == "playwright_*" or .action == "maestro_*" or .action == "stitch_*")] | length) == 0 and ([.permissions[] | select(.action == "read" and (.resource == "~/.codex/sessions/**" or .resource == "~/.ssh/**") and .effect == "deny")] | length) == 2' "$opencode" >/dev/null
jq -e '.agent.build.permission.skill == "allow" and .agent.plan.permission.skill == "allow" and .agent.build.permission.subagent == {"*":"deny","explore-m2.7":"allow","explore-m2.5":"allow","worker-m2.7":"allow","worker-m3":"allow","worker-m3.1":"allow","worker-luna":"allow"} and ([.agent["explore-m2.7"], .agent["explore-m2.5"], .agent["worker-m2.7"], .agent["worker-m3"], .agent["worker-m3.1"], .agent["worker-luna"]] | all(.permission.skill == "allow" and .permission.subagent == "deny")) and ([.agent["explore-m2.7"], .agent["explore-m2.5"]] | all(.permission.edit == "deny"))' "$opencode" >/dev/null
jq -e '(.agent | {build: .build.steps, plan: .plan.steps, "explore-m2.7": .["explore-m2.7"].steps, "explore-m2.5": .["explore-m2.5"].steps, "worker-m2.7": .["worker-m2.7"].steps, "worker-m3": .["worker-m3"].steps, "worker-m3.1": .["worker-m3.1"].steps, "worker-luna": .["worker-luna"].steps}) == {build: 250, plan: 120, "explore-m2.7": 60, "explore-m2.5": 50, "worker-m2.7": 200, "worker-m3": 220, "worker-m3.1": 200, "worker-luna": 160}' "$opencode" >/dev/null
jq -e '.mcp.servers.browser.environment.NOXFLOW_MCP_PROFILE == "web" and .mcp.servers.playwright.environment.NOXFLOW_MCP_PROFILE == "web" and .mcp.servers.maestro.environment.NOXFLOW_MCP_PROFILE == "mobile" and .mcp.servers.codegraph.environment.NOXFLOW_MCP_PROFILE == "dev" and .mcp.servers.v0.type == "remote" and .mcp.servers.v0.url == "https://v0.app/api/mcp" and .mcp.servers.vp0.command == ["npx", "-y", "vp0-mcp"] and .mcp.servers.stitch.url == "https://stitch.googleapis.com/mcp" and .mcp.servers.stitch.oauth == false and ([.mcp.servers[] | has("enabled")] | any | not) and ([.mcp.servers[] | (.disabled // false)] | all(. == false)) and (.mcp.servers | keys) == ["browser", "codegraph", "maestro", "playwright", "stitch", "v0", "vp0"]' "$opencode" >/dev/null
jq -e '.tool_output.max_lines == 500 and .tool_output.max_bytes == 32768 and .compaction.auto == true and .compaction.keep.tokens == 30000 and .compaction.buffer == 24000' "$opencode" >/dev/null
jq -e '.mcp.servers.codegraph.timeout == {"catalog":60000,"execution":120000} and .mcp.servers.maestro.timeout == {"catalog":120000,"execution":600000} and .mcp.servers.browser.timeout == {"catalog":120000,"execution":600000} and .mcp.servers.playwright.timeout == {"catalog":120000,"execution":600000} and ([.mcp.servers.v0, .mcp.servers.vp0, .mcp.servers.stitch] | all(.timeout == null))' "$opencode" >/dev/null
jq -e '(.watcher.ignore | index("**/target/**")) != null and (.watcher.ignore | index("target/**")) != null and (.watcher.ignore | index(".codegraph/**")) != null' "$opencode" >/dev/null
jq -e '([.instructions[]] | any(contains("NOXORIGIN_SYSTEM.md"))) | not' "$opencode" >/dev/null
jq -e '([.instructions[]] | any(contains("worker_contract.md"))) | not' "$opencode" >/dev/null
jq -e '([.instructions[] | select(contains("quality_contract.md") or contains("verification_policy.md"))] | length) == 2' "$opencode" >/dev/null
while IFS= read -r instruction; do
  [ -f "$instruction" ] || {
    printf 'missing instruction file: %s\n' "$instruction" >&2
    exit 1
  }
done < <(jq -r '.instructions[]' "$opencode")
jq -e '(([.agent.build.permission.subagent | to_entries[] | select(.key != "*") | .key]) - (.agent | keys)) == []' "$opencode" >/dev/null
jq -e '([.agent | to_entries[] | select(.key != "general") | .value]) | (all(.[]; ((.description // "") | length) > 0)) and (all(.[]; ((.model // "") | length) > 0))' "$opencode" >/dev/null
jq -e '([.agent[] | select(.mode == "subagent") | .prompt] | all(contains("worker_contract.md")))' "$opencode" >/dev/null
jq -e '.commands | keys == ["fix", "ui"]' "$opencode" >/dev/null
jq -e '(.commands.ui.template | contains("building-native-ui") and contains("mobile-design") and contains("anti-ui-slop") and contains("emil-design-eng") and contains("NOXORIGIN_SYSTEM.md"))' "$opencode" >/dev/null
jq -e '(.plugins | length) == 2 and ([.plugins[] | (if type == "string" then . else .package end) | contains("tmux-tools") or contains("safety-guards")] | all) and ([.plugins[] | select(type == "object" and (.package | contains("tmux-tools"))) | .options == {socketName: "nox", sharedSessions: ["nox"]}] | all)' "$opencode" >/dev/null
jq -e '(.plugins? // []) == []' "$cli" >/dev/null
rg -q 'force_link .*plugins/quota-v2' "$root/setup/normalize-links.sh"
jq -e '(.mcp? // {}) | ((has("maestro") or ((.servers? // {}) | has("maestro"))) | not)' "$root/.opencode/opencode.json" >/dev/null
jq -e '.plugin == []' "$root/configs/opencode/tui.json" >/dev/null
rg -q 'Plugin.define' "$root/configs/opencode/plugins/quota-v2/tui.ts"
rg -q 'dist/tui-v2.js' "$root/configs/opencode/plugins/quota-v2/tui.ts"
rg -q 'upstream.setup' "$root/configs/opencode/plugins/quota-v2/tui.ts"
rg -q 'keymap.layer' "$root/configs/opencode/plugins/quota-v2/tui.ts"
jq -e '.exports["./tui"] == "./tui.ts"' "$root/configs/opencode/plugins/quota-v2/package.json" >/dev/null
rg -q 'id: "nox.linux-notify"' "$root/configs/opencode/plugins/linux-notify/tui.ts"
node --test "$root/configs/opencode/plugins/__tests__/quota-command-filter.test.mjs" >/dev/null
jq -e '.["$schema"] == "https://opencode.ai/v2/cli.json" and .theme == {name: "noxflow-dynamic", mode: "dark"} and .diffs.wrap == "word" and .session.sidebar == "auto" and .session.scrollbar == false and .session.thinking == "show" and .animations == true' "$cli" >/dev/null
jq -e '(.dependencies | has("mcp-orchestrate") | not)' "$runtime" >/dev/null
jq -e '.tuiSidebarPanel.enabled == true and .enableToast == false and .tuiCompactStatus.enabled == true and .enabledProviders == "auto" and .requestTimeoutMs == 15000' "$quota" >/dev/null
rg -q '75d9b5dbc01ed2e3e4ad1a609f9203912a2a4f8f' "$root/setup/install-opencode-quota-v2.sh"
rg -n -- '--autoConnect' "$chrome_launcher" >/dev/null
! rg -n -- '--userDataDir|CHROME_DEVTOOLS_MCP_USER_DATA_DIR' "$chrome_launcher" >/dev/null

if rg -n -i 'mcp-orchestrate|orchestrate-mcp|opencode-goal-plugin|opencode-snip|opencode-go' \
  "$root/configs" "$root/setup" "$root/ai" "$root/docs" "$root/README.md" \
  --glob '!*.jsonl' --glob '!setup/test-ai-config.sh' >/dev/null; then
  printf 'retired AI integration reference found\n' >&2
  exit 1
fi

printf 'AI configuration and retired-integration checks: ok\n'
