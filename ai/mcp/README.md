# MCP Setup

This directory holds example MCP configs for local clients.

## Included servers
- workbench: canonical TypeScript project, retrieval, memory, and workflow MCP
- filesystem: project-scoped file access
- git: project history and diffs
- local-docs: cached framework and workstation documentation
- browser and chrome-devtools: browser automation and inspection
- obsidian: optional vault access

Obsidian stays disabled until a vault and `OBSIDIAN_API_KEY` are available.

## Enabled by default
The OpenCode baseline enables Workbench, filesystem, git, local-docs, browser,
and Chrome DevTools. Mutating tools require OpenCode approval; Obsidian is
enabled only when its vault and API key are configured.

## Credentials
Put secrets in your MCP client's secure env/config layer, not in this repo. Replace placeholder connection strings, tokens, and vault paths before enabling optional servers.
