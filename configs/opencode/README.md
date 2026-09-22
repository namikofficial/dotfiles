# OpenCode workflow configuration

The canonical configuration is `opencode.local-llamacpp.json` and is linked to `~/.config/opencode/opencode.json` by the existing setup scripts.

Useful commands:

```sh
scripts/opencode-capabilities.sh
scripts/opencode-permission show
scripts/opencode-permission normal
scripts/opencode-permission auto
scripts/verify /path/to/project affected
scripts/verify /path/to/project full
setup/install-verify-adapters.sh       # dry run
setup/install-verify-adapters.sh --apply
```

Configured workflow commands are `/auto`, `/handoff`, `/ui`, and `/fix`.
`/auto` classifies the request and chooses one bounded specialist handoff only
when it helps; `/handoff` makes the contract explicit; `/ui` selects UI and
verification guidance. OpenCode's quota plugin adds `/quota`. Runtime `.ai/`
artifacts are created only for large or multi-session work, not for every task.

For automatic capability selection without changing the normal `codex` or
`opencode` commands, use the explicit launcher:

```sh
setup/ai-session.sh opencode
setup/ai-session.sh codex
```

It detects repository/path, request intent, task class, and the smallest
specialist hint; prints the route; preserves every tool argument (including
`--yolo`, prompts, sessions, and explicit profiles); and supports:

```sh
setup/ai-session.sh --explain --dry-run opencode --yolo
AI_SESSION_PROFILE=mobile setup/ai-session.sh opencode
AI_SESSION_TASK=security setup/ai-session.sh codex
AI_SESSION_NO_PROFILE=1 setup/ai-session.sh codex
```

OpenCode receives the scoped MCP environment. Codex uses the design or notes
overlay only when the classifier selects it and no explicit profile was passed.
This is intentionally opt-in so a normal launch cannot unexpectedly change
profiles or hand work to another agent. After reloading zsh, `ai-opencode` and
`ai-codex` are equivalent argument-preserving shell functions.

MiniMax M2.7 is the normal model for build, plan, exploration, worker, and
review. MiniMax M3 is available through the explicit `worker-m3` escalation;
GPT-5.6 Luna (and its fast variant) is reserved for deliberate escalation.
The catalog also keeps MiniMax M2.5/M2.1 plus one GPT-5.6 Terra model for
manual selection. `ask` is the twenty-step quick repository agent.

The default profile uses bounded budgets: build 180, plan 120, explore 60,
worker 140, review 100, worker-m3 220, worker-luna 160, expert 80,
web-verifier 100, android-verifier 100, ui-specialist 140, security-audit 100,
devops-run 100, explore-m3 80, and ask 20. These are ceilings, not targets.
Escalate deliberately for migrations or long runtime debugging. `worker-luna`
uses GPT-5.6 Luna with the `medium` variant.

All configured agents and tools are permission-allowed, including shell,
external directories, skills, MCP, delegation, and destructive operations.
Use this profile only when that level of autonomy is intentional; it can
modify or delete files, expose credentials to a model, or perform irreversible
commands. OpenCode still needs to be restarted after configuration changes.

`Super+Tab` is owned by Hyprland workspace overview and is unrelated to OpenCode task execution. Use `/fix` inside OpenCode for end-to-end coding work; use `Super+Space` for the NoxFlow AI launcher.

Optional Bruno, Schemathesis, axe, Roborazzi, browser CLI, cloud-device, and physical-device checks are capability-gated. They are never silently installed or reported as passing when unavailable.

## MCP resource profiles

MCP servers are scoped by profile so every client does not start every expensive
servers. The launcher pins each configured server to its correct scoped profile
so normal OpenCode launches work without shell reconfiguration. Use explicit
profile commands when starting standalone MCP clients:

The local OpenCode config declares CodeGraph, Maestro, browser, Playwright, and
Stitch, but only CodeGraph is enabled by default. The others are opt-in and
pinned to `dev`, `mobile`, or `web` so an agent handoff does not silently launch
an expensive or stateful capability. The two browser paths
remain intentionally different: `playwright` is the isolated deterministic
browser, while `browser` attaches to the dedicated agent Chrome session through
Chrome DevTools MCP. Verify the effective process map with `opencode mcp list`.

```sh
eval "$(mcp-profile env dev)"    # browser + Playwright + CodeGraph + local docs
eval "$(mcp-profile env notes)"  # dev + Obsidian
eval "$(mcp-profile env mobile)" # dev + Maestro
mcp-profile verify-codegraph      # fresh OpenCode CodeGraph handshake
mcp-profile status                # classify scoped vs legacy processes
```

The browser server launches a dedicated, visible Chrome instance for agent
work using a persistent profile at
`~/.local/state/opencode/chrome-devtools-profile` (override with
`CHROME_DEVTOOLS_MCP_USER_DATA_DIR`). This is intentionally separate from your
personal Chrome profile, so it does not require `chrome://inspect` or an
**Allow remote debugging?** prompt. Log in to sites once inside this agent
Chrome; cookies and local storage persist across OpenCode sessions. Do not run
two independent MCP clients against the same profile at the same time; set a
different `CHROME_DEVTOOLS_MCP_USER_DATA_DIR` for parallel sessions.

After normalizing the managed OpenCode link, restart OpenCode and verify the
resolved config before using browser tools.

The development resource profile is separate from MCP profiles. Review and
apply it with:

```sh
workstationctl resources plan
sudo /home/namik/Documents/code/dotfiles/setup/workstationctl resources apply
systemctl reboot
/home/namik/Documents/code/dotfiles/setup/workstationctl resources verify
```

The `sudo` command and reboot are intentionally manual. `resource-profile.sh
verify` reports the current drift without applying system changes.

## Plannotator and Obsidian

Install the corrective planning hook with:

```sh
setup/install-plannotator-improvement-hook.sh
```

The shared Obsidian MCP launcher is `configs/opencode/obsidian-mcp.sh`. It reads the user-owned `~/.config/opencode/obsidian.env` and the vault's local REST API settings without copying credentials into this repository. OpenCode uses it from the tracked config; Codex and Claude Code use the same launcher as user-scoped MCP servers.

The Stitch remote MCP entry reads its Google API key from the user-owned
`~/.config/opencode/stitch-api-key` file. Keep that file mode `600`; the key is
intentionally not stored in this repository. OpenCode v2 quota uses a tested
community port pinned to commit `75d9b5d`. Install/build it with:

```sh
setup/install-opencode-quota-v2.sh
```

The managed `cli.json` contains TUI preferences. OpenCode auto-discovers the
quota adapter from `~/.config/opencode/plugins`; Linux notifications are also
linked there.
The quota adapter exposes `/quota` and `/quota_status`. After installing or
relinking these plugins, restart the background server with
`opencode service restart`, then open a new TUI session.

In Plannotator, open Settings, enable **Obsidian Integration**, and select `~/Documents/notes/DocsVault`. Approved plans will then be saved to the vault with frontmatter, tags, and a backlink to `[[Plannotator Plans]]`.
