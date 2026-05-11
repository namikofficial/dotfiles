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

response="$(curl -fsS --max-time 10 "http://127.0.0.1:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg prompt "$prompt" '{model:"local",messages:[{role:"system",content:"You write concise conventional commit messages."},{role:"user",content:$prompt}],temperature:0.2,stream:false,max_tokens:120}')" 2>/dev/null || true)"

if [ -z "$response" ]; then
  notify "❌ Local AI not running" "Start: llama-swap-manager start"
  exit 1
fi

# Extract message
msg="$(jq -r '.choices[0].message.content // empty' <<<"$response" 2>/dev/null || true)"
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


