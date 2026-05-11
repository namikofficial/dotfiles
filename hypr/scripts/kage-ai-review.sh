#!/usr/bin/env bash
# kage-ai-review.sh — AI code review using LOCAL model (zero token cost)
# Shows in floating kitty with bat syntax highlighting
set -euo pipefail

notify() { notify-send -a "kage-ai" "$1" "${2:-}" 2>/dev/null || true; }

# Get last commit diff
diff_text="$(git diff HEAD~1..HEAD 2>/dev/null || git diff HEAD 2>/dev/null || echo "")"
[ -n "$diff_text" ] || { notify "❌ No commits" "Need at least 2 commits"; exit 1; }

notify "⏳ Analyzing code..." "Checking for security & logic issues..."

# ── Call LOCAL AI (zero tokens) ────────────────────────────────────────────────

prompt="You are a security-focused code reviewer. Analyze this git diff and report:

1. Security issues (SQL injection, XSS, CSRF, auth flaws)
2. Logic bugs (null checks, race conditions, state issues)
3. Performance issues (N+1, memory leaks, inefficiency)
4. ONLY report CRITICAL issues, NOT style.

Format:
[SECURITY] issue desc
[BUG] issue desc
[PERF] issue desc

Git diff:
${diff_text}"

review_output=""
review_output="$(curl -fsS --max-time 20 "http://127.0.0.1:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg prompt "$prompt" '{model:"local",messages:[{role:"system",content:"You are a terse security-focused code reviewer. Only report meaningful issues."},{role:"user",content:$prompt}],temperature:0.2,stream:false,max_tokens:700}')" 2>/dev/null || true)"

if [ -z "$review_output" ]; then
  notify "❌ Local AI not running" "Start: llama-swap-manager start"
  exit 1
fi

# Extract message from response
review_text="$(jq -r '.choices[0].message.content // empty' <<<"$review_output" 2>/dev/null || true)"

[ -n "$review_text" ] || { notify "❌ AI failed"; exit 1; }

notify "✓ Review complete" "Opening in floating window..."

# ── Render in floating kitty with syntax highlighting ────────────────────────

cmd_bat="cat"
if command -v bat >/dev/null 2>&1; then
  cmd_bat="bat --language md --theme=Monokai\ Extended"
elif command -v batcat >/dev/null 2>&1; then
  cmd_bat="batcat --language md --theme=Monokai\ Extended"
fi

tmpfile="$(mktemp /tmp/kage-review.XXXXXX.md)"
trap "rm -f '$tmpfile'" EXIT

cat > "$tmpfile" << REVIEW
# Code Review (HEAD~1..HEAD)

## AI Analysis

$review_text

## Diff Reviewed

\`\`\`diff
$diff_text
\`\`\`

---
Press Enter to close.
REVIEW

# Open in floating kitty
kitty --class noxflow-tool-large --title "Code Review" -- \
  sh -lc "
    ${cmd_bat} '${tmpfile}' 2>/dev/null || cat '${tmpfile}'
    printf '\n\n=== Press Enter to close ===\n'
    read -r _
  " >/dev/null 2>&1 &
