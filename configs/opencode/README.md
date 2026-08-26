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

The phase commands are available inside OpenCode as `/research`, `/plan`, `/build`, `/verify`, `/permission`, and `/handoff`, alongside the existing `/goal` and `/full-fix` commands. Runtime phase artifacts live in a project-local, gitignored `.ai/` directory.

Optional Bruno, Schemathesis, axe, Roborazzi, browser CLI, cloud-device, and physical-device checks are capability-gated. They are never silently installed or reported as passing when unavailable.

## MCP resource profiles

MCP servers are scoped by profile so every client does not start every expensive
server. The default profile is `minimal` (browser only). Opt into a profile in
the shell before starting Codex, OpenCode, or Claude:

```sh
eval "$(mcp-profile env dev)"    # browser + CodeGraph + local docs
eval "$(mcp-profile env notes)"  # dev + Obsidian
eval "$(mcp-profile env mobile)" # dev + Maestro
```

The browser server attaches to the existing Chrome session through Chrome's
local remote-debugging flow; it does not launch an additional Chromium profile.
Enable it once at `chrome://inspect/#remote-debugging` and accept Chrome's
local connection prompt.

## Plannotator and Obsidian

Install the corrective planning hook with:

```sh
setup/install-plannotator-improvement-hook.sh
```

The shared Obsidian MCP launcher is `configs/opencode/obsidian-mcp.sh`. It reads the user-owned `~/.config/opencode/obsidian.env` and the vault's local REST API settings without copying credentials into this repository. OpenCode uses it from the tracked config; Codex and Claude Code use the same launcher as user-scoped MCP servers.

In Plannotator, open Settings, enable **Obsidian Integration**, and select `~/Documents/notes/DocsVault`. Approved plans will then be saved to the vault with frontmatter, tags, and a backlink to `[[Plannotator Plans]]`.
