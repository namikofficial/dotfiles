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

For argument-preserving launches with optional Codex overlays, use the
launcher:

```sh
setup/ai-session.sh opencode
setup/ai-session.sh codex
```

It is an argument-preserving direct launcher. It does not classify tasks,
select an agent, or delegate work. OpenCode uses the MCP profiles configured
per server. Codex uses its normal config unless you explicitly request an
overlay:

```sh
setup/ai-session.sh --explain --dry-run opencode --yolo
AI_SESSION_PROFILE=design setup/ai-session.sh codex
AI_SESSION_PROFILE=notes setup/ai-session.sh codex
AI_SESSION_NO_PROFILE=1 setup/ai-session.sh codex
```

The wrapper is optional. Run `opencode` or `codex` directly for the normal
workflow.

MiniMax M2.7 is the normal build and plan model. From the same build session it
can spawn `explore-m2.7`, cheaper `explore-m2.5`, `worker-m2.7`, `worker-m3`,
`worker-m3.1`, or `worker-luna`; no restart or primary mode switch is
required. Luna uses the medium variant.

Pick the worker deliberately: `worker-m3.1` (MiniMax M3.1 Flash Preview) is the
fast lane with a 1M-token context — broad reads, mechanical multi-file edits,
and well-specified changes. `worker-m3` is the hardest-reasoning fallback and
`worker-luna` is for vision or arbitration. `worker-m3.1` is a preview model, so
if the provider retires the id the agent fails at spawn and `worker-m3` is the
fallback; `opencode models | grep M3.1` confirms it is still served.

The ceilings are build 250, plan 120, M2.7 explorer 60, M2.5 explorer 50, M2.7
worker 200, M3 worker 220, M3.1 worker 200, and Luna worker 160. Delegation
depth is one and children cannot launch children. There are no verifier,
expert, review, ask, UI-specialist, security, or devops roles.

Sensitive environment/auth/session paths remain denied. Build has every
configured tool. Build, plan, and all workers can use the full installed skill
catalog. Restart or run `opencode reload` after configuration changes, then
inspect resolved role names with
`opencode debug config | jq -r '.[0].info.agents | keys[]'`.

`quality_contract.md` and `verification_policy.md` are loaded as global
instructions, so every task inherits the same conduct and result vocabulary.
`worker_contract.md` is deliberately *not* global: each explorer and worker
prompt points at it and reads it on spawn, which keeps the contract in one file
without paying for it on every coordinator request. When a child returns, treat
its report as evidence — it is required to separate observed checks from
assumptions.

`Super+Tab` is owned by Hyprland workspace overview and is unrelated to OpenCode task execution. Use `/fix` inside OpenCode for end-to-end coding work; use `Super+Space` for the NoxFlow AI launcher.

Optional Bruno, Schemathesis, axe, Roborazzi, browser CLI, cloud-device, and physical-device checks are capability-gated. They are never silently installed or reported as passing when unavailable.

## MCP resource profiles

Only Chrome DevTools (`browser`, profile `web`) and Maestro (profile `mobile`)
are configured. Both retain 120s discovery and 600s execution timeouts in the
native V2 `mcp.servers` layout. The browser attaches to the active Chrome
profile using auto-connect; enable remote debugging and approve the connection
when Chrome prompts. Run `opencode mcp list` to check connections.

The shared skill inventory contains only six official Expo skills: overview,
native UI, routing, data fetching, dev client, and SDK upgrades. The source is
`~/.agents/skills`; managed OpenCode skill links point there. No Expo MCP or
additional design libraries are installed.

The development resource profile is separate from MCP profiles. Review and
apply it with:

```sh
workstationctl resources plan
sudo ./setup/workstationctl resources apply
systemctl reboot
./setup/workstationctl resources verify
```

The `sudo` command and reboot are intentionally manual. `resource-profile.sh
verify` reports the current drift without applying system changes.

## Plannotator and Obsidian

Install the corrective planning hook with:

```sh
setup/install-plannotator-improvement-hook.sh
```

OpenCode v2 quota uses a tested
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
