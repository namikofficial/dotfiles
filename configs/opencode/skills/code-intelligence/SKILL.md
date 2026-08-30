---
name: code-intelligence
description: Use local code indexes and static analyzers to answer codebase questions with minimal context.
compatibility: opencode
---

# Local Code Intelligence

Prefer targeted analysis over opening large collections of files.

## Tool order

1. Use LSP for definitions, references, implementations, types, symbols, call hierarchy, and diagnostics.
2. Use CodeGraph for symbols, callers, callees, impact, affected tests, module dependencies, and cross-cutting flows.
3. Use `ast-grep` (`sg`) for syntax-aware search, structural patterns, and mechanical structural rewrites.
4. Use `semgrep` for security, bug-pattern, and rule-based scans.
5. Use `knip` when installed for unused JS/TS files, exports, dependencies, binaries, and cycles.
6. Use `rg` only for exact text or configuration searches.
7. Use `fd`/`glob` for filenames and paths.
8. Use `Read` for implementation details only after the relevant location is known.

Do not dump entire files or repositories when a symbol, call path, diagnostic, or affected-test result is sufficient. Confirm important findings against source before editing.

Before applying a structural rewrite broadly with ast-grep, test the pattern against representative files and inspect the resulting diff.

Do not enable global formatters (`"formatter": true`) in the global OpenCode config — formatter behavior differs per project and a global default creates unwanted formatting changes. Configure formatters per-project instead.

