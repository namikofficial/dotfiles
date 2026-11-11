#!/usr/bin/env bash
# Install the dotfiles-managed ~/.ssh/config.
#
# The workstation SSH configuration is owned by this repository. This script
# makes ~/.ssh/config a symlink to ssh/config, after backing up whatever was
# there. It is safe to run repeatedly: an already-correct install is a no-op.
#
# Restoring the previous file:
#   ~/.config/dotfiles/install-ssh-config.sh --restore
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$REPO_DIR/ssh/config"
TARGET="$HOME/.ssh/config"
DRY_RUN=0
RESTORE=0
BACKUP=""
STAMP="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<USAGE
Usage: $0 [options]

  --dry-run     Report what would change; write nothing.
  --restore     Remove the symlink and put the most recent backup back.
  --help        This message.

Without options the managed file is installed. An existing ~/.ssh/config is
copied to ~/.ssh/config.bak-<timestamp> before it is replaced, and the path is
printed so the original is always recoverable.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --restore) RESTORE=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  DIM=$'\033[2m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RED=$'\033[31m'
  RESET=$'\033[0m'
else
  DIM=''
  GREEN=''
  YELLOW=''
  RED=''
  RESET=''
fi

log() { printf '%s\n' "$*"; }
ok() { printf '%sok%s    %s\n' "$GREEN" "$RESET" "$*"; }
info() { printf '%s-%s     %s\n' "$DIM" "$RESET" "$*"; }
warn() { printf '%swarn%s  %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() {
  printf '%sfatal%s %s\n' "$RED" "$RESET" "$*" >&2
  exit 1
}

if [ "$RESTORE" -eq 1 ]; then
  [ -L "$TARGET" ] || die "$TARGET is not managed by dotfiles; nothing to restore."
  latest="$(ls -1t "$HOME"/.ssh/config.bak-* 2>/dev/null | head -1 || true)"
  [ -n "$latest" ] || die "no backup found in $HOME/.ssh/config.bak-*"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] rm $TARGET"
    log "[dry-run] restore $latest -> $TARGET"
    exit 0
  fi
  rm "$TARGET"
  cp "$latest" "$TARGET"
  chmod 0600 "$TARGET"
  ok "restored $TARGET from $latest"
  log "The dotfiles copy is still at $SOURCE; re-run without --restore to return to managed mode."
  exit 0
fi

[ -f "$SOURCE" ] || die "managed SSH config not found at $SOURCE"

# Validate before touching anything. An unparseable config locks you out of
# every host at once, which is a much worse outcome than not installing.
if ! ssh -F "$SOURCE" -G nox >/dev/null 2>&1; then
  die "the managed config does not parse (ssh -F $SOURCE -G nox failed)"
fi

mkdir -p "$HOME/.ssh"
chmod 0700 "$HOME/.ssh"

if [ -L "$TARGET" ] && [ "$(readlink -f "$TARGET")" = "$(readlink -f "$SOURCE")" ]; then
  chmod 0600 "$TARGET" 2>/dev/null || true
  ok "$TARGET already points at the managed config"
else
  if [ -e "$TARGET" ]; then
    BACKUP="$TARGET.bak.$STAMP"
    if [ "$DRY_RUN" -eq 1 ]; then
      log "[dry-run] cp $TARGET $BACKUP"
      log "[dry-run] rm $TARGET"
    else
      cp -p "$TARGET" "$BACKUP"
      chmod 0600 "$BACKUP"
      rm "$TARGET"
      warn "backed up the previous config to $BACKUP"
    fi
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] ln -s $SOURCE $TARGET"
  else
    ln -s "$SOURCE" "$TARGET"
    ok "linked $TARGET -> $SOURCE"
  fi
fi

# The key the NoxOrigin hosts authenticate with. Generating one is an identity
# decision, so this reports rather than creates.
if [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
  warn "no ~/.ssh/id_ed25519.pub found."
  info "Create one with:"
  info "  ssh-keygen -t ed25519 -C \"\$(whoami)@\$(hostname)\" -f ~/.ssh/id_ed25519"
fi

log ""
log "Development data tunnel:"
# The repository tooling restarts this unit by name when a configured endpoint is
# unreachable, so the name is a contract between dotfiles and noxorigin/tooling.
TUNNEL_UNIT="nox-tunnel.service"
if systemctl --user cat "$TUNNEL_UNIT" >/dev/null 2>&1; then
  ok "$TUNNEL_UNIT is installed"
else
  warn "$TUNNEL_UNIT is not installed; remote development data will be unreachable."
  info "Install it with:"
  info "  systemctl --user link $REPO_DIR/systemd/user/$TUNNEL_UNIT"
  info "  systemctl --user enable --now $TUNNEL_UNIT"
fi

log ""
log "NoxOrigin server access (from the managed config):"
for host in nox nox-tunnel noxorigin noxorigin-tunnel; do
  # Read the managed file directly rather than ~/.ssh/config: in --dry-run, and
  # before the first install, ~/.ssh/config is still whatever was there before.
  if resolved="$(ssh -F "$SOURCE" -G "$host" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')" && [ -n "$resolved" ]; then
    printf '  %-18s %s\n' "$host" "$resolved"
  else
    printf '  %-18s %s(unresolved)%s\n' "$host" "$RED" "$RESET"
  fi
done
log ""
log "Connect with:  ssh nox"
if [ -z "$BACKUP" ]; then
  log "${DIM}Restore the previous file at any time: \$0 --restore${RESET}"
fi
