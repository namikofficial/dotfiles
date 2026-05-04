# Local RAG stack

This repo now includes a repeatable local RAG bootstrap aimed at the current laptop profile and broader repo work, not just dotfiles:

- **Answer model:** Gemma 3 4B Q4_K_M via local llama-swap
- **Vector store:** Qdrant (local Docker container)
- **Dense embeddings:** FastEmbed with **`BAAI/bge-small-en-v1.5`** by default
- **Keyword retrieval:** SQLite FTS5 over the indexed chunks
- **Hybrid retrieval:** dense + keyword + metadata fusion
- **Reranker:** lightweight heuristic reranker enabled by default on this machine
- **Facts layer:** exact structured facts for aliases, keybinds, env vars, tools, config keys, and SQL objects
- **File summaries:** cheap routing summaries per indexed file
- **Repo memory:** durable repo-level summary usable during `rag ask --memory`
- **Code focus:** tuned for TypeScript, JavaScript, React/TSX, Rust, Kotlin, HTML, CSS, shell, GTK/XML-style UI files, and mixed config repos

## Install / repair the stack

```bash
cd ~/Documents/code/dotfiles
./setup/install-local-rag-stack.sh
```

That script is idempotent. You can rerun it to:

- recreate or repair the venv under `~/ai-rag/.venv`
- install/update Python dependencies
- start the local `qdrant` Docker container
- refresh the `rag` CLI symlink in `~/.local/bin/rag`

## Commands

```bash
rag doctor
cd ~/Documents/code/noxflow && rag index
rag index --profile fast
rag index ~/Documents/code/noxflow --changed-only
rag status
rag search "AuthService.login"
rag search "AuthService.login" --explain
rag search "scratchpad manager" --no-rerank
rag facts list --kind keybind
rag facts keybind scratchpad
rag facts tool docker
rag trace keybind Super Alt S
rag summarize-files --changed-only
rag summarize
rag memory show
rag memory status
rag memory refresh
rag memory clear --repo dotfiles
rag ask "How does tenant scoping work?"
rag ask "How does tenant scoping work?" --show-context
rag ask "What does Super Alt S do?" --memory
rag ask "How does the AI scratchpad choose its model?" --rerank
rag reindex
rag clean --repo noxflow
rag clean --all
```

When you run `rag ask` or `rag search` **from inside an indexed git repo**, the CLI auto-scopes to that repo unless you override it with `--repo`.

## Machine-tuned defaults

- The default embedding model is **`BAAI/bge-small-en-v1.5`** because it is lighter and faster for this machine.
- The default reranker is a **heuristic local scoring pass, not a separate model reranker**, and is **enabled by default** here. You can override it per query with `--rerank` or `--no-rerank`.
- The chunker now recognizes more mixed-repo shapes, including TypeScript/JavaScript arrow functions, Rust modules/traits, Kotlin classes/functions, shell function/alias/env/case/tool blocks, TOML sections, YAML top-level sections, HTML/CSS sections, GTK/XML-style UI objects, and Hyprland config anchors.
- Structured fact extraction now also covers `package.json` scripts/dependencies/workspaces, Docker Compose services/ports/dependencies/environment keys, and Nest-style TypeScript controllers/routes/services/entities.
- Facts and file summaries are generated during indexing, so `rag reindex` refreshes them alongside the chunk/vector index.
- Indexing profiles let you trade speed for richer derived state:
  - `fast`: chunks + facts only
  - `balanced`: chunks + facts + file summaries
  - `deep`: chunks + facts + file summaries + repo memory refresh
- Context packing now uses separate budgets for repo memory, facts, file summaries, and chunks instead of one shared token pool.
- Retrieval diversity limits keep one file from dominating the final context window.
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
3. pull keyword hits from SQLite FTS
4. pull matching facts and file summaries from SQLite
5. merge chunk candidates with reciprocal rank fusion
6. apply diversity limits so one file does not crowd out the rest
7. rerank by lexical/path/symbol overlap (enabled by default, but optional)
8. optionally prepend repo memory for `rag ask --memory`
9. pack sections with per-section token budgets and send the result to Gemma

## Notes

- This initial version is tuned for **local repeatability** over maximal complexity.
- It already supports:
  - repo-aware indexing
  - changed-file reindexing
  - reranker toggles with `--rerank` / `--no-rerank`
  - retrieval debugging with `rag search --explain`
  - packed-context inspection with `rag ask --show-context`
  - structured `rag facts` queries
  - trace-style fact inspection with `rag trace`
  - file summaries via `rag summarize-files`
  - repo memory via `rag summarize` / `rag memory show` / `rag memory status` / `rag ask --memory`
  - metadata with path / repo / kind / symbol / line ranges
  - answer prompts with file citations
- It intentionally does **not** try to index lockfiles, build artifacts, binaries, or media by default.
