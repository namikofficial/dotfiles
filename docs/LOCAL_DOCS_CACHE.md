# Local Docs Cache

The local docs cache gives OpenCode a quota-free MCP for framework and platform
documentation. It stores fetched text under `~/.cache/local-docs` and serves it
through the `local-docs` MCP.

## Sources

Configured in `configs/local-docs/sources.json`:

- React
- Vite
- TanStack Query
- MikroORM
- Rust Book
- Android Developers

## Commands

```sh
system/local-docs-cache.sh status
system/local-docs-cache.sh refresh
system/local-docs-cache.sh refresh react
system/local-docs-cache.sh search "useQuery staleTime" --stack tanstack-query
system/local-docs-cache.sh read vite --max-chars 4000
```

## OpenCode

OpenCode loads the server through:

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
