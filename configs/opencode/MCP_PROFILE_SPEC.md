# MCP profile specification

Status: initial implementation

MCP servers are capability gates, not default context. The launcher and the
OpenCode config must agree on the effective profile.

| Profile | Intended servers | Use |
| --- | --- | --- |
| `minimal` | none unless explicitly required by the client | repository work |
| `dev` | CodeGraph, local docs | semantic code exploration |
| `web` | Playwright; browser only for authenticated/debug sessions | live Web proof |
| `mobile` | Maestro | emulator/device proof |
| `design` | Stitch/design tools | UI research/implementation |
| `notes` | Obsidian | note operations |

The current canonical config exposes CodeGraph, Maestro, browser, Playwright,
and Stitch entries. `mcp-scoped.sh` defaults to `minimal`, while CodeGraph and
Maestro receive fixed profile environments. This must be validated at runtime;
configuration presence is not proof of process isolation.

Required checks:

1. For each profile, run the scoped launcher and record allowed/denied servers.
2. Start a clean OpenCode process and inspect `opencode mcp list`.
3. Confirm disabled servers do not spawn and enabled servers use the expected environment.
4. Keep remote Stitch and authenticated browser access opt-in.
5. Redact keys, cookies, headers, and tool payloads from diagnostics.
