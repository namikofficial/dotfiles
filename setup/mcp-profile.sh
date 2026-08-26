#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  mcp-profile env {minimal|dev|notes|mobile}
  mcp-profile status
  mcp-profile stop PID...
  mcp-profile verify-codegraph

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
    printf 'profile=%s\n' "${NOXFLOW_MCP_PROFILE:-minimal}"
    printf '%-8s %-8s %-8s %-10s %-8s %s\n' PID PPID RSS ELAPSED MODE COMMAND
    ps -eo pid=,ppid=,rss=,etime=,args= |
      while read -r pid ppid rss elapsed command; do
        case "$command" in
          *'mcp-scoped.sh'* | *'chrome-devtools-mcp.sh'*) mode=scoped ;;
          *'codegraph serve --mcp'* | *'local-docs-mcp'* | *'playwright-mcp'* | *'chrome-devtools-mcp'* | *'obsidian-mcp-server'* | *'maestro mcp'*) mode=legacy ;;
          *) continue ;;
        esac
        parent="$(ps -p "$ppid" -o comm= 2>/dev/null | tr -d ' ' || true)"
        printf '%-8s %-8s %-8s %-10s %-8s %s [parent=%s]\n' "$pid" "$ppid" "$rss" "$elapsed" "$mode" "$command" "${parent:-unknown}"
      done
    ;;
  verify-codegraph)
    command -v opencode >/dev/null 2>&1 || {
      printf 'opencode is not installed\n' >&2
      exit 127
    }
    output="$(NOXFLOW_MCP_PROFILE=dev timeout 45s opencode mcp list --pure 2>&1 || true)"
    printf '%s\n' "$output"
    awk '
      /codegraph/ && /connected/ { ok=1; exit }
      END { exit(ok ? 0 : 1) }
    ' <<<"$output" || {
      printf 'CodeGraph did not report connected in a fresh OpenCode MCP session\n' >&2
      exit 1
    }
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
