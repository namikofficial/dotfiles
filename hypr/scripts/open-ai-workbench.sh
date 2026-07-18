#!/usr/bin/env bash
set -euo pipefail

url="${AI_WORKBENCH_URL:-http://127.0.0.1:4317}"
health="${AI_WORKBENCH_API_URL:-http://127.0.0.1:4417}/health"
root="${AI_WORKBENCH_ROOT:-$HOME/Documents/code/ai}"
session="${AI_WORKBENCH_TMUX_SESSION:-ai-workbench}"
view="${1:-overview}"
status_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ai-workbench/project-status-v1.json"

notify() {
	command -v notify-send >/dev/null 2>&1 || return 0
	notify-send -a "AI Workbench" "$1" "${2:-}"
}

if command -v curl >/dev/null 2>&1 && ! curl -fsS --max-time 1 "$health" >/dev/null 2>&1; then
	if [[ ! -d "$root" ]]; then
		notify "AI Workbench repository not found" "$root"
		exit 1
	fi
	if ! command -v tmux >/dev/null 2>&1; then
		notify "Unable to start AI Workbench" "tmux is required; run: cd $root && pnpm dev"
		exit 1
	fi
	if ! tmux has-session -t "$session" 2>/dev/null; then
		tmux new-session -d -s "$session" "cd $(printf '%q' "$root") && exec pnpm dev"
	fi
	for _ in {1..30}; do
		curl -fsS --max-time 1 "$health" >/dev/null 2>&1 && break
		sleep 1
	done
	if ! curl -fsS --max-time 1 "$health" >/dev/null 2>&1; then
		notify "AI Workbench did not become ready" "Inspect with: tmux attach -t $session"
		exit 1
	fi
fi

if command -v jq >/dev/null 2>&1 && [ -s "$status_cache" ]; then
	project_id="$(jq -r '.status.project.id // ""' "$status_cache" 2>/dev/null || true)"
	if [ -n "$project_id" ]; then
		encoded_id="$(jq -rn --arg value "$project_id" '$value | @uri')"
		case "$view" in
		work | ask | planner | checks) url="${url%/}/projects/${encoded_id}/${view}" ;;
		*) url="${url%/}/projects/${encoded_id}" ;;
		esac
	fi
fi

if command -v xdg-open >/dev/null 2>&1; then
	xdg-open "$url" >/dev/null 2>&1 &
	exit 0
fi

notify "Unable to open AI Workbench" "xdg-open is missing"
exit 1
