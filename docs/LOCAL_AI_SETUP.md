# Local AI Setup for kage AI Features

Your AI commands are now **completely offline** and use **zero tokens**. No cloud API calls, no cost.

## What Changed

The three AI features are now completely rewritten to call your **local LLM**:

- `kage ai commit-msg` — generates conventional commits
- `kage ai review` — reviews your last commit diff for bugs/security
- `kage ai explain` — explains errors, code, or logs from clipboard

All use **curl** to talk to a local AI server on `localhost:11434` or `localhost:8000`.

---

## Step 1: Install a Local LLM Runtime

### Option A: ollama (Recommended for Arch)

```bash
yay -S ollama
# Start it:
ollama serve
```

### Option B: llama.cpp Server

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
make
./llama-server --model /path/to/model.gguf
```

### Option C: LM Studio (GUI)

- Download: https://lmstudio.ai/
- Load a model
- Click "Start Server" (uses `localhost:8000`)

---

## Step 2: Download a Model

With **ollama**, just run:

```bash
ollama pull mistral
# Or another model:
ollama pull neural-chat
ollama pull llama2
```

Models are auto-downloaded to `~/.ollama/models/`.

For **llama.cpp** or **LM Studio**, download GGUF format models from:
- https://huggingface.co/TheBloke/Mistral-7B-GGUF (fast, good for code)
- https://huggingface.co/TheBloke/neural-chat-7b-v3-GGUF
- https://huggingface.co/TheBloke/Llama-2-7B-GGUF

---

## Step 3: Test It Works

### Start the server:

```bash
# If using ollama:
ollama serve

# If using llama.cpp:
./llama-server --model model.gguf

# If using LM Studio: just click "Start Server"
```

### Test the endpoint:

```bash
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Hello","stream":false}'
```

Should return a response like `{"response":"Hello!..."}`

---

## Step 4: Use It!

Now just use the keybinds:

```bash
# Generate commit message from staged changes
Super+Shift+C

# Review last commit diff
Super+Shift+R

# Explain text from clipboard
Super+Shift+E
```

Each opens a notification saying it's working.

---

## Troubleshooting

### "Local AI not running"

Make sure your server is running:

```bash
# Check if ollama is running:
curl -s http://localhost:11434/api/tags | jq .

# Check if llama.cpp is running:
curl -s http://localhost:8000/v1/completions -X POST | jq .
```

If nothing responds, start the server:

```bash
ollama serve  # or your llama-server command
```

### "Could not generate message"

The model might be having issues. Check:

```bash
# See what models are available:
ollama list

# If no models, pull one:
ollama pull mistral

# Restart ollama:
pkill ollama
ollama serve
```

### Keybinds not working

Reload Hyprland after making changes:

```bash
hyprctl reload
```

Then try again: `Super+Shift+C`

### Slow responses

Try a smaller model:

```bash
ollama pull neural-chat  # 7B, faster
ollama pull mistral      # 7B, faster
# Instead of:
ollama pull llama2       # 13B, slower
```

---

## Performance Tips

1. **Use smaller models** (7B is fast, 13B is medium, 70B is slow)
2. **Disable animations** while waiting for AI (reduce system load)
3. **More VRAM** = faster (CPU fallback is slow)

## Cost

- **Zero dollars** — runs on your hardware
- **CPU usage** — 2-5 seconds per request (depends on model)
- **VRAM** — ~4-6 GB for 7B model

---

## Manual Invocation

If keybinds don't work, test manually:

```bash
# In a git repo with staged changes:
kage ai commit-msg

# After making a commit:
kage ai review

# With text in clipboard:
kage ai explain
```

Each should show a notification and/or open a Rofi/window.
