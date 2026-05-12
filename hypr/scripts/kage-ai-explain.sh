#!/usr/bin/env bash
# kage-ai-explain.sh — Pedagogical explanation using LOCAL model (zero token cost)
# Gets clipboard text, asks AI "why does this happen?", shows in rofi
set -euo pipefail

notify() { notify-send -a "kage-ai" "$1" "${2:-}" 2>/dev/null || true; }
SOURCE_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
HEALTH_ENDPOINT="${LLM_HEALTH_ENDPOINT:-http://127.0.0.1:8080/v1/models}"

local_ai_runtime() {
  if command -v local-ai-runtime >/dev/null 2>&1; then
    command -v local-ai-runtime
    return 0
  fi
  if [ -x "$SCRIPT_DIR/../../system/local-ai-runtime.sh" ]; then
    printf '%s\n' "$SCRIPT_DIR/../../system/local-ai-runtime.sh"
    return 0
  fi
  return 1
}

ensure_local_ai() {
  local runtime
  runtime="$(local_ai_runtime)" || return 1
  "$runtime" ensure-llm
}

# Get text from clipboard
text_to_explain="$(wl-paste 2>/dev/null || xclip -o 2>/dev/null || echo "")"
[ -n "$text_to_explain" ] || { notify "❌ Clipboard empty" "Copy error/code/log first"; exit 1; }

notify "⏳ Explaining..." "Analyzing your text..."

if ! curl -fsS --max-time 1 "$HEALTH_ENDPOINT" >/dev/null 2>&1; then
  notify "⏳ Starting local AI" "Loading llama-swap and the local model..."
  if ! ensure_local_ai; then
    notify "❌ Local AI not running" "Start: local-ai-runtime start"
    exit 1
  fi
fi

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
explanation="$(curl -fsS --max-time 90 "http://127.0.0.1:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg prompt "$prompt" '{model:"local",messages:[{role:"system",content:"You explain technical material deeply and clearly."},{role:"user",content:$prompt}],temperature:0.3,stream:false,max_tokens:1000}')" 2>/dev/null || true)"

if [ -z "$explanation" ]; then
  notify "❌ Local AI request failed" "Retry or start with: local-ai-runtime start"
  exit 1
fi

# Extract response
explanation_text="$(jq -r '.choices[0].message.content // empty' <<<"$explanation" 2>/dev/null || true)"

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

