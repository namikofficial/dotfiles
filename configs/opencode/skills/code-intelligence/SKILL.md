---
name: code-intelligence
description: Use local code indexes and static analyzers to answer codebase questions with minimal context.
compatibility: opencode
---

# Local Code Intelligence

Prefer targeted analysis over opening large collections of files.

## Tool order

1. Use CodeGraph for symbols, callers, callees, impact, affected tests, and focused exploration.
2. Use LSP for definitions, references, diagnostics, and type information.
3. Use `ast-grep` when installed for syntax-aware search or mechanical structural rewrites.
4. Use `semgrep` for security, bug-pattern, and rule-based scans.
5. Use `knip` when installed for unused JS/TS files, exports, dependencies, binaries, and cycles.
6. Use `rg` only for exact text or configuration searches.

Do not dump entire files or repositories when a symbol, call path, diagnostic, or affected-test result is sufficient. Confirm important findings against source before editing.

