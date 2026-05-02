# 🚀 Quick Start: Local LLM + AI Features

## What's Ready ✅

### 1. **GA Alias (Fixed!)**
```bash
ga                    # Add all files
ga file1.txt file2    # Add specific files
gcm "commit message"  # Direct commit
gcm                   # Interactive commit prompt
```

### 2. **AI Features** (Super+Shift+C/R/E)
- **Super+Shift+C** — Commit message generator
- **Super+Shift+R** — Code review (last commit)
- **Super+Shift+E** — Explain clipboard text

### 3. **LLM Server Manager**
```bash
llm-manager start gemma       # Start Gemma 7B
llm-manager start code        # Start DeepSeek-Coder
llm-manager stop              # Stop server
llm-manager status            # Check status
llm-manager logs              # View logs
llm-manager test              # Test server works
```

## Quick Setup (5 minutes)

### Step 1: Create HuggingFace Account & Get Token
1. Visit https://huggingface.co/join
2. Accept model licenses:
   - https://huggingface.co/google/gemma-7b-it
   - https://huggingface.co/deepseek-ai/deepseek-coder-6.7b-instruct
3. Create token: https://huggingface.co/settings/tokens (copy the token)

### Step 2: Download Models
```bash
# Run the setup script (interactive)
bash ~/Documents/code/dotfiles/system/model-download-setup.sh

# OR do it manually:
export HF_TOKEN="your_token_here"
huggingface-cli login --token "$HF_TOKEN"

# Then download
llm-manager download
```

Expected downloads:
- **gemma-7b-it-Q4_K_M.gguf** — ~4.5 GB
- **deepseek-coder-6.7b-instruct-Q4_K_M.gguf** — ~4.0 GB

### Step 3: Start Server
```bash
# Start Gemma 7B (general tasks)
llm-manager start gemma

# Wait ~3 seconds for startup, then verify:
llm-manager status
llm-manager test
```

### Step 4: Test AI Features
```bash
# Test commit message generator
cd ~/Documents/code/dotfiles
echo "test" > file.txt
ga
git commit --no-edit  # Or use: gcm "test: add file"
Super+Shift+C         # Generate next commit message

# Test explain (copy error text first)
echo "TypeError: 'NoneType' object is not subscriptable" | wl-copy
Super+Shift+E         # Explain in rofi

# Test review
Super+Shift+R         # Review last commit in kitty
```

## Hardware Notes (Your System)

| Component | Spec | Impact |
|-----------|------|--------|
| GPU | GTX 4050 6GB | ✅ Perfect for both models |
| CPU | i7-13Gen | ✅ Great for overflow |
| RAM | 8-16GB | ✅ Both models fit with room |

**Performance expectations:**
- Gemma 7B: ~50-60 tokens/sec
- DeepSeek-Coder: ~40-50 tokens/sec
- Total VRAM used: ~9GB (both models loaded)

## Troubleshooting

### Models won't download
**Problem:** 401/404 errors
**Solution:**
1. Make sure you accepted the model licenses on HF
2. Create a new token (older ones may be revoked)
3. Run: `huggingface-cli login --token YOUR_TOKEN`

### GA function not working
**Problem:** `ga: command not found`
**Solution:**
```bash
# Reload zshrc
exec zsh
# Or restart kitty
```

### LLM server won't start
**Problem:** `curl: (7) Failed to connect to localhost port 8000`
**Solution:**
```bash
# Check if server is actually running
llm-manager status

# View logs
llm-manager logs

# Try restarting
llm-manager stop
llm-manager start gemma
```

### Model files still missing after download
**Problem:** `ls ~/llama-models/` is empty
**Solution:**
```bash
# Check download progress
llm-manager logs

# Manual download with auth
huggingface-cli login  # Follow prompts
# Then download via the script
```

## What's Installed

- ✅ **llama.cpp (CUDA)** — Local inference engine
- ✅ **llm-manager** — Server lifecycle manager
- ✅ **huggingface-hub** — Model downloader
- ✅ **kage AI scripts** — Rewritten for local LLMs
- ✅ **GA alias** — Fixed in zshrc (sources before aliases)
- ✅ **Wayle LLM widget** — Shows running model in sidebar

## File Locations

| File | Purpose |
|------|---------|
| `~/.local/bin/llm-manager` | Server manager symlink |
| `~/llama-models/` | Model storage (9GB) |
| `~/.cache/kage/llm-logs/` | Server logs |
| `~/.cache/kage/llm-status.json` | Current status |
| `~/Documents/code/dotfiles/hypr/scripts/kage-ai-*.sh` | AI features |
| `~/Documents/code/dotfiles/zsh/git-functions.zsh` | GA/GCM definitions |

## Next Steps

### After Models Downloaded:
1. [ ] Start server: `llm-manager start gemma`
2. [ ] Test in Hyprland: `Super+Shift+E` (explain a note)
3. [ ] Test git workflow: Edit → `ga` → `gcm "feat: ..."` → `Super+Shift+C`
4. [ ] Verify Wayle shows `🤖 LLM: gemma-7b-it` in sidebar

### Future Enhancements:
- Add OCR → AI explain pipeline
- Notification digest summary
- Keyboard shortcut customization
- Model switching via Wayle UI
- Cache responses to reduce latency

## Support

Need help?
```bash
# Check all components
llm-manager test
ga --help  # GA is now a function
gcm        # Test interactive commit

# View logs
llm-manager logs
tail -f ~/.cache/kage/llm-logs/llm.log

# Check git setup
zsh -c 'type ga gco gcm'
```
