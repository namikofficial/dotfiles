# LLM Setup Guide - Complete

Your system is now fully configured to run local LLMs with **tmux + Wayle integration + logging**.

## Quick Start (3 steps)

### Step 1: Download Models

Run the model downloader to get links:

```bash
bash ~/Documents/code/dotfiles/system/model-downloader.sh gemma
# Then manually download and save to ~/llama-models/gemma-7b-it-Q4_K_M.gguf

# And download coder model:
bash ~/Documents/code/dotfiles/system/model-downloader.sh code
# Save to ~/llama-models/deepseek-coder-6.7b-instruct-Q4_K_M.gguf
```

**Or use HuggingFace CLI (fastest):**

```bash
pip install huggingface-hub

# Download Gemma
huggingface-cli download TheBloke/Gemma-7B-Instruct-GGUF gemma-7b-it-Q4_K_M.gguf --local-dir ~/llama-models

# Download DeepSeek-Coder
huggingface-cli download TheBloke/deepseek-coder-6.7B-instruct-GGUF deepseek-coder-6.7b-instruct-Q4_K_M.gguf --local-dir ~/llama-models
```

### Step 2: Start Server (In Tmux)

```bash
# Start Gemma on port 8000
llm-manager start gemma

# Or start DeepSeek-Coder
llm-manager start code
```

Server runs in tmux session: `llm-server`

### Step 3: Use It!

```bash
# Terminal commands
kage ai explain        # Copy error/code to clipboard first
kage ai commit-msg     # In git repo with staged changes
kage ai review         # In git repo with commits

# Or use keybinds (from anywhere in Hyprland)
Super+Shift+E          # Explain
Super+Shift+C          # Commit message
Super+Shift+R          # Review code
```

## Available Commands

### llm-manager

```bash
llm-manager start [gemma|code]    # Start server with model (tmux)
llm-manager stop                  # Stop running server
llm-manager status                # Show status, logs, models
llm-manager logs                  # Tail server logs in real-time
llm-manager attach                # Attach to tmux session
llm-manager test                  # Test if server is responding
llm-manager download              # Show download links/instructions
```

### Example Workflow

```bash
# Terminal 1: Start Gemma
llm-manager start gemma
# [server runs in background in tmux]

# Terminal 2: Check status
llm-manager status

# Terminal 3: Watch logs
llm-manager logs

# Terminal 4: Test
llm-manager test

# Terminal 5: Use in git repo
cd ~/my-repo
git add file.ts
kage ai commit-msg    # → Shows rofi with message
```

## Files

**Scripts (portable):**
- `~/Documents/code/dotfiles/system/llm-manager.sh` - Main controller
- `~/Documents/code/dotfiles/system/model-downloader.sh` - Model download helper
- `~/Documents/code/dotfiles/system/wayle-llm-module.sh` - Wayle sidebar widget
- `~/.local/bin/llm-manager` - Symlink (added to PATH)

**Config:**
- `~/.config/kage/llama.conf` - LLM configuration
- `~/.cache/kage/llm-logs/llm.log` - Server logs (auto-rotated)

**Models (store here):**
- `~/llama-models/gemma-7b-it-Q4_K_M.gguf` (~4.5 GB)
- `~/llama-models/deepseek-coder-6.7b-instruct-Q4_K_M.gguf` (~4.0 GB)

## Wayle Integration

The LLM status appears in Wayle sidebar bar (left section, after project):

```
🤖 LLM: gemma-7b-it   ← Click to see status
```

Shows:
- Model name
- Server status (running/offline)
- Recent logs (hover for tooltip)
- Click: Show detailed status
- Action: View logs

## Troubleshooting

### Server won't start

```bash
# Check logs
llm-manager logs

# Check if model file exists
ls -lh ~/llama-models/

# Check port 8000 is free
lsof -i :8000

# Try attaching to tmux session
llm-manager attach
# Then press Ctrl+C to see any errors
```

### "Model not found" error

Make sure you downloaded the model correctly:

```bash
# List models
ls -lh ~/llama-models/

# Should show:
# gemma-7b-it-Q4_K_M.gguf (4.5G)
# deepseek-coder-6.7b-instruct-Q4_K_M.gguf (4.0G)
```

### Wayle doesn't show LLM module

Reload Wayle:

```bash
# Restart Wayle service
systemctl --user restart wayle

# Or restart Hyprland
hyprctl reload
```

### AI features say "Local AI not running"

Start the server:

```bash
llm-manager start gemma
# Wait 2-3 seconds for it to initialize
llm-manager test
```

## Performance Tips

**For best speed on GTX 4050 (6GB):**

- Use Q4_K_M quantization (already done)
- Keep `-ngl 32` (all layers on GPU)
- Use 8 CPU threads for overflow
- Close heavy apps before starting

**Model selection:**

- Gemma 7B: General explanations, commit messages (~50-60 tok/sec)
- DeepSeek-Coder 6.7B: Code analysis, security review (~40-50 tok/sec)

Both fit in 6GB VRAM with room to spare.

## Next Steps

1. Download models (Step 1 above)
2. Start server: `llm-manager start gemma`
3. Test: `llm-manager test`
4. Use: `kage ai explain` (copy text to clipboard first)
5. Watch Wayle sidebar for LLM status

## Portable Setup

These scripts work on any machine:

```bash
# Copy entire system folder to new machine
cp -r ~/Documents/code/dotfiles/system/ /path/on/new/machine/

# Link the scripts
ln -sf /path/on/new/machine/system/llm-manager.sh ~/.local/bin/llm-manager

# Download models
bash /path/on/new/machine/system/model-downloader.sh gemma

# Start!
llm-manager start gemma
```

## Questions?

- Check logs: `llm-manager logs`
- Check status: `llm-manager status`
- Manual test: `curl -X POST http://localhost:8000/v1/completions ...`
- See all commands: `llm-manager help`
