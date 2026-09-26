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

Configured workflow commands are `/fix` and `/ui`. Routing and handoff commands
were removed because ordinary tasks should run directly; delegation is an
explicit choice inside `build`, not a mandatory pre-step. OpenCode's quota
plugin adds `/quota`. Runtime `.ai/` artifacts are created only for genuinely
large or multi-session work, not for every task.

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

MiniMax M2.7 is the normal build and plan model. From the same build session it
can spawn `explore-m2.7`, cheaper `explore-m2.5`, `worker-m2.7`, `worker-m3`,
or `worker-luna`; no restart or primary mode switch is required. Luna uses the
medium variant.

The ceilings are build 250, plan 120, M2.7 explorer 60, M2.5 explorer 50, M2.7
worker 200, M3 worker 220, and Luna worker 160. Delegation depth is one and
children cannot launch children. There are no verifier, expert, review, ask,
UI-specialist, security, or devops roles.

Sensitive environment/auth/session paths remain denied. Build has every
configured tool. Build, plan, and all workers can use the full installed skill
catalog. Restart or run `opencode reload` after configuration changes, then
inspect resolved role names with
`opencode debug config | jq -r '.[0].info.agents | keys[]'`.

`Super+Tab` is owned by Hyprland workspace overview and is unrelated to OpenCode task execution. Use `/fix` inside OpenCode for end-to-end coding work; use `Super+Space` for the NoxFlow AI launcher.

Optional Bruno, Schemathesis, axe, Roborazzi, browser CLI, cloud-device, and physical-device checks are capability-gated. They are never silently installed or reported as passing when unavailable.

## MCP resource profiles

MCP servers are scoped by profile so every client does not start every expensive
servers. The launcher pins each configured server to its correct scoped profile
so normal OpenCode launches work without shell reconfiguration. Use explicit
profile commands when starting standalone MCP clients:

The local OpenCode config declares CodeGraph, Maestro, browser, Playwright,
Stitch, v0, and VP0, and build can use all of them. v0 uses remote OAuth;
authenticate with `opencode mcp auth v0`. VP0 runs through `npx -y vp0-mcp`.
For native mobile UI work, `/ui` routes through the installed native UI and
mobile design skills and can use v0/VP0 when their workflows help. The two browser paths remain
intentionally different: `playwright` is isolated and deterministic;
`browser` attaches to the active Chrome profile. Chrome 144+ and remote
debugging at `chrome://inspect/#remote-debugging` are required; Chrome may ask
you to approve the connection. This gives the agent access to open tabs and
session data in that profile. Verify the effective process map with
`opencode mcp list`.

```sh
eval "$(mcp-profile env dev)"    # browser + Playwright + CodeGraph + local docs
eval "$(mcp-profile env notes)"  # dev + Obsidian
eval "$(mcp-profile env mobile)" # dev + Maestro
mcp-profile verify-codegraph      # fresh OpenCode CodeGraph handshake
mcp-profile status                # classify scoped vs legacy processes
```

The browser server uses Chrome DevTools MCP auto-connect to attach to your
active Chrome Stable profile. Enable remote debugging in Chrome settings and
approve the connection when prompted. Do not run independent agents against
the same active browser session at the same time.

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
The selected `noxflow-dynamic` theme is regenerated into
`~/.config/opencode/themes/` whenever the wallpaper palette syncs, including
separate markdown, diff, syntax, and muted-text colors.
The quota adapter exposes `/quota` and `/quota_status`. After installing or
relinking these plugins, restart the background server with
`opencode service restart`, then open a new TUI session.

In Plannotator, open Settings, enable **Obsidian Integration**, and select `~/Documents/notes/DocsVault`. Approved plans will then be saved to the vault with frontmatter, tags, and a backlink to `[[Plannotator Plans]]`.
