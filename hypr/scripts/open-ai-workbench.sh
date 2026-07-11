#!/usr/bin/env bash
set -euo pipefail

url="${AI_WORKBENCH_URL:-http://127.0.0.1:3000}"
health="${AI_WORKBENCH_API_URL:-http://127.0.0.1:4242}/health/deep"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "AI Workbench" "$1" "${2:-}"
}

if command -v curl >/dev/null 2>&1 && ! curl -fsS --max-time 1 "$health" >/dev/null 2>&1; then
  notify "AI Workbench is not ready" "Start it with: cd ~/Documents/code/ai && pnpm dev"
fi

if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$url" >/dev/null 2>&1 &
  exit 0
fi

notify "Unable to open AI Workbench" "xdg-open is missing"
exit 1
