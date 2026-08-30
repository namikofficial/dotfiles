#!/usr/bin/env bash
set -euo pipefail

check_only=0
settle_seconds="${NOXFLOW_MEASURE_SETTLE_SECONDS:-5}"
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

sleep "$settle_seconds"
shell_rss="$(ps -o rss= -p "$shell_unit" | tr -d ' ')"
daemon_rss="$(ps -o rss= -p "$daemon_unit" | tr -d ' ')"
combined_rss="$((shell_rss + daemon_rss))"
proc_ticks() {
  awk '{ print $14 + $15 }' "/proc/$1/stat"
}
system_ticks() {
  awk '/^cpu / { print $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9 + $10 }' /proc/stat
}
proc_before="$(($(proc_ticks "$shell_unit") + $(proc_ticks "$daemon_unit")))"
system_before="$(system_ticks)"
sleep 1
proc_after="$(($(proc_ticks "$shell_unit") + $(proc_ticks "$daemon_unit")))"
system_after="$(system_ticks)"
idle_cpu="$(awk -v p="$((proc_after - proc_before))" -v s="$((system_after - system_before))" 'BEGIN { if (s > 0) printf "%.2f", p / s * 100; else print "0.00" }')"
processes="$(($(pgrep -x noxd | wc -l) + $(pgrep -x quickshell | wc -l)))"
journal_start="$(systemctl --user show noxflow-shell.service -p ActiveEnterTimestamp --value 2>/dev/null || true)"
journal_errors=0
if [[ -n "$journal_start" ]]; then
  journal_errors="$(journalctl --user -u noxflow-shell.service --since "$journal_start" --no-pager -o cat 2>/dev/null | rg -i -c 'error|exception|failed' || true)"
  journal_errors="${journal_errors:-0}"
fi
login_to_bar="not_measured"
if [[ -n "${XDG_SESSION_ID:-}" ]]; then
  session_timestamp="$(loginctl show-session "$XDG_SESSION_ID" -p Timestamp --value 2>/dev/null || true)"
  shell_timestamp="$(systemctl --user show noxflow-shell.service -p ActiveEnterTimestamp --value 2>/dev/null || true)"
  if [[ -n "$session_timestamp" && -n "$shell_timestamp" ]]; then
    session_epoch="$(date -d "$session_timestamp" +%s 2>/dev/null || true)"
    shell_epoch="$(date -d "$shell_timestamp" +%s 2>/dev/null || true)"
    if [[ "$session_epoch" =~ ^[0-9]+$ && "$shell_epoch" =~ ^[0-9]+$ && "$shell_epoch" -ge "$session_epoch" ]]; then
      login_to_bar="$((shell_epoch - session_epoch))"
    fi
  fi
fi

printf 'shell_pid=%s\ndaemon_pid=%s\nshell_rss_kib=%s\ndaemon_rss_kib=%s\ncombined_noxflow_rss_kib=%s\nidle_cpu_percent=%s\nlogin_to_visible_bar_seconds=%s\nnoxflow_related_processes=%s\njournal_errors_since_shell_start=%s\n' \
  "$shell_unit" "$daemon_unit" "$shell_rss" "$daemon_rss" "$combined_rss" "$idle_cpu" "$login_to_bar" "$processes" "$journal_errors"

if ((check_only)); then exit 0; fi
