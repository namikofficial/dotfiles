# Skill: local-ai-runtime-debug

## When to use
llama-swap, llama-server, model routing, or local RAG runtime issues.

## Inputs required
Symptom, active model, logs, endpoint status, and recent config changes.

## Process
1. Check config generation and model file presence.
2. Verify endpoint health, aliases, and runtime state.
3. Separate GPU/runtime issues from model/config issues.

## Output format
Likely failing layer, evidence, and the next repair command.

## Safety / guardrails
Do not assume a model is usable if the GGUF file is missing or invalid.
