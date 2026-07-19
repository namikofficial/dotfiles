# Local AI helpers

The local model assets live under `~/ai-models` and the Python runtimes live
under `~/.local/share/nox-ai` and `~/.local/share/nox-ocr`.

```bash
system/ai/nox-ai-health.sh
system/ai/nox-embed.py "where are invoice permissions checked?"
system/ai/nox-dino.py baseline.png current.png
system/ai/nox-ocr.py screenshot.png
system/ai/nox-whisper task-recording.wav --model small --output_format txt
```

GPU swapping is automatic. By default, embedding, DINOv2, and Whisper acquire
the GPU, stop llama-swap first, run, then restore llama-swap. Force CPU mode
with `NOX_AI_DEVICE=cpu`. The RTX 4050 cannot reliably host the chat model and
all transformer models at the same time.

```bash
system/ai/nox-gpu-manager.sh status
system/ai/nox-gpu-manager.sh with nvidia-smi
NOX_AI_DEVICE=cpu system/ai/nox-embed.py "query"
```

For code search, `colgrep` uses LateOn-Code-edge by default:

```bash
colgrep "where invoice permissions are checked" /path/to/repository
colgrep settings
```

The existing AI Workbench remains the source of truth for project indexing and
hybrid retrieval. These helpers provide the local model operations it can call.
