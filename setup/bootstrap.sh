#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=setup/lib/install-manifest.sh
source "$SCRIPT_DIR/lib/install-manifest.sh"

DEFAULT_SCRIPTS_DIR=""
for candidate in \
  "$REPO_DIR/private/scripts" \
  "$HOME/Documents/code/scripts" \
  "$HOME/dev/personal-scripts"; do
  if [ -d "$candidate" ]; then
    DEFAULT_SCRIPTS_DIR="$candidate"
    break
  fi
done
DEFAULT_SCRIPTS_DIR="${DEFAULT_SCRIPTS_DIR:-$REPO_DIR/private/scripts}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$DEFAULT_SCRIPTS_DIR}"
RUN_PACKAGES=0
WITH_AUR=0
WITH_NVIDIA=""
DRY_RUN=0
NO_BACKUP=0
SET_DEFAULT_SHELL=0
INSTALL_LOCAL_AI=1
INSTALL_LOCAL_AI_MODELS=0
INSTALL_ZSH_PLUGINS=1
INSTALL_TMUX_PLUGINS=1
INSTALL_HYPR_PLUGINS=0
INSTALL_SSH_CONFIG=1
STAMP="$(date +%Y%m%d-%H%M%S)"

# The manifest records every path this run touches so 'setup/rollback.sh'
# can undo exactly those paths. It lives in the XDG state directory, not in
# the repository: it describes the machine, not the checkout.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
MANIFEST_DIR="$STATE_DIR/manifests"
MANIFEST_FILE=""

usage() {
  cat <<USAGE
Usage: $0 [options]
  --scripts-dir PATH   Path to scripts repo (default: auto-detect private/scripts, then legacy locations)
  --install-packages   Run setup/install-packages.sh after linking
  --no-ssh-config      Do not install the repository-managed ~/.ssh/config
  --with-aur           Include AUR packages (requires yay)
  --with-nvidia        Opt in to repo-managed NVIDIA package installation
  --no-nvidia          Skip repo-managed NVIDIA package installation
  --no-zsh-plugins     Skip optional zsh plugin sync
  --no-tmux-plugins    Skip optional tmux plugin sync
  --install-hypr-plugins  Build/install hyprexpo locally (must run in Hyprland session)
  --install-local-ai   Install the local llama.cpp router (user unit, preset, helpers)
  --install-local-ai-models
                       Also download the local GGUF models
  --no-local-ai        Skip local AI runtime install/linking
  --dry-run            Print the plan without writing anything
  --no-backup          Replace paths this repository already owns without keeping a backup copy
  --set-default-shell  Set the account login shell to /usr/bin/zsh
USAGE
}

while (($#)); do
  case "$1" in
    --scripts-dir)
      shift
      SCRIPTS_DIR="${1:-}"
      [ -n "$SCRIPTS_DIR" ] || {
        echo "--scripts-dir requires a path" >&2
        exit 1
      }
      ;;
    --install-packages) RUN_PACKAGES=1 ;;
    --no-ssh-config) INSTALL_SSH_CONFIG=0 ;;
    --with-aur) WITH_AUR=1 ;;
    --with-nvidia) WITH_NVIDIA="--with-nvidia" ;;
    --no-nvidia) WITH_NVIDIA="--no-nvidia" ;;
    --no-zsh-plugins) INSTALL_ZSH_PLUGINS=0 ;;
    --no-tmux-plugins) INSTALL_TMUX_PLUGINS=0 ;;
    --install-hypr-plugins) INSTALL_HYPR_PLUGINS=1 ;;
    --install-local-ai) INSTALL_LOCAL_AI=1 ;;
    --install-local-ai-models)
      INSTALL_LOCAL_AI=1
      INSTALL_LOCAL_AI_MODELS=1
      ;;
    --no-local-ai)
      INSTALL_LOCAL_AI=0
      INSTALL_LOCAL_AI_MODELS=0
      ;;
    --dry-run) DRY_RUN=1 ;;
    --no-backup) NO_BACKUP=1 ;;
    --set-default-shell) SET_DEFAULT_SHELL=1 ;;
    -h | --help)
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

# ── Plan ─────────────────────────────────────────────────────────────────
#
# Every path is planned before anything is written, so a missing source or
# an unreadable target is reported before the machine is half-configured.
PLAN_OPS=()
PLAN_SRCS=()
PLAN_DSTS=()

plan_add() {
  PLAN_OPS+=("$1")
  PLAN_SRCS+=("$2")
  PLAN_DSTS+=("$3")
}

plan_link() {
  local source="$1" target="$2"

  if [ ! -e "$source" ] && [ ! -L "$source" ]; then
    echo "Missing source: $source" >&2
    exit 1
  fi

  plan_add link "$source" "$target"
}

plan_copy() {
  local source="$1" target="$2"

  if [ ! -e "$source" ] && [ ! -L "$source" ]; then
    echo "Missing source: $source" >&2
    exit 1
  fi

  plan_add copy "$source" "$target"
}

# A runtime link points at a file a daemon regenerates (a theme cache entry),
# so the source is allowed to be absent at plan time.
plan_runtime_link() {
  plan_add runtime "$1" "$2"
}

# ── Ownership ────────────────────────────────────────────────────────────
#
# A path is 'ours' when this repository created it. Only 'ours' paths may
# be deleted outright. Anything else belongs to the user and is moved aside
# instead of being removed.
#
# A symlink counts as ours when it resolves into the checkout. A regular
# file counts as ours only when an earlier manifest recorded it as a copy
# AND it still holds the content we installed: a file the user edited after
# the install is their data, not ours.
symlink_is_ours() {
  local target="$1"
  local resolved
  resolved="$(readlink -f "$target" 2>/dev/null || true)"
  case "$resolved" in
    "$REPO_DIR"/*) return 0 ;;
  esac
  return 1
}

file_is_ours() {
  local target="$1"
  manifest_owns_target "$MANIFEST_DIR" "$target" copy || return 1
  local source
  source="$(manifest_source_for "$MANIFEST_DIR" "$target" copy || true)"
  [ -n "$source" ] || return 1
  [ -f "$source" ] || return 1
  cmp -s "$source" "$target"
}

# ── Apply ────────────────────────────────────────────────────────────────

CONFLICTS=0

ensure_parent() {
  local dir="$1"
  if ((DRY_RUN)); then
    echo "[dry-run] mkdir -p '$dir'"
    return 0
  fi
  mkdir -p "$dir"
}

# preserve_existing <target> — make room for a new path at <target>.
#
# Returns 1 when the existing path must not be replaced. The rules:
#   * a symlink into this repository is unlinked, never followed, so the
#     file it pointed at is never touched;
#   * a regular file this repository installed, still holding the content
#     we installed, may be removed when --no-backup is given;
#   * anything else (a user file, a user symlink, a directory, a file the
#     user edited) is moved aside to a timestamped backup and never
#     deleted.
preserve_existing() {
  local target="$1"

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    return 0
  fi

  if [ -L "$target" ] && symlink_is_ours "$target"; then
    local previous
    previous="$(readlink "$target" || true)"
    if ((DRY_RUN)); then
      echo "[dry-run] unlink '$target' (was -> $previous)"
      return 0
    fi
    # Record the previous link so a rollback can put it back.
    manifest_record remove "$target" "$previous"
    rm -f "$target"
    return 0
  fi

  if [ -f "$target" ] && file_is_ours "$target"; then
    if ((NO_BACKUP)); then
      if ((DRY_RUN)); then
        echo "[dry-run] rm '$target' (owned by this repository)"
      else
        rm -f "$target"
      fi
      return 0
    fi
  fi

  if ((NO_BACKUP)); then
    echo "conflict: '$target' is not owned by this repository; leaving it untouched" >&2
    CONFLICTS=$((CONFLICTS + 1))
    return 1
  fi

  local backup="${target}.bak.${STAMP}"
  if ((DRY_RUN)); then
    echo "[dry-run] mv '$target' '$backup'"
    return 0
  fi
  mv "$target" "$backup"
  echo "backed up $target -> $backup"
  BACKUP_PATH="$backup"
  return 0
}

apply_link() {
  local source="$1" target="$2"

  if [ -L "$target" ] && target_is_link_to "$target" "$source"; then
    echo "ok   $target"
    return 0
  fi

  local backup=""
  BACKUP_PATH=""
  if ! preserve_existing "$target"; then
    return 0
  fi
  backup="$BACKUP_PATH"

  ensure_parent "$(dirname "$target")"
  if ((DRY_RUN)); then
    echo "[dry-run] ln -s '$source' '$target'"
  else
    ln -s "$source" "$target"
    echo "link $target -> $source"
    manifest_record link "$target" "$source" "$backup"
  fi
}

apply_copy() {
  local source="$1" target="$2"

  if [ -f "$source" ] && [ -f "$target" ] && cmp -s "$source" "$target"; then
    echo "ok   $target"
    return 0
  fi

  local backup=""
  BACKUP_PATH=""
  if ! preserve_existing "$target"; then
    return 0
  fi
  backup="$BACKUP_PATH"

  ensure_parent "$(dirname "$target")"
  if ((DRY_RUN)); then
    echo "[dry-run] cp -a '$source' '$target'"
  else
    cp -a "$source" "$target"
    echo "copy $target <- $source"
    manifest_record copy "$target" "$source" "$backup"
  fi
}

apply_runtime_link() {
  local source="$1" target="$2"

  if [ -L "$target" ] && target_is_link_to "$target" "$source"; then
    echo "ok   $target"
    return 0
  fi

  local backup=""
  BACKUP_PATH=""
  if ! preserve_existing "$target"; then
    return 0
  fi
  backup="$BACKUP_PATH"

  ensure_parent "$(dirname "$target")"
  if ((DRY_RUN)); then
    echo "[dry-run] ln -s '$source' '$target'"
  else
    ln -s "$source" "$target"
    echo "link $target -> $source"
    manifest_record link "$target" "$source" "$backup"
  fi
}

# ── Plan contents ────────────────────────────────────────────────────────

link_path() { plan_link "$1" "$2"; }
copy_path() { plan_copy "$1" "$2"; }
link_runtime_path() { plan_runtime_link "$1" "$2"; }

link_path "$REPO_DIR/zshrc" "$HOME/.zshrc"
link_path "$REPO_DIR/bashrc" "$HOME/.bashrc"
link_path "$REPO_DIR/configs/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
link_path "$REPO_DIR/configs/claude/agents" "$HOME/.claude/agents"
link_path "$REPO_DIR/configs/claude/mcp.json" "$HOME/.claude/.mcp.json"
link_path "$REPO_DIR/sddm/dmrc" "$HOME/.dmrc"
link_path "$REPO_DIR/git/gitconfig" "$HOME/.gitconfig"
link_path "$REPO_DIR/git/hooks/commit-msg" "$HOME/.config/git/hooks/commit-msg"
link_path "$REPO_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"
link_path "$REPO_DIR/tmux/tmux-help" "$HOME/.local/bin/tmux-help"
link_path "$REPO_DIR/tmux/tmux-sessions" "$HOME/.local/bin/tmux-sessions"
link_path "$REPO_DIR/tmux/tmux-project-cockpit" "$HOME/.local/bin/tmux-project-cockpit"
link_path "$REPO_DIR/tmux/tmux-actions" "$HOME/.local/bin/tmux-actions"
link_path "$REPO_DIR/tmux/tmux-diagnostics" "$HOME/.local/bin/tmux-diagnostics"
link_path "$REPO_DIR/setup/dev-health.sh" "$HOME/.local/bin/dev-health"
link_path "$REPO_DIR/setup/check-stale-references.sh" "$HOME/.local/bin/dotfiles-stale-check"
link_path "$REPO_DIR/setup/project-profile.sh" "$HOME/.local/bin/project-profile"
link_path "$REPO_DIR/setup/mcp-profile.sh" "$HOME/.local/bin/mcp-profile"
link_path "$REPO_DIR/setup/resource-report.sh" "$HOME/.local/bin/resource-report"
link_path "$REPO_DIR/hypr/scripts/chatgpt-launcher.sh" "$HOME/.local/bin/chatgpt-launcher.sh"
link_path "$REPO_DIR/setup/client-backup.sh" "$HOME/.local/bin/client-backup"
link_path "$REPO_DIR/setup/workstationctl" "$HOME/.local/bin/workstationctl"
# noxflow-shell.service starts this launcher. The bootstrap links the unit,
# so it has to link the launcher too.
link_path "$REPO_DIR/setup/noxflow-shell-launcher.sh" "$HOME/.local/bin/noxflow-shell"
link_path "$REPO_DIR/system/node-runtime" "$HOME/.local/bin/node"
link_path "$REPO_DIR/system/node-runtime" "$HOME/.local/bin/npm"
link_path "$REPO_DIR/system/node-runtime" "$HOME/.local/bin/npx"
link_path "$REPO_DIR/system/pnpm" "$HOME/.local/bin/pnpm"
link_path "$REPO_DIR/system/desktop-launch" "$HOME/.local/bin/desktop-launch"
link_path "$REPO_DIR/system/code" "$HOME/.local/bin/code"
link_path "$REPO_DIR/tools/code-doctor/code-doctor" "$HOME/.local/bin/code-doctor"
link_path "$REPO_DIR/SHELL_CHEATSHEET.md" "$HOME/SHELL_CHEATSHEET.md"
link_path "$REPO_DIR/atuin/config.toml" "$HOME/.config/atuin/config.toml"
link_path "$REPO_DIR/starship.toml" "$HOME/.config/starship.toml"
link_path "$REPO_DIR/nvim" "$HOME/.config/nvim"
link_path "$REPO_DIR/uwsm/default-id" "$HOME/.config/uwsm/default-id"
link_path "$REPO_DIR/uwsm/env" "$HOME/.config/uwsm/env"
link_path "$REPO_DIR/uwsm/env-hyprland" "$HOME/.config/uwsm/env-hyprland"
link_path "$REPO_DIR/settings/features.env" "$HOME/.config/dotfiles/features.env"
link_path "$REPO_DIR/settings/machine.env" "$HOME/.config/dotfiles/machine.env"
link_path "$REPO_DIR/android/android-env.conf" "$HOME/.config/environment.d/60-android.conf"
link_path "$REPO_DIR/android/android-env.sh" "$HOME/.config/dotfiles/android-env.sh"
# Unreal Engine looks for Android Studio only at ~/android-studio on Linux.
if [ -x "$HOME/.local/opt/android-studio/bin/studio" ]; then
  link_path "$REPO_DIR/android/unreal-studio.sh" "$HOME/android-studio/bin/studio.sh"
  link_path "$HOME/.local/opt/android-studio/jbr" "$HOME/android-studio/jbr"
fi
link_path "$REPO_DIR/xdg-desktop-portal/hyprland-portals.conf" "$HOME/.config/xdg-desktop-portal/hyprland-portals.conf"
link_path "$REPO_DIR/systemd/user/noxflow-session-optional.service" "$HOME/.config/systemd/user/noxflow-session-optional.service"
link_path "$REPO_DIR/systemd/user/noxflow-shell.service" "$HOME/.config/systemd/user/noxflow-shell.service"
link_path "$REPO_DIR/systemd/user/noxflow-fallback.service" "$HOME/.config/systemd/user/noxflow-fallback.service"

link_path "$REPO_DIR/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua"
link_path "$REPO_DIR/hypr/conf" "$HOME/.config/hypr/conf"
link_path "$REPO_DIR/hypr/lib" "$HOME/.config/hypr/lib"
link_path "$REPO_DIR/hypr/monitor-layout.json" "$HOME/.config/hypr/monitor-layout.json"
link_path "$REPO_DIR/hypr/hypridle.conf" "$HOME/.config/hypr/hypridle.conf"
link_path "$REPO_DIR/hypr/hyprlock.conf" "$HOME/.config/hypr/hyprlock.conf"
link_path "$REPO_DIR/hypr/hyprpaper.conf" "$HOME/.config/hypr/hyprpaper.conf"
link_path "$REPO_DIR/hypr/recovery.conf" "$HOME/.config/hypr/recovery.conf"
link_path "$REPO_DIR/hypr/scripts" "$HOME/.config/hypr/scripts"
link_path "$REPO_DIR/xdg/applications/chatgpt.desktop" "$HOME/.local/share/applications/chatgpt.desktop"
link_path "$REPO_DIR/wayle/config.toml" "$HOME/.config/wayle/config.toml"
link_path "$REPO_DIR/shell/noxflow" "$HOME/.config/noxflow/shell"
# The daemon loads ~/.config/noxflow/config.toml (core/noxflow-config
# loader.rs). Without it the shell runs on code defaults only.
link_path "$REPO_DIR/configs/noxflow/config.toml" "$HOME/.config/noxflow/config.toml"
# The named profile that config selects is resolved from
# ~/.config/noxflow/profiles/<name>.toml; without them the daemon refuses to
# load ("ProfileNotFound").
link_path "$REPO_DIR/config/profiles" "$HOME/.config/noxflow/profiles"
link_path "$REPO_DIR/hypr/rofi" "$HOME/.config/rofi"
link_path "$REPO_DIR/hypr/wlogout" "$HOME/.config/wlogout"
link_runtime_path "$HOME/.cache/hypr/theme-colors-rofi.rasi" "$HOME/.config/rofi/theme-colors-rofi.rasi"
link_path "$REPO_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
link_path "$REPO_DIR/chrome/chrome-flags.conf" "$HOME/.config/chrome-flags.conf"
link_path "$REPO_DIR/cursor/cursor-flags.conf" "$HOME/.config/cursor-flags.conf"
link_path "$REPO_DIR/code/code-flags.conf" "$HOME/.config/code-flags.conf"
copy_path "$REPO_DIR/mime/mimeapps.list" "$HOME/.config/mimeapps.list"
link_path "$REPO_DIR/theme/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
link_path "$REPO_DIR/theme/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"

if ((INSTALL_LOCAL_AI)); then
  for f in "$REPO_DIR/ai/templates/"*.md; do
    [ -e "$f" ] || continue
    link_path "$f" "$HOME/.config/local-ai/templates/$(basename "$f")"
  done
  for f in "$REPO_DIR/ai/skills/"*.md; do
    [ -e "$f" ] || continue
    link_path "$f" "$HOME/.config/local-ai/skills/$(basename "$f")"
  done
  for f in "$REPO_DIR/ai/system/"*.md; do
    [ -e "$f" ] || continue
    link_path "$f" "$HOME/.config/local-ai/system/$(basename "$f")"
  done
fi

if [ -d "$SCRIPTS_DIR/bin" ]; then
  while IFS= read -r -d '' file; do
    link_path "$file" "$HOME/.local/bin/$(basename "$file")"
  done < <(find "$SCRIPTS_DIR/bin" -maxdepth 1 -type f -print0)
else
  echo "warning: scripts bin directory not found at $SCRIPTS_DIR/bin" >&2
  echo "warning: public dotfiles setup will continue without private scripts" >&2
  echo "warning: if you have access, run: git submodule update --init private/scripts" >&2
fi

# ── Apply the plan ───────────────────────────────────────────────────────

if ((DRY_RUN)); then
  echo "[dry-run] plan: ${#PLAN_OPS[@]} path(s); nothing will be written"
else
  MANIFEST_FILE="$MANIFEST_DIR/manifest-$STAMP-$$.tsv"
  manifest_init "$MANIFEST_FILE"
fi

index=0
while [ "$index" -lt "${#PLAN_OPS[@]}" ]; do
  op="${PLAN_OPS[$index]}"
  src="${PLAN_SRCS[$index]}"
  dst="${PLAN_DSTS[$index]}"
  case "$op" in
    link) apply_link "$src" "$dst" ;;
    copy) apply_copy "$src" "$dst" ;;
    runtime) apply_runtime_link "$src" "$dst" ;;
  esac
  index=$((index + 1))
done

# The obsolete managed drop-in discarded the GPU that env-hyprland selects.
# Removing it is recorded so a rollback can put the symlink back.
legacy_gpu_override="$HOME/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf"
if [ -L "$legacy_gpu_override" ]; then
  previous_link="$(readlink "$legacy_gpu_override" || true)"
  if ((DRY_RUN)); then
    echo "[dry-run] rm '$legacy_gpu_override'"
  else
    manifest_record remove "$legacy_gpu_override" "$previous_link"
    rm -f "$legacy_gpu_override"
    echo "removed obsolete $legacy_gpu_override"
  fi
fi

if ((! DRY_RUN)) && command -v luac >/dev/null 2>&1; then
  "$REPO_DIR/hypr/scripts/hypr-validate.sh" "$REPO_DIR/hypr/hyprland.lua"
fi

if ((! DRY_RUN)) && command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload 2>/dev/null || true
fi

if ((RUN_PACKAGES)); then
  cmd=("$SCRIPT_DIR/install-packages.sh")
  ((WITH_AUR)) && cmd+=(--with-aur)
  [ -n "$WITH_NVIDIA" ] && cmd+=("$WITH_NVIDIA")
  ((DRY_RUN)) && cmd+=(--dry-run)
  "${cmd[@]}"
fi

# SSH config is owned by this repository. It is installed on every bootstrap
# because ~/.ssh/config is the one file that silently changes behaviour
# everywhere: a missing alias fails at the worst moment rather than loudly.
if ((INSTALL_SSH_CONFIG)); then
  cmd=("$SCRIPT_DIR/install-ssh-config.sh")
  ((DRY_RUN)) && cmd+=(--dry-run)
  "${cmd[@]}"
fi

if ((INSTALL_ZSH_PLUGINS)); then
  cmd=("$SCRIPT_DIR/install-zsh-plugins.sh")
  ((DRY_RUN)) && cmd+=(--dry-run)
  "${cmd[@]}"
fi

if ((INSTALL_TMUX_PLUGINS)); then
  cmd=("$SCRIPT_DIR/install-tmux-plugins.sh")
  ((DRY_RUN)) && cmd+=(--dry-run)
  "${cmd[@]}"
fi

if ((SET_DEFAULT_SHELL)); then
  zsh_path="$(command -v zsh || true)"
  if [ -z "$zsh_path" ]; then
    echo "Cannot set the default shell: zsh is not installed." >&2
    exit 1
  fi
  current_shell="$(getent passwd "$USER" | cut -d: -f7 || true)"
  if [ "$current_shell" != "$zsh_path" ]; then
    if ((DRY_RUN)); then
      echo "[dry-run] chsh -s '$zsh_path' '$USER'"
    else
      chsh -s "$zsh_path" "$USER"
      echo "login shell set to $zsh_path; start a new login session to activate it"
    fi
  else
    echo "ok   login shell is already $zsh_path"
  fi
fi

if ((INSTALL_HYPR_PLUGINS)); then
  if ((DRY_RUN)); then
    echo "[dry-run] $SCRIPT_DIR/install-hypr-plugins.sh"
  else
    "$SCRIPT_DIR/install-hypr-plugins.sh"
  fi
fi

# The local AI runtime is optional. A missing llama.cpp install must not
# abort a workstation bootstrap, so failures here are reported and the rest
# of the setup continues.
if ((INSTALL_LOCAL_AI)); then
  if ((DRY_RUN)); then
    echo "[dry-run] $SCRIPT_DIR/install-llama-router.sh"
  elif ! "$SCRIPT_DIR/install-llama-router.sh"; then
    echo "warning: local llama.cpp router install failed; see the message above" >&2
    echo "warning: the rest of the workstation setup completed" >&2
  fi
  if ((INSTALL_LOCAL_AI_MODELS)); then
    if ((DRY_RUN)); then
      echo "[dry-run] $SCRIPT_DIR/download-local-models.sh core"
    elif ! "$SCRIPT_DIR/download-local-models.sh" core; then
      echo "warning: local model download failed; see the message above" >&2
    fi
  fi
fi

if ((CONFLICTS)); then
  echo "$CONFLICTS path(s) were left untouched because they are not owned by this repository." >&2
  echo "Move them aside, or re-run without --no-backup so a backup is kept." >&2
  exit 1
fi

cat <<DONE

Bootstrap complete.
- Reload shell: exec zsh
- Set the account login shell with: $0 --set-default-shell
- Restart Hyprland/login session to activate hyprland.lua after migration
DONE

if ((! DRY_RUN)) && [ -n "$MANIFEST_FILE" ]; then
  printf 'manifest: %s\n' "$MANIFEST_FILE"
  printf 'rollback:  %s --manifest %s\n' "$SCRIPT_DIR/rollback.sh" "$MANIFEST_FILE"
fi
