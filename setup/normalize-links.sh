#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

backup_if_exists() {
  local p="$1"
  if [[ -e "$p" || -L "$p" ]]; then
    mv "$p" "${p}.bak.${STAMP}"
  fi
}

# force_link <src> <dst> [runtime] — link <dst> to <src>.
#
# A missing source is refused by default: a symlink that points at nothing is
# a broken configuration, and it is harder to notice than a missing file. A
# source that a daemon generates later is linked with the 'runtime' mode,
# where the link is allowed to dangle until the daemon writes the file.
force_link() {
  local src="$1" dst="$2" mode="${3:-strict}"
  if [[ "$mode" != "runtime" && ! -e "$src" && ! -L "$src" ]]; then
    echo "skip $dst: source does not exist: $src" >&2
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]]; then
    local resolved_dst resolved_src
    resolved_dst="$(readlink -f "$dst" || true)"
    resolved_src="$(readlink -f "$src" || true)"
    if [[ -n "$resolved_dst" && "$resolved_dst" == "$resolved_src" ]]; then
      echo "already linked $dst -> $src"
      return
    fi
  fi
  backup_if_exists "$dst"
  ln -s "$src" "$dst"
  echo "link $dst -> $src"
}

force_copy() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  backup_if_exists "$dst"
  cp -a "$src" "$dst"
  echo "copy $dst <- $src"
}

force_link "$ROOT_DIR/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua"
force_link "$ROOT_DIR/hypr/lib" "$HOME/.config/hypr/lib"
force_link "$ROOT_DIR/hypr/monitor-layout.json" "$HOME/.config/hypr/monitor-layout.json"
force_link "$ROOT_DIR/uwsm/env" "$HOME/.config/uwsm/env"
force_link "$ROOT_DIR/wayle/config.toml" "$HOME/.config/wayle/config.toml"
force_link "$ROOT_DIR/fontconfig/fonts.conf" "$HOME/.config/fontconfig/fonts.conf"
force_link "$ROOT_DIR/uwsm/env-hyprland" "$HOME/.config/uwsm/env-hyprland"
force_link "$ROOT_DIR/xdg-desktop-portal/hyprland-portals.conf" "$HOME/.config/xdg-desktop-portal/hyprland-portals.conf"
force_link "$ROOT_DIR/configs/opencode/opencode.local-llamacpp.json" "$HOME/.config/opencode/opencode.json"
force_link "$ROOT_DIR/configs/pi/models.json" "$HOME/.pi/agent/models.json"

# Official Expo skills are installed once in the shared user skill directory.
for skill in expo-overview expo-native-ui expo-router expo-data-fetching expo-dev-client expo-upgrade; do
  for skill_root in "$HOME/.claude/skills" "$HOME/.pi/agent/skills" "$HOME/.gemini/skills" "$HOME/.gemini/antigravity/skills" "$ROOT_DIR/configs/opencode/skills"; do
    force_link "$HOME/.agents/skills/$skill" "$skill_root/$skill"
  done
done
force_link "$ROOT_DIR/configs/opencode/cli.json" "$HOME/.config/opencode/cli.json"
force_link "$ROOT_DIR/configs/opencode/plugins/quota-v2" "$HOME/.config/opencode/plugins/quota-v2"
force_link "$ROOT_DIR/configs/opencode/plugins/linux-notify" "$HOME/.config/opencode/plugins/linux-notify"
force_link "$ROOT_DIR/configs/opencode/opencode-quota/quota-toast.json" "$HOME/.config/opencode/opencode-quota/quota-toast.json"
force_link "$HOME/.cache/hypr/theme-colors-rofi.rasi" "$HOME/.config/rofi/theme-colors-rofi.rasi" runtime
force_copy "$ROOT_DIR/mime/mimeapps.list" "$HOME/.config/mimeapps.list"

# ~/.local/bin/noxctl was a 3.4 MB *copy* of the cargo build output, so it
# silently drifted: the copy was rebuilt on a different day than target/release
# and neither the gate nor any check noticed. Link it instead.
#
# Skipped when the binary has not been built yet — a dangling symlink is worse
# than a stale copy, and `cargo build --release -p noxctl` fixes it.
if [[ -x "$ROOT_DIR/target/release/noxctl" ]]; then
  force_link "$ROOT_DIR/target/release/noxctl" "$HOME/.local/bin/noxctl"
else
  echo "skip ~/.local/bin/noxctl: target/release/noxctl not built" >&2
  echo "  fix: cargo build --release --manifest-path cli/noxctl/Cargo.toml" >&2
fi

# The managed DRM override was retired. DRM selection belongs to
# uwsm/env-hyprland, which exports AQ_DRM_DEVICES; a drop-in that pins the
# GPU fights it. A link left behind by an earlier run is removed here rather
# than re-created.
obsolete_drm_override="$HOME/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf"
if [[ -L "$obsolete_drm_override" ]]; then
  rm -f "$obsolete_drm_override"
  echo "removed obsolete $obsolete_drm_override"
fi

echo "Normalization complete."
