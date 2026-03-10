#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/Documents/code/scripts}"
RUN_PACKAGES=0
WITH_AUR=0
WITH_NVIDIA=""
DRY_RUN=0
NO_BACKUP=0
INSTALL_ZSH_PLUGINS=1
INSTALL_TMUX_PLUGINS=1
INSTALL_HYPR_PLUGINS=0
STAMP="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<USAGE
Usage: $0 [options]
  --scripts-dir PATH   Path to scripts repo (default: $HOME/Documents/code/scripts)
  --install-packages   Run setup/install-packages.sh after linking
  --with-aur           Include AUR packages (requires yay)
  --with-nvidia        Opt in to repo-managed NVIDIA package installation
  --no-nvidia          Skip repo-managed NVIDIA package installation
  --no-zsh-plugins     Skip optional zsh plugin sync
  --no-tmux-plugins    Skip optional tmux plugin sync
  --install-hypr-plugins  Build/install hyprexpo locally (must run in Hyprland session)
  --dry-run            Print actions without writing changes
  --no-backup          Replace existing files without backup copy
USAGE
}

while (($#)); do
  case "$1" in
    --scripts-dir)
      shift
      SCRIPTS_DIR="${1:-}"
      [ -n "$SCRIPTS_DIR" ] || { echo "--scripts-dir requires a path" >&2; exit 1; }
      ;;
    --install-packages) RUN_PACKAGES=1 ;;
    --with-aur) WITH_AUR=1 ;;
    --with-nvidia) WITH_NVIDIA="--with-nvidia" ;;
    --no-nvidia) WITH_NVIDIA="--no-nvidia" ;;
    --no-zsh-plugins) INSTALL_ZSH_PLUGINS=0 ;;
    --no-tmux-plugins) INSTALL_TMUX_PLUGINS=0 ;;
    --install-hypr-plugins) INSTALL_HYPR_PLUGINS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --no-backup) NO_BACKUP=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

backup_if_needed() {
  local target="$1"

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    return 0
  fi

  if (( NO_BACKUP )); then
    if (( DRY_RUN )); then
      echo "[dry-run] rm -rf '$target'"
    else
      rm -rf "$target"
    fi
    return 0
  fi

  local backup="${target}.bak.${STAMP}"
  if (( DRY_RUN )); then
    echo "[dry-run] mv '$target' '$backup'"
  else
    mv "$target" "$backup"
  fi
}

link_path() {
  local source="$1"
  local target="$2"

  if [ ! -e "$source" ] && [ ! -L "$source" ]; then
    echo "Missing source: $source" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$target")"

  if [ -L "$target" ]; then
    local existing
    existing="$(readlink -f "$target" || true)"
    local desired
    desired="$(readlink -f "$source" || true)"
    if [ -n "$existing" ] && [ "$existing" = "$desired" ]; then
      echo "ok   $target"
      return 0
    fi
  fi

  backup_if_needed "$target"

  if (( DRY_RUN )); then
    echo "[dry-run] ln -s '$source' '$target'"
  else
    ln -s "$source" "$target"
    echo "link $target -> $source"
  fi
}

copy_path() {
  local source="$1"
  local target="$2"

  if [ ! -e "$source" ] && [ ! -L "$source" ]; then
    echo "Missing source: $source" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$target")"

  backup_if_needed "$target"

  if (( DRY_RUN )); then
    echo "[dry-run] cp -a '$source' '$target'"
  else
    cp -a "$source" "$target"
    echo "copy $target <- $source"
  fi
}

link_path "$REPO_DIR/zshrc" "$HOME/.zshrc"
link_path "$REPO_DIR/git/gitconfig" "$HOME/.gitconfig"
link_path "$REPO_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"
link_path "$REPO_DIR/SHELL_CHEATSHEET.md" "$HOME/SHELL_CHEATSHEET.md"
link_path "$REPO_DIR/atuin/config.toml" "$HOME/.config/atuin/config.toml"
link_path "$REPO_DIR/nvim" "$HOME/.config/nvim"
link_path "$REPO_DIR/uwsm/env-hyprland" "$HOME/.config/uwsm/env-hyprland"
link_path "$REPO_DIR/systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf" "$HOME/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf"

mkdir -p "$HOME/.config/hypr" "$HOME/.config/kitty"
link_path "$REPO_DIR/hypr/hyprland.conf" "$HOME/.config/hypr/hyprland.conf"
link_path "$REPO_DIR/hypr/hypridle.conf" "$HOME/.config/hypr/hypridle.conf"
link_path "$REPO_DIR/hypr/hyprlock.conf" "$HOME/.config/hypr/hyprlock.conf"
link_path "$REPO_DIR/hypr/hyprpaper.conf" "$HOME/.config/hypr/hyprpaper.conf"
link_path "$REPO_DIR/hypr/scripts" "$HOME/.config/hypr/scripts"
link_path "$REPO_DIR/hypr/waybar" "$HOME/.config/waybar"
link_path "$REPO_DIR/hypr/rofi" "$HOME/.config/rofi"
link_path "$REPO_DIR/hypr/swaync" "$HOME/.config/swaync"
link_path "$REPO_DIR/hypr/wlogout" "$HOME/.config/wlogout"
link_path "$REPO_DIR/hypr/dunst" "$HOME/.config/dunst"
link_path "$REPO_DIR/hypr/eww" "$HOME/.config/eww"
link_path "$REPO_DIR/hypr/eww-settings" "$HOME/.config/eww-settings"
link_path "$REPO_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
link_path "$REPO_DIR/chrome/chrome-flags.conf" "$HOME/.config/chrome-flags.conf"
copy_path "$REPO_DIR/mime/mimeapps.list" "$HOME/.config/mimeapps.list"
copy_path "$REPO_DIR/kde/kdeglobals" "$HOME/.config/kdeglobals"
link_path "$REPO_DIR/kde/dolphinrc" "$HOME/.config/dolphinrc"
link_path "$REPO_DIR/kde/kiorc" "$HOME/.config/kiorc"
link_path "$REPO_DIR/kde/gwenviewrc" "$HOME/.config/gwenviewrc"
link_path "$REPO_DIR/theme/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
link_path "$REPO_DIR/theme/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
link_path "$REPO_DIR/theme/qt5ct/qt5ct.conf" "$HOME/.config/qt5ct/qt5ct.conf"
link_path "$REPO_DIR/theme/qt6ct/qt6ct.conf" "$HOME/.config/qt6ct/qt6ct.conf"
copy_path "$REPO_DIR/theme/Kvantum" "$HOME/.config/Kvantum"

if (( DRY_RUN )); then
  echo "[dry-run] mkdir -p '$HOME/.local/bin'"
else
  mkdir -p "$HOME/.local/bin"
fi

if [ -d "$SCRIPTS_DIR/bin" ]; then
  while IFS= read -r -d '' file; do
    target="$HOME/.local/bin/$(basename "$file")"
    if (( DRY_RUN )); then
      echo "[dry-run] ln -sf '$file' '$target'"
    else
      ln -sf "$file" "$target"
    fi
  done < <(find "$SCRIPTS_DIR/bin" -maxdepth 1 -type f -print0)
else
  echo "warning: scripts bin directory not found at $SCRIPTS_DIR/bin" >&2
fi

if (( RUN_PACKAGES )); then
  cmd=("$SCRIPT_DIR/install-packages.sh")
  (( WITH_AUR )) && cmd+=(--with-aur)
  [ -n "$WITH_NVIDIA" ] && cmd+=("$WITH_NVIDIA")
  (( DRY_RUN )) && cmd+=(--dry-run)
  "${cmd[@]}"
fi

if (( INSTALL_ZSH_PLUGINS )); then
  cmd=("$SCRIPT_DIR/install-zsh-plugins.sh")
  (( DRY_RUN )) && cmd+=(--dry-run)
  "${cmd[@]}"
fi

if (( INSTALL_TMUX_PLUGINS )); then
  cmd=("$SCRIPT_DIR/install-tmux-plugins.sh")
  (( DRY_RUN )) && cmd+=(--dry-run)
  "${cmd[@]}"
fi

if (( INSTALL_HYPR_PLUGINS )); then
  if (( DRY_RUN )); then
    echo "[dry-run] $SCRIPT_DIR/install-hypr-plugins.sh"
  else
    "$SCRIPT_DIR/install-hypr-plugins.sh"
  fi
fi

cat <<DONE

Bootstrap complete.
- Reload shell: exec zsh
- Reload Hyprland: hyprctl reload
DONE
