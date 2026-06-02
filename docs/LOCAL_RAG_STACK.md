# Local RAG stack and runtime

This repo includes a repeatable local RAG bootstrap for the current workstation and broader repo work, not just dotfiles:

- **Answer model:** Qwen3 8B Q4_K_M via local llama-swap
- **Vector store:** Qdrant (local Docker container)
- **Dense embeddings:** FastEmbed with **`BAAI/bge-small-en-v1.5`** by default
- **Keyword retrieval:** SQLite FTS5 over the indexed chunks
- **Hybrid retrieval:** dense Qdrant + SQLite FTS5 + metadata/fact fusion
- **Reranker:** lightweight heuristic reranker enabled by default on this machine
- **Query intelligence:** richer intent detection, developer abbreviations, symbol-aware rewrites, typo-tolerant lookup, and metadata boosts
- **Facts layer:** exact structured facts for aliases, keybinds, env vars, tools, config keys, SQL/schema objects, systems-language surfaces, data stores, and local infra
- **File summaries:** cheap routing summaries per indexed file
- **Repo memory:** durable repo-level summary usable during `rag ask --memory`
- **Mode surfaces:** explicit `rag quick`, `rag deep`, `rag agent`, and target-specific `rag handoff`
- **Operational state:** structured todos, decisions, commands, errors, sessions, developer memory notes, context packs, and session compactions stored in SQLite
- **Active-work context:** git diff snapshots, branch/index mismatch reporting, GitHub issue/PR context, test-failure transcripts, and exact error fingerprints
- **Code focus:** tuned for TypeScript, JavaScript, React/TSX, Rust, Kotlin, HTML, CSS, shell, GTK/XML-style UI files, and mixed config repos

## Install / repair the stack

```bash
cd ~/Documents/code/dotfiles
./setup/install-local-rag-stack.sh
```

That script is idempotent. You can rerun it to:

- recreate or repair the venv under `~/ai-rag/.venv`
- install/update Python dependencies
- create or repair the local `qdrant` Docker container for on-demand startup
- refresh the `rag` CLI symlink in `~/.local/bin/rag`
- refresh the `local-ai-runtime` helper in `~/.local/bin/local-ai-runtime`

## Reindex after schema changes

The current local index format is `rag-v5` / `semantic-lines-v5`. If your local SQLite/Qdrant state was built with an older schema, reset and rebuild it:

```bash
rag clean --all
rag index ~/Documents/code/dotfiles --profile balanced
```

`rag index` and `rag reindex` show live progress with elapsed time, ETA, processed files, changed/skipped counts, chunk count, current file, and files-per-second. If you cancel a long run, rerun with `rag index --changed-only` to continue from already committed files.

## Commands

```bash
local-ai-runtime status
local-ai-runtime start
rag doctor
cd ~/Documents/code/noxflow && rag index
rag index --profile fast
rag index ~/Documents/code/noxflow --changed-only
rag status
rag search "AuthService.login"
rag search "AuthService.login" --explain
rag search "scratchpad manager" --no-rerank
rag suggest
rag suggest debug
rag inspect "AuthService.login"
rag missing "debug checkout failure"
rag why "checkout failure" src/checkout.ts
rag graph AuthService
rag facts list --kind keybind
rag facts keybind scratchpad
rag facts tool docker
rag trace keybind Super Alt S
rag quick "what does this config do?"
rag deep "review the retrieval architecture"
rag agent "prepare a Codex handoff for the RAG CLI" --save-handoff
rag todo add "Add reranker support" --repo dotfiles
rag todo list --repo dotfiles
rag decision add "Use explicit modes" "Keep rag ask as a compatibility alias" --repo dotfiles
rag command add "python -m unittest tests.rag.test_retrieval" --purpose "RAG regression check" --repo dotfiles
rag error add "database is locked" --fix "retry after the active command finishes" --command "pytest tests/rag/test_retrieval.py" --exit-code 1 --repo dotfiles
rag context git --refresh --repo dotfiles
rag context github pr 123 --repo dotfiles
rag context test-failure add "pytest tests/rag/test_retrieval.py" --output "AssertionError: ..." --runner pytest --exit-code 1 --repo dotfiles
rag session list --repo dotfiles
rag summarize-files --changed-only
rag summarize
rag memory show
rag memory status
rag memory refresh
rag memory remember known_stack backend "node nest mikro-orm postgres" --global-scope
rag memory notes --scope all
rag memory conflicts --repo dotfiles
rag memory compact --repo dotfiles
rag memory pack dotfiles --repo dotfiles --target-agent codex --write-file
rag memory taxonomy --query backend
rag memory clear --repo dotfiles
rag handoff codex "prepare a RAG memory handoff" --save-handoff
rag ask "How does tenant scoping work?"
rag ask "How does tenant scoping work?" --show-context
rag ask "What does Super Alt S do?" --memory
rag ask "How does the AI scratchpad choose its model?" --rerank
rag reindex
rag clean --repo noxflow
rag clean --all
local-ai-runtime stop
```

When you run `rag ask`, `rag quick`, `rag deep`, `rag agent`, or `rag search` **from inside an indexed git repo**, the CLI auto-scopes to that repo unless you override it with `--repo`.

`rag index`, `rag reindex`, `rag search`, and the answer/handoff commands now auto-start the local Qdrant and llama-swap services when they target the default loopback endpoints. That lets the Docker/vector store and model server stay off during normal non-LLM work.

For command completion, suggestions, and the full interactive command map, see [RAG CLI UX guide](RAG_CLI_UX.md).

## Machine-tuned defaults

- The default embedding model is **`BAAI/bge-small-en-v1.5`** because it is lighter and faster for this machine.
- The default reranker is a **heuristic local scoring pass, not a separate model reranker**, and is **enabled by default** here. You can override it per query with `--rerank` or `--no-rerank`.
- Query rewriting now expands common developer shorthand like `cfg`, `svc`, `db`, and symbol-shaped queries like `AuthService.login`, then lightly corrects close typos from indexed path/symbol vocabulary.
- The chunker now recognizes more mixed-repo shapes, including TypeScript/JavaScript arrow functions, Rust modules/traits, Kotlin classes/functions, shell function/alias/env/case/tool blocks, TOML sections, YAML top-level sections, HTML/CSS sections, GTK/XML-style UI objects, and Hyprland config anchors.
- Structured fact extraction now also covers `package.json` scripts/dependencies/workspaces, Cargo/Rust, Go/go.mod, C/kernel-module patterns, Postgres/MSSQL schema details, Mongo/Redis usage, Grafana/Prometheus config, Dockerfile/Compose, systemd units, zsh dotfiles, richer Nest/Node facts (modules/providers/guards/interceptors/pipes/queues/relations), Express/Fastify routes, React/frontend surfaces (components/hooks/routes/query keys/forms/stores), and TS/dev-tooling config files such as `tsconfig`, Vite, Vitest, Jest, Playwright, ESLint, Prettier, and Commitlint.
- Facts and file summaries are generated during indexing, so `rag reindex` refreshes them alongside the chunk/vector index.
- Code indexing now keeps a developer profile, optional Tree-sitter parsing with regex fallback, AST/regex-derived symbol records, import/export edges, and a semantic line index for better code-aware recall.
- Indexed code files also carry package metadata so monorepos can produce file dependency edges and deterministic package summaries.
- Indexing profiles let you trade speed for richer derived state:
  - `fast`: chunks + facts only
  - `balanced`: chunks + facts + file summaries
  - `deep`: chunks + facts + file summaries + repo memory refresh
- Context packing now uses separate budgets for repo memory, facts, file summaries, and chunks instead of one shared token pool.
- Developer memory is split by kind (`project_facts`, `developer_preferences`, `known_stack`, `tool_preferences`, `hardware_profile`, `repo_conventions`) and kept separate from repo summaries.
- Context packs can be generated into SQLite and optional `.context/*.toon` files for reusable handoffs.
- Repo memory freshness now tracks commit drift, changed files/symbols, and a freshness score.
- Tool taxonomy data is stored locally and used to expand queries/reranking for stack-specific prompts.
- Retrieval diversity limits keep one file from dominating the final context window.
- Metadata ranking now strongly prefers matching paths, symbols, and hinted file types, while treating recency as a weak tiebreaker instead of the main signal.
- If you want higher retrieval quality later, edit `~/ai-rag/config.json` and switch:

```json
{
  "embedding_model": "BAAI/bge-m3",
  "reranker": {
    "enabled": true,
    "mode": "heuristic",
    "top_k_input": 30,
    "top_k_output": 12
  }
}
```

## Retrieval flow

1. rewrite each question into a few query variants
2. pull semantic hits from Qdrant
3. pull keyword hits from SQLite FTS5
4. pull matching facts and file summaries from SQLite
5. merge chunk candidates with reciprocal rank fusion
6. apply diversity limits so one file does not crowd out the rest
7. rerank by lexical/path/symbol overlap (enabled by default, but optional)
8. route between quick / deep / agent behavior instead of treating every task the same way
9. prepend repo memory, operational state, and active-work context (git/PR/test failures/errors) for deeper tasks when available
10. run a missing-context pass for caller/tests/config/docs/error logs when the first retrieval is too narrow
11. pack sections with per-section token budgets and send the result to Gemma, or emit a coding-agent handoff packet

## Notes

- This initial version is tuned for **local repeatability** over maximal complexity.
- It already supports:
  - repo-aware indexing
  - changed-file reindexing
  - reranker toggles with `--rerank` / `--no-rerank`
  - retrieval debugging with `rag search --explain`
  - packed-context inspection with `rag ask --show-context`
  - explicit `rag quick` / `rag deep` / `rag agent` mode surfaces
  - auto-routed `rag ask --mode auto|quick|deep|agent`
  - structured `rag facts` queries
  - trace-style fact inspection with `rag trace`
  - file summaries via `rag summarize-files`
  - repo memory via `rag summarize` / `rag memory show` / `rag memory status` / `rag ask --memory`
  - structured operational memory via `rag todo`, `rag decision`, `rag command`, `rag error`, `rag session`, and `rag memory remember`
  - branch-aware git snapshots via `rag context git`
  - GitHub issue/PR context ingestion via `rag context github`
  - exact error fingerprints plus stored local/CI test failures via `rag error` and `rag context test-failure`
  - missing-context reporting in `rag search --explain` / `rag ask --show-context`
  - reusable context packs via `rag memory pack`
  - coding-agent handoff generation via `rag agent ... --target-agent ...` or `rag handoff <target> ...`
  - metadata with path / repo / kind / symbol / line ranges
  - answer prompts with file citations
- It intentionally does **not** try to index lockfiles, build artifacts, binaries, or media by default.
- It also skips dependency/cache trees such as `node_modules`, Python virtualenvs, `site-packages`, `__pycache__`, `.tox`, `.nox`, `.gradle`, `target`, `vendor`, and coverage output.
