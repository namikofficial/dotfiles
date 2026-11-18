# Codex configuration

The active user settings live in `~/.codex/config.toml`; personal behavior rules
live in `~/.codex/AGENTS.md`. Credentials and user state stay out of this repository.

- Chrome DevTools is the only user-configured Codex MCP server.
- GitHub is retained; optional specialist plugins have been removed. Explicit
  disabled records prevent application-provided packages from auto-loading again.
- Six official Expo skills live in `~/.agents/skills`, without the Expo MCP.
- Memory remains enabled. Delegation is only on explicit request; existing
  agent definitions, models, reasoning settings, and permissions are preserved.
- RTK is optional for Codex. There is no mandatory semantic-navigation step.

Use targeted search and concise repository documentation or issues for durable
context. Do not claim token savings from configuration size or tool listings:
compare completed tasks, tool output, verification, and rework if benchmarking.

Validate TOML syntax and use a fresh Codex session to check discovery. Existing
sessions may retain tools and skill descriptions loaded before cleanup.

On Unix, Codex uses the user's login shell for command execution and has no
supported shell-path setting. The user config disables login-shell semantics
to avoid loading interactive startup behavior. Non-interactive zsh also has
`nomatch` disabled, so unmatched command globs behave like ordinary arguments.
For Bash-specific syntax, invoke `/usr/bin/bash -c` explicitly.

The 2026-09-22 user-config backup is retained at:

`~/.codex/backups/20260922T-codex-opencode-optimization/config.toml`
