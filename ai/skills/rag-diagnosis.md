# Skill: rag-diagnosis

## When to use
Bad retrieval quality, broken indexing, embedding mismatches, or MCP/RAG issues.

## Inputs required
Query, corpus path, model settings, and error output.

## Process
1. Check ingestion, chunking, embeddings, reranking, and synthesis.
2. Verify endpoint and config alignment.
3. Suggest one focused validation per stage.

## Output format
Stage-by-stage diagnosis with the first failing point.

## Safety / guardrails
Do not claim retrieval quality without checking indexed data.
