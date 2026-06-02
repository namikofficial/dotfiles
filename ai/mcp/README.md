# MCP Setup

This directory holds example MCP configs for local clients.

## Included servers
- filesystem: workspace file access
- git: repository history and diffs
- sqlite: local RAG SQLite database
- context7: library docs lookup
- rag: local RAG MCP bridge
- postgres, browser, qdrant, obsidian: optional extras

## Enabled by default
The example configs enable filesystem, git, sqlite, context7, and rag by default.

## Credentials
Put secrets in your MCP client's secure env/config layer, not in this repo. Replace placeholder connection strings, tokens, and vault paths before enabling optional servers.
