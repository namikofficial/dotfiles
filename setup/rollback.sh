#!/usr/bin/env bash
# Undo a dotfiles install using the manifest that install recorded.
#
# 'setup/bootstrap.sh' writes a manifest of every path it touched: the
# target, the source it came from, and the backup that was preserved. This
# script replays that manifest in reverse and restores exactly those paths.
#
# It is deliberately narrow. A path that the user changed after the install
# is reported and left alone, so a rollback never destroys newer work.
#
# Usage:
#   setup/rollback.sh                 # undo the most recent install
#   setup/rollback.sh --manifest PATH # undo a specific install
#   setup/rollback.sh --dry-run       # report the plan, change nothing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=setup/lib/install-manifest.sh
source "$SCRIPT_DIR/lib/install-manifest.sh"

MANIFEST=""
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: $0 [options]

  --manifest PATH  Undo the install recorded in PATH.
                   Defaults to the most recent manifest.
  --dry-run        Report what would be restored; change nothing.
  --help           This message.

Manifests live in:
  ${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/manifests
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest)
      shift
      MANIFEST="${1:-}"
      [ -n "$MANIFEST" ] || {
        echo "--manifest requires a path" >&2
        exit 2
      }
      ;;
    --manifest=*)
      MANIFEST="${1#*=}"
      [ -n "$MANIFEST" ] || {
        echo "--manifest requires a path" >&2
        exit 2
      }
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

MANIFEST_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/manifests"

if [ -z "$MANIFEST" ]; then
  MANIFEST="$(manifest_latest "$MANIFEST_DIR" || true)"
  if [ -z "$MANIFEST" ]; then
    echo "No install manifest found in $MANIFEST_DIR" >&2
    echo "Nothing to roll back." >&2
    exit 1
  fi
fi

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

actions="$(manifest_count "$MANIFEST")"
if [ "$actions" -eq 0 ]; then
  echo "Manifest $MANIFEST records no actions; nothing to roll back." >&2
  exit 0
fi

echo "Manifest: $MANIFEST ($actions recorded action(s))"
if ((DRY_RUN)); then
  echo "[dry-run] no file will be changed"
  ROLLBACK_DRY_RUN=1
fi

rollback_restore "$MANIFEST"
