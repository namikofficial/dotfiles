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
for endpoint in "http://localhost:11434/api/generate" "http://127.0.0.1:8000/v1/completions"; do
  if review_output="$(curl -s --max-time 10 "$endpoint" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"prompt\":\"$prompt\",\"stream\":false,\"num_predict\":500}" 2>/dev/null)"; then
    [ -n "$review_output" ] && break
  fi
done

if [ -z "$review_output" ]; then
  notify "❌ Local AI not running" "Start: llama-server (see LOCAL_AI_SETUP.md)"
  exit 1
fi

# Extract message from response
review_text="$(printf '%s' "$review_output" | \
  grep -o '"response":"[^"]*' | head -1 | cut -d'"' -f4 || \
  printf '%s' "$review_output" | head -20)"

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

