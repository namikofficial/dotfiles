#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"

TS="$(date -u +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/post-reboot-${TS}.log"
LATEST_LINK="$LOG_DIR/post-reboot-latest.log"

exec > >(tee -a "$LOG_FILE") 2>&1

status_ok=0
status_warn=0

ok() {
  status_ok=$((status_ok + 1))
  echo "[OK]   $*"
}

warn() {
  status_warn=$((status_warn + 1))
  echo "[WARN] $*"
}

echo "=== Post-reboot verify ($(date -u +%F' '%T' UTC')) ==="
echo "repo: $REPO_DIR"
echo "log:  $LOG_FILE"
echo

echo "[1/14] Boot entry status"
bootctl status 2>/dev/null | rg 'Current Entry|Default Entry' || true
echo

echo "[2/14] NVIDIA package + module"
pacman -Q nvidia-open-dkms nvidia-utils nvidia-settings nvidia-prime 2>/dev/null || true
license="$(modinfo -F license nvidia 2>/dev/null || true)"
if [[ -n "$license" ]]; then
  echo "module license: $license"
  if [[ "$license" == "Dual MIT/GPL" ]]; then
    ok "NVIDIA open kernel module is loaded"
  elif [[ "$license" == "NVIDIA" ]]; then
    ok "NVIDIA proprietary kernel module is loaded"
  else
    warn "Unknown NVIDIA module license: $license"
  fi
else
  warn "NVIDIA kernel module not found"
fi
echo

echo "[3/14] Runtime checks"
if nvidia-smi -L >/dev/null 2>&1; then
  nvidia-smi -L
  ok "nvidia-smi can talk to the driver"
else
  warn "nvidia-smi failed"
fi

if vulkaninfo >/tmp/noxflow-vulkaninfo.$$ 2>/tmp/noxflow-vulkaninfo-err.$$; then
  sed -n '1,10p' /tmp/noxflow-vulkaninfo.$$
  ok "Vulkan initializes"
else
  warn "Vulkan failed"
  sed -n '1,20p' /tmp/noxflow-vulkaninfo-err.$$ || true
fi

if LIBVA_DRIVER_NAME=iHD vainfo >/tmp/noxflow-vainfo.$$ 2>/tmp/noxflow-vainfo-err.$$; then
  sed -n '1,8p' /tmp/noxflow-vainfo.$$
  ok "VA-API works on Intel iGPU"
else
  warn "VA-API failed on Intel iGPU"
  sed -n '1,20p' /tmp/noxflow-vainfo-err.$$ || true
fi
rm -f /tmp/noxflow-vulkaninfo.$$ /tmp/noxflow-vulkaninfo-err.$$ /tmp/noxflow-vainfo.$$ /tmp/noxflow-vainfo-err.$$
echo

echo "[4/14] Hyprland plugin state"
if hyprctl plugin list 2>/dev/null | rg -q 'hyprexpo'; then
  hyprctl plugin list 2>/dev/null
  ok "hyprexpo loaded"
else
  warn "hyprexpo not loaded"
fi
echo

echo "[5/14] Hyprland runtime version"
if command -v hyprctl >/dev/null 2>&1; then
  hyprctl version || warn "hyprctl version failed"
else
  warn "hyprctl missing"
fi
echo

echo "[6/14] Hyprland ecosystem packages"
pacman -Q \
  hyprland \
  hyprutils \
  aquamarine \
  hyprpaper \
  xdg-desktop-portal \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal-gtk \
  pipewire \
  pipewire-pulse \
  wireplumber 2>/dev/null || warn "one or more Hyprland ecosystem packages are missing"
echo

check_user_service() {
  local svc="$1"
  if systemctl --user is-active --quiet "$svc"; then
    ok "user service active: $svc"
  else
    warn "user service not active: $svc"
    systemctl --user status "$svc" --no-pager || true
  fi
}

echo "[7/14] Portal and media services"
check_user_service xdg-desktop-portal.service
check_user_service xdg-desktop-portal-hyprland.service
check_user_service xdg-desktop-portal-gtk.service
check_user_service pipewire.service
check_user_service pipewire-pulse.service
check_user_service wireplumber.service
echo

echo "[8/14] Portal routing preferences"
for f in \
  "$HOME/.config/xdg-desktop-portal/hyprland-portals.conf" \
  /usr/share/xdg-desktop-portal/hyprland-portals.conf \
  /usr/share/xdg-desktop-portal/gtk-portals.conf \
  /usr/share/xdg-desktop-portal/kde-portals.conf; do
  if [[ -f "$f" ]]; then
    echo "--- $f"
    sed -n '1,80p' "$f"
  fi
done
echo

echo "[9/14] Browser default"
browser="$(xdg-settings get default-web-browser 2>/dev/null || true)"
echo "default browser: ${browser:-unknown}"
if [[ "$browser" == "google-chrome.desktop" || "$browser" == "google-chrome-stable.desktop" ]]; then
  ok "Chrome is default browser"
else
  warn "Chrome is not default browser"
fi
echo

echo "[10/14] Zsh keybindings"
zsh_bind_r="$(zsh -ic "bindkey -M emacs '^R'" 2>/dev/null || true)"
zsh_bind_c="$(zsh -ic "bindkey -M emacs '^[c'" 2>/dev/null || true)"
echo "emacs ^R: $zsh_bind_r"
echo "emacs Alt-C: $zsh_bind_c"
if [[ "$zsh_bind_r" == *"atuin-search"* ]]; then
  ok "Atuin Ctrl-R binding active"
else
  warn "Atuin Ctrl-R binding not active"
fi
if [[ "$zsh_bind_c" == *"fzf_jump_widget"* ]]; then
  ok "Alt-C fuzzy jump binding active"
else
  warn "Alt-C fuzzy jump binding not active"
fi
echo

echo "[11/14] Boot hang scan (current boot)"
hang_hits="$(journalctl -b -k --no-pager | rg -i 'blocked for more|task .*blocked|nv_drm_dev_load|nvidia-persiste|watchdog did not stop' || true)"
if [[ -n "$hang_hits" ]]; then
  warn "Detected potential hang signatures in current boot"
  printf '%s\n' "$hang_hits" | tail -n 20
else
  ok "No hang signatures in current boot"
fi
echo

echo "[12/14] Cold-boot login blocker scan"
wait_online_log="$(journalctl -b -u systemd-networkd-wait-online.service --no-pager 2>/dev/null || true)"
if [[ -z "$wait_online_log" ]]; then
  ok "networkd-wait-online not active this boot"
elif printf '%s\n' "$wait_online_log" | rg -q 'Timeout occurred|Failed to start'; then
  warn "networkd-wait-online timed out; this can block graphical.target and break UWSM logins"
  networkctl list --no-pager || true
else
  ok "networkd-wait-online completed without blocking the boot"
fi
echo

echo "[13/14] Failed system units"
if systemctl --failed --no-pager | rg -q '0 loaded units listed'; then
  ok "no failed system units"
else
  warn "failed system units present"
  systemctl --failed --no-pager || true
fi
echo

echo "[14/14] Failed user units"
if systemctl --user --failed --no-pager | rg -q '0 loaded units listed'; then
  ok "no failed user units"
else
  warn "failed user units present"
  systemctl --user --failed --no-pager || true
fi
echo

ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LINK"

echo "Summary: ok=$status_ok warn=$status_warn"
if (( status_warn > 0 )); then
  echo "RESULT: WARN"
else
  echo "RESULT: PASS"
fi
echo "Latest log: $LATEST_LINK"
