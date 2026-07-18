#!/usr/bin/env bash
# kage-project-rofi.sh — Wayle project chip cockpit (left-click handler)
set -euo pipefail

KAGE="${HOME}/.config/hypr/scripts/kage"
LEGACY_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/kage/project-current.json"
WORKBENCH_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ai-workbench/project-status-v1.json"
ROFI_THEME="${HOME}/.config/rofi/actions.rasi"
rofi_theme_arg=(-theme "${ROFI_THEME}")
[ -f "${ROFI_THEME}" ] || rofi_theme_arg=()

notify() { notify-send -a kage "$1" "${2:-}" 2>/dev/null || true; }

workbench_available() {
	[ -s "$WORKBENCH_CACHE" ] && jq -e '.schemaVersion == 1 and (.status.project.path // "") != ""' \
		"$WORKBENCH_CACHE" >/dev/null 2>&1
}

project_path() {
	if workbench_available; then
		jq -r '.status.project.path // ""' "$WORKBENCH_CACHE"
	else
		jq -r '.path // ""' "$LEGACY_CACHE" 2>/dev/null || true
	fi
}

# ── Build menu entries ────────────────────────────────────────────────────────

build_menu() {
	if workbench_available; then
		local failed stale
		failed="$(jq -r '.status.checks.failed // 0' "$WORKBENCH_CACHE")"
		stale="$(jq -r '.status.index.stale // false' "$WORKBENCH_CACHE")"
		printf '  Resume current work\n'
		[ "$failed" -gt 0 ] && printf '  Show failed checks\n'
		[ "$stale" = "true" ] && printf '  Reindex project\n'
		printf '  Open Lazygit\n'
		printf '  Ask AI about project\n'
		printf '  Open Workbench\n'
		printf '  Switch project\n'
	elif [ -s "${LEGACY_CACHE}" ]; then
		# Project actions from cache
		jq -r '.actions[]? // empty' "${LEGACY_CACHE}" 2>/dev/null | while IFS= read -r act; do
			printf '⚡  %s\n' "$act"
		done
	fi

	# Always-available utility actions
	printf '  Refresh project\n'
	printf '  Open in terminal\n'
	printf '  Copy project path\n'
	printf '  Open file manager\n'
	printf '  Project status\n'
}

build_header() {
	if workbench_available; then
		jq -r '.compact as $c | "\($c.project.name // "?")  \($c.git.branch // "")  ✦\($c.git.dirty // 0) ◆\($c.git.staged // 0)  \($c.work.label // "No active task") [\($c.work.state // "unknown")]"' \
			"$WORKBENCH_CACHE" 2>/dev/null
	elif [ -s "$LEGACY_CACHE" ]; then
		jq -r '"\(.name // "?")  [\(.framework // "")]  \(.branch // "")  \(if .dirty then "✦\(.modified // 0) ◆\(.staged // 0)" else "clean" end)"' \
			"$LEGACY_CACHE" 2>/dev/null
	else
		printf 'Workbench offline — no cached project\n'
	fi
}

# ── Run rofi ─────────────────────────────────────────────────────────────────

MENU="$(build_menu)"
HEADER="$(build_header)"

CHOICE="$(printf '%s\n' "${MENU}" |
	rofi -dmenu -i -p '  Project' -mesg "$HEADER" "${rofi_theme_arg[@]}" 2>/dev/null || true)"

[ -n "$CHOICE" ] || exit 0

# ── Dispatch ─────────────────────────────────────────────────────────────────

# Strip leading icon prefix for matching
CHOICE_CLEAN="$(printf '%s' "$CHOICE" | sed 's/^[[:space:]]*[⚡ ]*[[:space:]]*//')"

case "$CHOICE_CLEAN" in
"Refresh project")
	"${KAGE}" project refresh
	;;
"Open in terminal")
	_path="$(project_path)"
	if [ -n "$_path" ] && [ -d "$_path" ]; then
		kitty --directory "$_path" --class noxflow-tool-large --title "terminal — $(basename "$_path")"
	else
		notify "Cannot open terminal" "Project path not found"
	fi
	;;
"Copy project path")
	_path="$(project_path)"
	if [ -n "$_path" ] && printf '%s' "$_path" | wl-copy; then
		notify "Copied" "$_path"
	else
		notify "Copy failed" "No project path cached"
	fi
	;;
"Open file manager")
	_path="$(project_path)"
	if [ -n "$_path" ] && [ -d "$_path" ]; then
		xdg-open "$_path" >/dev/null 2>&1 &
	else
		notify "No path" "Project path not found"
	fi
	;;
"Project status")
	"${KAGE}" project status |
		rofi -dmenu -p 'Project Status' "${rofi_theme_arg[@]}" >/dev/null 2>&1 || true
	;;
"Switch project")
	"$HOME/.config/hypr/scripts/workbench-project-switcher"
	;;
"Open Workbench" | "Reindex project")
	"$HOME/.config/hypr/scripts/open-ai-workbench.sh" overview
	;;
"Resume current work")
	"$HOME/.config/hypr/scripts/open-ai-workbench.sh" work
	;;
"Show failed checks")
	"$HOME/.config/hypr/scripts/open-ai-workbench.sh" checks
	;;
"Ask AI about project")
	"$HOME/.config/hypr/scripts/open-ai-workbench.sh" ask
	;;
"Open Lazygit")
	_path="$(project_path)"
	[ -n "$_path" ] && [ -d "$_path" ] && kitty --class noxflow-lazygit --title "lazygit — $(basename "$_path")" -- lazygit -p "$_path"
	;;
*)
	# It's a project action (e.g. "test", "build", "logs", etc.)
	if [ -n "$CHOICE_CLEAN" ]; then
		if workbench_available; then
			notify "Action unavailable" "Canonical workflow execution is not enabled for this action yet"
		else
			"${KAGE}" project action "${CHOICE_CLEAN}" &
		fi
	fi
	;;
esac
