# Codex optimization record

The active user configuration is `/home/namik/.codex/config.toml`; credentials
and user state must not be committed here. The current baseline is deliberately
small and profile-driven:

- default model/reasoning and verbosity remain low for routine work;
- subagents are limited to two concurrent threads and depth one;
- browser, design, notes, and other optional MCP servers are disabled in the
  base config and enabled only through separate profile files;
- CodeGraph is routed through the dotfiles `mcp-scoped.sh` launcher so its
  profile gating is shared with OpenCode;
- the disabled Stitch server has no API key in the active Codex config;
- `codex --strict-config doctor --summary --no-color --ascii` is the canonical
  syntax/configuration smoke check.

Codex profiles are overlays under `$CODEX_HOME/*.config.toml`, selected with
`codex --profile NAME`. Keep project-specific guidance in trusted project
`.codex/config.toml` files, and keep machine/provider/auth settings in the user
config. Do not treat a parsed config or a successful MCP listing as proof of
token savings; benchmark completed tasks with context, tool, verification, and
rework metrics.

The 2026-09-22 user-config backup is retained at:

`/home/namik/.codex/backups/20260922T-codex-opencode-optimization/config.toml`
