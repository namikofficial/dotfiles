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

echo "[1/8] Boot entry status"
bootctl status 2>/dev/null | rg 'Current Entry|Default Entry' || true
echo

echo "[2/8] NVIDIA package + module"
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

echo "[3/8] Runtime checks"
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

echo "[4/8] Hyprland plugin state"
if hyprctl plugin list 2>/dev/null | rg -q 'hyprexpo'; then
  hyprctl plugin list 2>/dev/null
  ok "hyprexpo loaded"
else
  warn "hyprexpo not loaded"
fi
echo

echo "[5/8] Browser default"
browser="$(xdg-settings get default-web-browser 2>/dev/null || true)"
echo "default browser: ${browser:-unknown}"
if [[ "$browser" == "google-chrome.desktop" || "$browser" == "google-chrome-stable.desktop" ]]; then
  ok "Chrome is default browser"
else
  warn "Chrome is not default browser"
fi
echo

echo "[6/8] Zsh keybindings"
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

echo "[7/8] Boot hang scan (current boot)"
hang_hits="$(journalctl -b -k --no-pager | rg -i 'blocked for more|task .*blocked|nv_drm_dev_load|nvidia-persiste|watchdog did not stop' || true)"
if [[ -n "$hang_hits" ]]; then
  warn "Detected potential hang signatures in current boot"
  printf '%s\n' "$hang_hits" | tail -n 20
else
  ok "No hang signatures in current boot"
fi
echo

echo "[8/8] Convenience restart (quiet logging)"
"$REPO_DIR/hypr/scripts/restart-waybar.sh" || true
echo "waybar log: ${XDG_STATE_HOME:-$HOME/.local/state}/noxflow/waybar.log"
echo

ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LINK"

echo "Summary: ok=$status_ok warn=$status_warn"
if (( status_warn > 0 )); then
  echo "RESULT: WARN"
else
  echo "RESULT: PASS"
fi
echo "Latest log: $LATEST_LINK"
