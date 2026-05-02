#!/usr/bin/env bash
# kage-ai-commit-msg.sh — Generate commits using LOCAL AI (ollama/llama-server)
# ZERO token usage - runs completely offline
# Dependencies: curl, rofi, wl-copy
set -euo pipefail

diff_text="$1"
[ -n "$diff_text" ] || { notify-send "kage-ai" "❌ No staged changes"; exit 1; }

notify() { notify-send -a "kage-ai" "$1" "${2:-}" 2>/dev/null || true; }
ROFI_THEME="${HOME}/.config/rofi/actions.rasi"

# Show progress
notify "⏳ Generating commit message..." "Analyzing staged changes..."

# ── Try to get commit message from local AI ────────────────────────────────────

prompt="You are an expert at writing conventional commit messages.
Analyze this git diff and generate ONLY a commit message in format:
type(scope): subject

Git diff:
${diff_text}"

# Try local LLM endpoint (ollama, llama-server, etc)
response=""
for endpoint in "http://localhost:11434/api/generate" "http://127.0.0.1:8000/v1/completions"; do
  if response="$(curl -s --max-time 5 "$endpoint" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"prompt\":\"$prompt\",\"stream\":false}" 2>/dev/null)"; then
    [ -n "$response" ] && break
  fi
done

if [ -z "$response" ]; then
  notify "❌ Local AI not running" "Start: llama-server (see LOCAL_AI_SETUP.md)"
  exit 1
fi

# Extract message (handle various API response formats)
msg="$(printf '%s' "$response" | grep -o '"response":"[^"]*' | head -1 | cut -d'"' -f4 || echo "$response" | head -3)"
[ -n "$msg" ] || { notify "❌ AI failed" "Could not generate message"; exit 1; }

notify "✓ Message generated" "Opening rofi for confirmation..."

# ── Show in Rofi + copy ────────────────────────────────────────────────────────

rofi_theme_arg=()
[ -f "$ROFI_THEME" ] && rofi_theme_arg=(-theme "$ROFI_THEME")

# Show confirmation
confirm="$(printf '%s\n' "$msg" "" "[Enter=Copy] [Esc=Cancel]" | \
  rofi -dmenu -i -p "Commit" "${rofi_theme_arg[@]}" 2>/dev/null || true)"

if [ $? -eq 0 ]; then
  printf '%s' "$msg" | wl-copy 2>/dev/null || true
  notify "✓ Copied to clipboard" "Ready for: git commit"
else
  notify "⊘ Cancelled" "Commit message discarded"
fi



