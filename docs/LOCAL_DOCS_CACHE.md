# Local Docs Cache

The local docs cache gives Codex and OpenCode a quota-free MCP for framework, platform, CLI, and desktop
documentation. It stores fetched text under `~/.cache/local-docs` and serves it
through the `local-docs` MCP.

## Sources

Configured in `configs/local-docs/sources.json`:

- Web/frontend: React, Vite, TypeScript, Node.js, npm, pnpm, Next.js, Tailwind CSS, shadcn/ui, Radix UI, Playwright, TanStack Query, MDN Web Docs
- Mobile: React Native, Expo, Android Developers, Gradle
- Rust/Python/Lua: Rust Book, Rust standard library, Cargo Book, Tokio, Serde, Python standard library, Lua 5.4
- Editor/desktop/shell: Neovim, Hyprland Wiki, kitty, Zsh, Bash, tmux, Git, Arch Linux Wiki essentials
- Backend/data/ops: Docker CLI, kubectl, PostgreSQL, SQLite, MikroORM, Fastify
- Agent/dev tooling: Model Context Protocol, OpenAI Codex manual
- Local workstation docs: selected manpages and installed CLI `--help` output

Source kinds:

- `url`: fetches one URL and optionally follows same-host links matching `include_patterns`
- `manpages`: snapshots local `man` output through `MANPAGER=cat`
- `commands`: snapshots local command help output without a shell

## Commands

```sh
system/local-docs-cache.sh status
system/local-docs-cache.sh refresh
system/local-docs-cache.sh refresh react
system/local-docs-cache.sh search "useQuery staleTime" --stack tanstack-query
system/local-docs-cache.sh read vite --max-chars 4000
system/local-docs-cache.sh search "hyprland windowrule monitor" --stack hyprland
system/local-docs-cache.sh search "systemctl unit journalctl" --stack local-manpages
```

## MCP clients

Codex and OpenCode load the server through:

```sh
system/local-docs-mcp.sh
```

Useful MCP tools:

- `local_docs_search`
- `local_docs_read`
- `local_docs_status`
- `local_docs_refresh`

Use `local_docs_search` before spending network or model quota on framework
questions. Use `local_docs_refresh` only when current docs are explicitly needed.
