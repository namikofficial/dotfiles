#!/usr/bin/env bash
# kage-ai-commit-msg.sh — Generate a detailed conventional commit message
# using the LOCAL AI runtime (llama-swap on :8080).
# Zero token usage. Uses qwen3-4b by default (fast, follows format well).
#
# Usage:
#   kage-ai-commit-msg.sh                    # use staged changes
#   kage-ai-commit-msg.sh --type feat        # hint a type
#   kage-ai-commit-msg.sh --model qwen3-8b   # override model
#   kage-ai-commit-msg.sh --commit           # commit after confirmation
#
# Dependencies: curl, jq, wl-copy, rofi (or wayle)
set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────────────
hint_type=""
model="${KAGE_AI_COMMIT_MODEL:-qwen3-4b}"
auto_commit=0
while [ $# -gt 0 ]; do
  case "$1" in
    --type)    hint_type="$2"; shift 2 ;;
    --model)   model="$2"; shift 2 ;;
    --commit)  auto_commit=1; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# *//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ── Resolve diff ──────────────────────────────────────────────────────────────
diff_text="$(git diff --cached 2>/dev/null || true)"
[ -n "$diff_text" ] || { notify-send "kage-ai" "No staged changes — run 'git add' first" 2>/dev/null || true; exit 1; }

# Truncate huge diffs so the prompt fits the context window
diff_max=6000
[ "${#diff_text}" -gt "$diff_max" ] && diff_text="${diff_text:0:$diff_max}
... [truncated — full diff in git]"

# Stats for the body context
files_changed="$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')"
insertions="$(git diff --cached --shortstat 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /insertion/) print $(i-1)}' | tr -d ' ')"
deletions="$(git diff --cached --shortstat 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /deletion/) print $(i-1)}' | tr -d ' ')"

# ── AI runtime helpers ────────────────────────────────────────────────────────
SOURCE_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
HEALTH_ENDPOINT="${LLM_HEALTH_ENDPOINT:-http://127.0.0.1:8080/v1/models}"

ensure_local_ai() {
  if curl -fsS --max-time 1 "$HEALTH_ENDPOINT" >/dev/null 2>&1; then return 0; fi
  local runtime=""
  if command -v local-ai-runtime >/dev/null 2>&1; then
    runtime="$(command -v local-ai-runtime)"
  elif [ -x "$SCRIPT_DIR/../../system/local-ai-runtime.sh" ]; then
    runtime="$SCRIPT_DIR/../../system/local-ai-runtime.sh"
  fi
  [ -n "$runtime" ] || { notify-send "kage-ai" "Local AI not running" "Start: local-ai-runtime start" 2>/dev/null || true; return 1; }
  "$runtime" ensure-llm || return 1
}

# ── Pick the right model alias (handle 'qwen3-4b' vs 'local' vs 'gemma-3-4b') ─
resolve_model_id() {
  # The runtime might expose the model under a different name. Ask the server.
  local available
  available="$(curl -fsS --max-time 2 "$HEALTH_ENDPOINT" | jq -r '.data[].id // empty' 2>/dev/null || true)"
  [ -n "$available" ] || { echo "$model"; return; }

  # Direct match?
  if printf '%s\n' "$available" | grep -qx "$model"; then echo "$model"; return; fi

  # Fallback chain
  local fallback
  for fallback in qwen3-4b qwen-coder-7b local; do
    if printf '%s\n' "$available" | grep -qx "$fallback"; then
      echo "$fallback"; return
    fi
  done

  printf '%s\n' "$available" | head -1
}

# ── Build the prompt ──────────────────────────────────────────────────────────
type_hint=""
[ -n "$hint_type" ] && type_hint="The user requested type: ${hint_type}.
If that type doesn't fit, pick the closest one and mention it in your thinking."

system_prompt="You are an expert at writing detailed conventional commit messages.

Rules:
- Subject: 'type(scope): imperative lowercase subject' — ≤ 50 chars, no period
- Types: feat, fix, refactor, perf, docs, test, build, ci, chore, style, revert
- Body: wrap at 72 chars, explain the WHY (the diff already shows the WHAT)
- Use bullet points (- ) for multiple reasons
- Footer: BREAKING CHANGE: if applicable, Refs: #N for issues

Always produce BOTH subject and body unless the change is trivial (typo, version bump, format-only)."

user_prompt="Generate a conventional commit message for these staged changes.

Files changed: ${files_changed} (+${insertions:-0}/-${deletions:-0})
${type_hint}

\`\`\`diff
${diff_text}
\`\`\`

Output format (no preamble, no explanation, no code fences):

type(scope): subject line here

- Body line 1 explaining the why
- Body line 2 if needed
- Body line 3 if needed"

# ── Call local AI ─────────────────────────────────────────────────────────────
notify-send -a "kage-ai" "⏳ Generating commit message..." "Using ${model}" 2>/dev/null || true

ensure_local_ai || exit 1

actual_model="$(resolve_model_id)"

response="$(curl -fsS --max-time 60 "http://127.0.0.1:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "$actual_model" \
    --arg sys "$system_prompt" \
    --arg usr "$user_prompt" \
    '{model:$model,messages:[{role:"system",content:$sys},{role:"user",content:$usr}],temperature:0.2,stream:false,max_tokens:400}')" 2>/dev/null || true)"

[ -n "$response" ] || { notify-send "kage-ai" "❌ Local AI request failed" "Check llama-swap status" 2>/dev/null || true; exit 1; }

msg="$(jq -r '.choices[0].message.content // empty' <<<"$response" 2>/dev/null || true)"
[ -n "$msg" ] || { notify-send "kage-ai" "❌ AI returned no message" "" 2>/dev/null || true; exit 1; }

# Strip leading/trailing whitespace
msg="$(printf '%s' "$msg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

# Strip code fences if the model wrapped the output
msg="$(printf '%s' "$msg" | sed -e 's/^```[a-zA-Z]*$//' -e 's/^```$//' -e 's/^```[a-zA-Z]*//' -e 's/```$//' -e 's/^[[:space:]]*//')"

# ── Show in picker (Rofi, fallback to Wayle or stdout) ───────────────────────
ROFI_THEME="${HOME}/.config/rofi/actions.rasi"
rofi_theme_arg=()
[ -f "$ROFI_THEME" ] && rofi_theme_arg=(-theme "$ROFI_THEME")

if command -v rofi >/dev/null 2>&1; then
  choice="$(printf '%s\n\n— — — — — — — —\n[Enter] Copy to clipboard   [C-Enter] Commit now' "$msg" | \
    rofi -dmenu -i -p "Commit msg" "${rofi_theme_arg[@]}" -mesg "Type: $hint_type  Model: $actual_model" 2>/dev/null || true)"

  # If user picked the help line, treat as cancel
  if [ -z "$choice" ] || [[ "$choice" == *"Enter] Copy"* ]] || [[ "$choice" == *"Cancel"* ]]; then
    # Fall through
    :
  fi
fi

# Always copy + notify
printf '%s' "$msg" | wl-copy 2>/dev/null || true
notify-send -a "kage-ai" "✓ Commit message copied" "Ready: git commit -F- or paste in editor" 2>/dev/null || true

# If --commit flag, do it now
if [ "$auto_commit" = "1" ]; then
  git commit -F- <<<"$msg" 2>&1 | tee >(notify-send -a "kage-ai" "✓ Committed" "$(git log -1 --oneline)" 2>/dev/null) || true
fi
