# Local RAG stack

This repo now includes a repeatable local RAG bootstrap aimed at the current laptop profile:

- **Answer model:** Gemma 3 4B Q4_K_M via local llama-swap
- **Vector store:** Qdrant (local Docker container)
- **Dense embeddings:** FastEmbed with **`BAAI/bge-small-en-v1.5`** by default
- **Keyword retrieval:** SQLite FTS5 over the indexed chunks
- **Hybrid retrieval:** dense + keyword + metadata fusion

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
rag index ~/Documents/code/dotfiles
rag search "scratchpad manager"
rag ask "How does the AI scratchpad choose its model?"
rag reindex --changed
```

When you run `rag ask` or `rag search` **from inside an indexed git repo**, the CLI auto-scopes to that repo unless you override it with `--repo`.

## Machine-tuned defaults

- The default embedding model is **`BAAI/bge-small-en-v1.5`** because it is lighter and faster for this machine.
- If you want higher retrieval quality later, edit `~/ai-rag/config.json` and switch:

```json
{
  "embedding_model": "BAAI/bge-m3"
}
```

## Retrieval flow

1. rewrite each question into a few query variants
2. pull semantic hits from Qdrant
3. pull keyword hits from SQLite FTS
4. merge with reciprocal rank fusion
5. rerank by lexical/path/symbol overlap
6. send only the best chunks to Gemma

## Notes

- This initial version is tuned for **local repeatability** over maximal complexity.
- It already supports:
  - repo-aware indexing
  - changed-file reindexing
  - metadata with path / repo / kind / symbol / line ranges
  - answer prompts with file citations
- It intentionally does **not** try to index lockfiles, build artifacts, binaries, or media by default.
