#!/usr/bin/env bash
set -euo pipefail

launcher_bin="${PRISM_BIN:-/usr/bin/prismlauncher}"
if [ ! -x "$launcher_bin" ]; then
  launcher_bin="$(command -v prismlauncher || true)"
fi

if [ -z "$launcher_bin" ] || [ ! -x "$launcher_bin" ]; then
  command -v notify-send >/dev/null 2>&1 && \
    notify-send -a "Prism" "Prism Launcher not found" "Install with: sudo pacman -S prismlauncher"
  exit 1
fi

# Prefer the discrete NVIDIA GPU only when the existing userland is already
# available. This keeps the wrapper harmless on systems that intentionally do
# not manage NVIDIA packages through dotfiles.
if command -v nvidia-smi >/dev/null 2>&1 || command -v nvidia-settings >/dev/null 2>&1; then
  export __NV_PRIME_RENDER_OFFLOAD=1
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export __VK_LAYER_NV_optimus=NVIDIA_only
  export DRI_PRIME=1
fi

# Keep launcher-side GPU env conservative; per-game tuning is done in Prism instance settings.

# Enable telemetry overlays only if user explicitly wants it.
: "${MANGOHUD:=0}"
export MANGOHUD

# Consistent Wayland-first behavior for Qt apps.
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland;xcb}"
export QT_QPA_PLATFORMTHEME="${QT_QPA_PLATFORMTHEME:-qt6ct}"
export QT_STYLE_OVERRIDE="${QT_STYLE_OVERRIDE:-kvantum}"
export KVANTUM_THEME="${KVANTUM_THEME:-NoxflowDynamic}"
export KDE_SESSION_VERSION=6
export KDE_FULL_SESSION=false

exec "$launcher_bin" -style kvantum "$@"
