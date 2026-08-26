#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  mcp-profile env {minimal|dev|notes|mobile}
  mcp-profile status
  mcp-profile stop PID...

Use the environment form with:
  eval "$(mcp-profile env dev)"
EOF
}

case "${1:-}" in
  env)
    profile="${2:-}"
    case "$profile" in
      minimal | dev | notes | mobile)
        printf 'export NOXFLOW_MCP_PROFILE=%q\n' "$profile"
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
    ;;
  status)
    ps -eo pid=,ppid=,rss=,etime=,args= | rg 'codegraph serve --mcp|local-docs-mcp|playwright-mcp|chrome-devtools-mcp|obsidian-mcp-server|maestro mcp' || true
    ;;
  stop)
    shift
    [ "$#" -gt 0 ] || {
      printf 'usage: %s stop PID...\n' "$0" >&2
      exit 2
    }
    for pid in "$@"; do
      case "$pid" in
        '' | *[!0-9]*)
          printf 'invalid PID: %s\n' "$pid" >&2
          exit 2
          ;;
      esac
      [ -r "/proc/$pid/cmdline" ] || {
        printf 'PID %s does not exist\n' "$pid" >&2
        exit 1
      }
      cmd="$(tr '\0' ' ' <"/proc/$pid/cmdline")"
      case "$cmd" in
        *'codegraph serve --mcp'* | *'local-docs-mcp'* | *'playwright-mcp'* | *'chrome-devtools-mcp'* | *'obsidian-mcp-server'* | *'maestro mcp'*)
          kill -TERM "$pid"
          printf 'sent SIGTERM to MCP PID %s\n' "$pid"
          ;;
        *)
          printf 'refusing non-MCP PID %s: %s\n' "$pid" "$cmd" >&2
          exit 1
          ;;
      esac
    done
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
