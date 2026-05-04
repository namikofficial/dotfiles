#!/usr/bin/env bash
# kage-ai-explain.sh — Pedagogical explanation using LOCAL model (zero token cost)
# Gets clipboard text, asks AI "why does this happen?", shows in rofi
set -euo pipefail

notify() { notify-send -a "kage-ai" "$1" "${2:-}" 2>/dev/null || true; }

# Get text from clipboard
text_to_explain="$(wl-paste 2>/dev/null || xclip -o 2>/dev/null || echo "")"
[ -n "$text_to_explain" ] || { notify "❌ Clipboard empty" "Copy error/code/log first"; exit 1; }

notify "⏳ Explaining..." "Analyzing your text..."

# ── Call LOCAL AI ──────────────────────────────────────────────────────────────

prompt="Explain this deeply and pedagogically. Don't just summarize.

For the given text, explain:
1. What is happening? (describe the problem/code/error)
2. Why does it happen? (root cause or mechanism)
3. How to fix/prevent it? (actionable steps)
4. What to watch for? (signs of similar issues)

Be specific and technical. Help understand the concept deeply, not just fix it.

Text to explain:
${text_to_explain}"

explanation=""
for endpoint in "http://localhost:11434/api/generate" "http://127.0.0.1:8000/v1/completions"; do
  if explanation="$(curl -s --max-time 15 "$endpoint" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"prompt\":\"$prompt\",\"stream\":false,\"num_predict\":1000}" 2>/dev/null)"; then
    [ -n "$explanation" ] && break
  fi
done

if [ -z "$explanation" ]; then
  notify "❌ Local AI not running" "Start: llama-server (see LOCAL_AI_SETUP.md)"
  exit 1
fi

# Extract response
explanation_text="$(printf '%s' "$explanation" | \
  grep -o '"response":"[^"]*' | head -1 | cut -d'"' -f4 || \
  printf '%s' "$explanation" | head -30)"

[ -n "$explanation_text" ] || { notify "❌ AI failed"; exit 1; }

notify "✓ Explanation ready" "Opening in rofi..."

# ── Show in Rofi ──────────────────────────────────────────────────────────────

ROFI_THEME="${HOME}/.config/rofi/actions.rasi"
rofi_theme_arg=()
[ -f "$ROFI_THEME" ] && rofi_theme_arg=(-theme "$ROFI_THEME")

# Format: add indent for readability
formatted="$(printf '%s' "$explanation_text" | sed 's/^/  /')"

# Show in rofi (scrollable)
printf '%s\n' "$formatted" | \
  rofi -dmenu -i -p "Explanation" "${rofi_theme_arg[@]}" >/dev/null 2>&1 || true

notify "✓ Done" ""



