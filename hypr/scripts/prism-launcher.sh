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

# Prefer discrete NVIDIA GPU on hybrid laptops for Minecraft.
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export DRI_PRIME=1

# NVIDIA driver tuning for better frame pacing/latency.
export __GL_THREADED_OPTIMIZATIONS=1
export __GL_MaxFramesAllowed=1

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

# Run launcher + game processes under Feral GameMode when available.
if command -v gamemoderun >/dev/null 2>&1; then
  exec gamemoderun "$launcher_bin" -style kvantum "$@"
fi

exec "$launcher_bin" -style kvantum "$@"
