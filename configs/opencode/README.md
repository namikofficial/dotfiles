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

The focused commands are available inside OpenCode as `/fix`, `/plan`, `/review`, `/verify`, and `/handoff`. Runtime `.ai/` artifacts are created only for large or multi-session work, not for every task.

MiniMax M2.7 is the normal model for build, plan, exploration, worker, and
review. MiniMax M3 is available through the explicit `worker-m3` escalation;
GPT-5.6 Luna (and its fast variant) is reserved for deliberate escalation.
The catalog also keeps MiniMax M2.5/M2.1 plus one GPT-5.6 Terra model for
manual selection. `ask` is the twenty-step quick repository agent.

The high-autonomy profile uses two delegation levels and larger bounded
budgets: build 250, plan 120, explore 60, worker 200, review 100, worker-m3
300, worker-luna 220, expert 80, web-verifier 100, android-verifier 100,
ui-specialist 180, security-audit 120, devops-run 120, explore-m3 80, and ask
20. `worker-luna` uses GPT-5.6 Luna with the `medium` variant.

All configured agents and tools are permission-allowed, including shell,
external directories, skills, MCP, delegation, and destructive operations.
Use this profile only when that level of autonomy is intentional; it can
modify or delete files, expose credentials to a model, or perform irreversible
commands. OpenCode still needs to be restarted after configuration changes.

`Super+Tab` is owned by Hyprland workspace overview and is unrelated to OpenCode task execution. Use `/fix` inside OpenCode for end-to-end coding work; use `Super+Space` for the NoxFlow AI launcher.

Optional Bruno, Schemathesis, axe, Roborazzi, browser CLI, cloud-device, and physical-device checks are capability-gated. They are never silently installed or reported as passing when unavailable.

## MCP resource profiles

MCP servers are scoped by profile so every client does not start every expensive
servers. The default profile is `minimal` (browser and Playwright). Opt into a profile in
the shell before starting Codex, OpenCode, or Claude:

The local OpenCode config exposes CodeGraph, Maestro, browser, Playwright, and
Stitch to every configured agent. The two browser paths remain intentionally
different: `playwright` is the isolated deterministic browser, while `browser`
attaches to the existing Chrome session through Chrome DevTools MCP. The
launcher still uses the selected MCP resource profile for server startup.

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
intentionally not stored in this repository. OpenCode Quota is pinned to
`@slkiser/opencode-quota@4.8.0`; its tracked sidecar is
`opencode-quota/quota-toast.json` and the linked TUI config is `tui.json`.

OpenCode Tool Search is pinned to `opencode-tool-search@0.4.3` with the core
file/edit/search tools kept visible and larger tool descriptions deferred.
Before changing quota installation, preview the upstream installer with:

```sh
npx @slkiser/opencode-quota@4.8.0 init --dry-run
```

In Plannotator, open Settings, enable **Obsidian Integration**, and select `~/Documents/notes/DocsVault`. Approved plans will then be saved to the vault with frontmatter, tags, and a backlink to `[[Plannotator Plans]]`.
