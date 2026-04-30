#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"

TS="$(date -u +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/health-${TS}.log"
LATEST_LINK="$LOG_DIR/health-latest.log"

declare -a red_flags=()
result="PASS"

add_flag() {
  local flag="$1"
  red_flags+=("$flag")
  result="FAIL"
}

status_ok() {
  printf '[OK]   %s\n' "$*"
}

status_warn() {
  printf '[WARN] %s\n' "$*"
}

section() {
  printf '\n## %s\n' "$1"
}

bool_icon() {
  if [ "$1" = "1" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

check_disk_flags() {
  local low=""
  while read -r _fs _sz _used _avail pcent mount; do
    pcent="${pcent%%%}"
    if [ -n "$pcent" ] && [ "$pcent" -ge 90 ]; then
      low="${low}${mount}(${pcent}%) "
    fi
  done < <(df -P / "$HOME" 2>/dev/null | awk 'NR>1')

  if [ -n "$low" ]; then
    add_flag "LOW_DISK ${low}"
  fi
}

check_portal_flags() {
  local portal_ok=1

  if ! systemctl --user is-active --quiet xdg-desktop-portal; then
    portal_ok=0
  fi
  if ! systemctl --user is-active --quiet xdg-desktop-portal-hyprland; then
    portal_ok=0
  fi

  if [ "$portal_ok" -eq 0 ]; then
    add_flag "PORTAL_DOWN user portal services are not active"
  fi
}

check_gpu_flags() {
  if ! nvidia-smi -L >/dev/null 2>&1; then
    add_flag "GPU_MISSING nvidia-smi cannot detect GPU"
  fi
}

check_journal_flags() {
  local err_count suspend_count

  err_count="$(journalctl --since '7 days ago' -p err..alert --no-pager 2>/dev/null | wc -l | tr -d ' ')"
  suspend_count="$(journalctl --since '7 days ago' --no-pager 2>/dev/null | rg -i 'failed to suspend|suspend.*fail|watchdog did not stop|Freezing of tasks failed|PM: suspend.*fail|sleep.*failed' | wc -l | tr -d ' ')"

  if [ "${err_count:-0}" -ge 150 ]; then
    add_flag "REPEATED_CRASHES ${err_count} high-priority journal errors in last 7d"
  fi
  if [ "${suspend_count:-0}" -gt 0 ]; then
    add_flag "SUSPEND_FAILURE ${suspend_count} suspend-related failures in last 7d"
  fi
}

portal_interface_checks() {
  local introspect cast_ok=0 picker_ok=0

  introspect="$(gdbus introspect --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop 2>/dev/null || true)"
  if printf '%s' "$introspect" | rg -q 'org.freedesktop.portal.ScreenCast'; then
    cast_ok=1
  fi
  if printf '%s' "$introspect" | rg -q 'org.freedesktop.portal.FileChooser'; then
    picker_ok=1
  fi

  printf 'Portal ScreenCast interface: %s\n' "$(bool_icon "$cast_ok")"
  printf 'Portal FileChooser interface: %s\n' "$(bool_icon "$picker_ok")"
  if [ "$cast_ok" -eq 0 ]; then
    add_flag "PORTAL_SCREENCAST missing org.freedesktop.portal.ScreenCast"
  fi
  if [ "$picker_ok" -eq 0 ]; then
    add_flag "PORTAL_FILEPICKER missing org.freedesktop.portal.FileChooser"
  fi
}

journal_group_by_service() {
  if command -v jq >/dev/null 2>&1; then
    journalctl --since '7 days ago' -p err..alert -o json --no-pager 2>/dev/null | \
      jq -r 'if ._SYSTEMD_UNIT then ._SYSTEMD_UNIT elif .SYSLOG_IDENTIFIER then .SYSLOG_IDENTIFIER else "unknown" end' | \
      sort | uniq -c | sort -nr | sed -n '1,40p'
  else
    journalctl --since '7 days ago' -p err..alert --no-pager 2>/dev/null | \
      awk '{print $5}' | sed 's/:$//' | sort | uniq -c | sort -nr | sed -n '1,40p'
  fi
}

print_storage_hotspots() {
  {
    du -xhd2 "$HOME" 2>/dev/null
    du -xhd2 /var 2>/dev/null
  } 2>/dev/null | sort -hr | sed -n '1,15p' || true
}

smart_summary() {
  local disk dev can_sudo
  can_sudo=0
  if sudo -n true >/dev/null 2>&1; then
    can_sudo=1
  fi

  dev=""
  if [ -b /dev/nvme0n1 ]; then
    dev="/dev/nvme0n1"
  else
    disk="$(lsblk -ndo NAME,TYPE | awk '$2=="disk" {print $1; exit}')"
    if [ -n "$disk" ]; then
      dev="/dev/${disk}"
    fi
  fi

  if [ -z "$dev" ]; then
    echo "No block device found for SMART summary."
    return 0
  fi

  echo "SMART target: $dev"
  if command -v smartctl >/dev/null 2>&1; then
    if [ "$EUID" -eq 0 ]; then
      smartctl -H "$dev" 2>/dev/null | sed -n '1,20p' || true
    elif [ "$can_sudo" -eq 1 ]; then
      sudo -n smartctl -H "$dev" 2>/dev/null | sed -n '1,20p' || true
    else
      echo "smartctl present but root access is required (run with sudo for full output)."
    fi
  else
    echo "smartctl not installed."
  fi

  if command -v nvme >/dev/null 2>&1 && [ "$dev" = "/dev/nvme0n1" ]; then
    if [ "$EUID" -eq 0 ]; then
      nvme smart-log "$dev" 2>/dev/null | rg -i 'critical_warning|temperature|available_spare|percentage_used|media_errors' || true
    elif [ "$can_sudo" -eq 1 ]; then
      sudo -n nvme smart-log "$dev" 2>/dev/null | rg -i 'critical_warning|temperature|available_spare|percentage_used|media_errors' || true
    else
      echo "nvme-cli present but root access is required for smart-log."
    fi
  fi
}

check_disk_flags
check_portal_flags
check_gpu_flags
check_journal_flags

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Noxflow Weekly Health Check ==="
echo "Timestamp: $(date -u '+%F %T UTC')"
host_name="$(hostname 2>/dev/null || uname -n 2>/dev/null || cat /etc/hostname 2>/dev/null || echo unknown)"
echo "Host: $host_name"
echo "RESULT: $result"
if [ "${#red_flags[@]}" -eq 0 ]; then
  echo "Red flags: none"
else
  echo "Red flags:"
  for flag in "${red_flags[@]}"; do
    echo "  - $flag"
  done
fi
echo "Log file: $LOG_FILE"

section "Hyprland"
if command -v hyprctl >/dev/null 2>&1; then
  echo "-- hyprctl version"
  hyprctl version 2>/dev/null || true
  echo
  echo "-- hyprctl monitors"
  hyprctl monitors 2>/dev/null || true
  echo
  echo "-- hyprctl clients"
  hyprctl clients 2>/dev/null || true
else
  status_warn "hyprctl not found"
fi

section "Portal / Clipboard / Notifications"
for svc in xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk; do
  state="$(systemctl --user is-active "$svc" 2>/dev/null || true)"
  printf 'service %-32s %s\n' "$svc" "${state:-unknown}"
done
portal_interface_checks
echo

if pgrep -af 'wl-paste --type text --watch .*cliphist store' >/dev/null 2>&1; then
  status_ok "clipboard text watcher running"
else
  status_warn "clipboard text watcher missing"
  add_flag "CLIPBOARD text watcher not running"
fi
if pgrep -af 'wl-paste --type image --watch .*cliphist store' >/dev/null 2>&1; then
  status_ok "clipboard image watcher running"
else
  status_warn "clipboard image watcher missing"
fi

if pgrep -x wayle >/dev/null 2>&1; then
  status_ok "notification shell: wayle"
else
  status_warn "wayle shell not detected"
  add_flag "WAYLE missing"
fi

section "NVIDIA / VA-API / Vulkan"
if nvidia-smi -L >/dev/null 2>&1; then
  status_ok "GPU detected"
  nvidia-smi --query-gpu=name,driver_version,pstate,temperature.gpu,power.draw,power.limit,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null || true
  echo
  echo "-- VRAM by process"
  nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv,noheader 2>/dev/null || true
else
  status_warn "nvidia-smi failed"
fi

if command -v vulkaninfo >/dev/null 2>&1; then
  if vulkaninfo --summary >/tmp/noxflow-health-vk.$$ 2>/tmp/noxflow-health-vk.err.$$; then
    status_ok "Vulkan functional"
    sed -n '1,40p' /tmp/noxflow-health-vk.$$
  else
    status_warn "Vulkan failed"
    add_flag "VULKAN_FAIL"
    sed -n '1,30p' /tmp/noxflow-health-vk.err.$$ || true
  fi
  rm -f /tmp/noxflow-health-vk.$$ /tmp/noxflow-health-vk.err.$$
else
  status_warn "vulkaninfo not installed"
fi

va_ok_any=0
if command -v vainfo >/dev/null 2>&1; then
  if vainfo >/tmp/noxflow-health-va.$$ 2>/tmp/noxflow-health-va.err.$$; then
    status_ok "VA-API (default) functional"
    va_ok_any=1
    sed -n '1,20p' /tmp/noxflow-health-va.$$
  else
    status_warn "VA-API (default) failed"
    sed -n '1,12p' /tmp/noxflow-health-va.err.$$ || true
  fi

  if LIBVA_DRIVER_NAME=iHD vainfo >/tmp/noxflow-health-va-ihd.$$ 2>/tmp/noxflow-health-va-ihd.err.$$; then
    status_ok "VA-API (Intel iHD) functional"
    va_ok_any=1
    sed -n '1,10p' /tmp/noxflow-health-va-ihd.$$
  else
    status_warn "VA-API (Intel iHD) failed"
    sed -n '1,10p' /tmp/noxflow-health-va-ihd.err.$$ || true
  fi

  rm -f /tmp/noxflow-health-va.$$ /tmp/noxflow-health-va.err.$$ /tmp/noxflow-health-va-ihd.$$ /tmp/noxflow-health-va-ihd.err.$$
else
  status_warn "vainfo not installed"
fi

if [ "$va_ok_any" -eq 0 ]; then
  add_flag "VAAPI_FAIL no VA-API path initialized"
fi

section "Journal errors last 7 days (grouped)"
journal_group_by_service
echo
echo "-- recent error samples"
journalctl --since '7 days ago' -p err..alert --no-pager 2>/dev/null | tail -n 80 || true

section "Disk / SSD health"
echo "-- df -h"
df -h
echo
echo "-- top 15 largest directories (/home + /var)"
print_storage_hotspots
echo
echo "-- SMART / NVMe"
smart_summary

section "Summary"
echo "RESULT: $result"
if [ "${#red_flags[@]}" -gt 0 ]; then
  echo "Flags:"
  for flag in "${red_flags[@]}"; do
    echo "  - $flag"
  done
fi

ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LINK"
echo "Latest log symlink: $LATEST_LINK"

if [ "$result" = "FAIL" ] && [ "${HEALTHCHECK_OPEN_ON_FAIL:-0}" = "1" ]; then
  if command -v code >/dev/null 2>&1; then
    code -g "$LOG_FILE" >/dev/null 2>&1 &
  elif [ -n "${EDITOR:-}" ]; then
    "${EDITOR}" "$LOG_FILE" >/dev/null 2>&1 &
  fi
fi
