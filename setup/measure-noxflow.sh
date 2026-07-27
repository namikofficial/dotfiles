#!/usr/bin/env bash
set -euo pipefail

check_only=0
if [[ "${1:-}" == "--check" ]]; then check_only=1; fi

if ! command -v systemctl >/dev/null || ! command -v ps >/dev/null; then
  echo "measurement tools unavailable" >&2
  exit 1
fi

shell_unit="$(systemctl --user show -p MainPID --value noxflow-shell.service 2>/dev/null || true)"
daemon_unit="$(systemctl --user show -p MainPID --value noxd.service 2>/dev/null || true)"
if [[ -z "$shell_unit" || "$shell_unit" == 0 || -z "$daemon_unit" || "$daemon_unit" == 0 ]]; then
  echo "noxflow shell and noxd must both be active" >&2
  exit 1
fi

shell_rss="$(ps -o rss= -p "$shell_unit" | tr -d ' ')"
daemon_rss="$(ps -o rss= -p "$daemon_unit" | tr -d ' ')"
shell_cpu="$(ps -o %cpu= -p "$shell_unit" | tr -d ' ')"
processes="$(pgrep -af 'noxflow|noxd|quickshell' | wc -l | tr -d ' ')"

printf 'shell_pid=%s\ndaemon_pid=%s\nshell_rss_kib=%s\ndaemon_rss_kib=%s\nshell_cpu_percent=%s\nshell_related_processes=%s\n' \
  "$shell_unit" "$daemon_unit" "$shell_rss" "$daemon_rss" "$shell_cpu" "$processes"

if (( check_only )); then exit 0; fi
