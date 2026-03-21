#!/usr/bin/env bash
set -euo pipefail

prism_dir="${PRISM_DIR:-$HOME/.local/share/PrismLauncher}"
apps_dir="$HOME/.local/share/applications"
wrapper="$HOME/.config/hypr/scripts/prism-launcher.sh"
mkdir -p "$apps_dir"

jvm_args='-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=50 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=20 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=15 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=20 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1'
max_mem="${PRISM_MAX_MEM_MB:-6144}"
min_mem="${PRISM_MIN_MEM_MB:-1024}"

upsert_kv() {
  local file="$1" key="$2" val="$3"
  if rg -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}

if [ -d "$prism_dir/instances" ]; then
  while IFS= read -r -d '' cfg; do
    upsert_kv "$cfg" "EnableFeralGamemode" "true"
    upsert_kv "$cfg" "EnableMangoHud" "true"
    upsert_kv "$cfg" "OverridePerformance" "true"
    upsert_kv "$cfg" "UseDiscreteGpu" "true"
    upsert_kv "$cfg" "OverrideMemory" "true"
    upsert_kv "$cfg" "MaxMemAlloc" "$max_mem"
    upsert_kv "$cfg" "MinMemAlloc" "$min_mem"
    upsert_kv "$cfg" "OverrideJavaArgs" "true"
    upsert_kv "$cfg" "JvmArgs" "$jvm_args"
  done < <(find "$prism_dir/instances" -maxdepth 3 -type f -name 'instance.cfg' -print0)
fi

cat > "$apps_dir/org.prismlauncher.PrismLauncher.desktop" <<DESKTOP
[Desktop Entry]
Version=1.0
Name=Prism Launcher
Comment=Discover, manage, and play Minecraft instances
Type=Application
Terminal=false
Exec=$wrapper %U
StartupNotify=true
Icon=org.prismlauncher.PrismLauncher
Categories=Game;ActionGame;AdventureGame;Simulation;PackageManager;
Keywords=game;minecraft;mc;
StartupWMClass=PrismLauncher
MimeType=application/zip;application/x-modrinth-modpack+zip;x-scheme-handler/curseforge;x-scheme-handler/prismlauncher;
DESKTOP

cat > "$apps_dir/prism-mc.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=Prism MC Performance
GenericName=Minecraft Launcher
Comment=Launch Prism Launcher with discrete-GPU preferences + GameMode
Exec=$wrapper
Icon=org.prismlauncher.PrismLauncher
Terminal=false
Categories=Game;
Keywords=minecraft;mc;prismlauncher;prism;
StartupNotify=true
DESKTOP

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
fi

if [ -x "$HOME/.config/hypr/scripts/launcher.sh" ]; then
  "$HOME/.config/hypr/scripts/launcher.sh" --rebuild-cache >/dev/null 2>&1 || true
fi

echo "Prism performance profile applied."
echo "- Wrapper: ~/.config/hypr/scripts/prism-launcher.sh"
echo "- Desktop entries overridden in: ~/.local/share/applications"
echo "- Instance defaults: gamemode+mangohud+discrete GPU+JVM args+memory (${min_mem}-${max_mem} MB)"
