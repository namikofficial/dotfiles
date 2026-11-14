#!/usr/bin/env bash
# shellcheck shell=bash
# install-manifest.sh - shared install bookkeeping for the dotfiles setup.
#
# Why this exists
# ---------------
# The installers used to write a target and forget it. When a link had to be
# replaced, the previous content was either dropped or left as a stray
# '*.bak.<stamp>' file that nobody could map back to the path it came from.
# Rolling back then meant guessing.
#
# Every install now records a manifest: one line per action, with the target,
# the source it came from, and the backup that was preserved (empty when there
# was nothing to preserve). 'setup/rollback.sh' replays a manifest in reverse
# and restores exactly those paths.
#
# Manifest format (tab separated, '#' starts a comment):
#
#   action<TAB>target<TAB>source<TAB>backup
#
#   action   link | copy | remove
#   target   absolute path that was written
#   source   where the content came from; for 'remove', the link target that
#            used to live there
#   backup   path the previous content was moved to, or empty when the target
#            did not exist before
#
# This file is a library, not an executable. It is sourced by setup/bootstrap.sh
# and setup/rollback.sh.

MANIFEST_ACTION=""
MANIFEST_TARGET=""
MANIFEST_SOURCE=""
MANIFEST_BACKUP=""

# Set to 1 to make rollback_restore report what it would do without
# touching the filesystem.
ROLLBACK_DRY_RUN=0

# manifest_init <path> - create the manifest file with its header.
manifest_init() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  {
    printf '# dotfiles install manifest v1\n'
    printf '# action\ttarget\tsource\tbackup\n'
  } >"$path"
}

# manifest_record <action> <target> <source> [backup]
#
# Append one action. Nothing is written when the manifest path is empty, so
# callers can run with manifest recording disabled.
manifest_record() {
  local action="$1" target="$2" source="$3" backup="${4:-}"
  [ -n "$MANIFEST_FILE" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "$action" "$target" "$source" "$backup" >>"$MANIFEST_FILE"
}

# manifest_rows <path> - print the action rows of a manifest, skipping the
# header and blank lines.
manifest_rows() {
  local path="$1"
  [ -f "$path" ] || return 0
  local line
  while IFS= read -r line; do
    case "$line" in
      '#'*) continue ;;
      '') continue ;;
    esac
    printf '%s\n' "$line"
  done <"$path"
}

# manifest_list <dir> - print the manifest paths in <dir>, newest first.
manifest_list() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  find "$dir" -maxdepth 1 -name 'manifest-*.tsv' -type f -printf '%T@ %p\n' 2>/dev/null |
    sort -rn | cut -d' ' -f2-
}

# manifest_latest <dir> - print the most recent manifest path in <dir>.
manifest_latest() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  local latest
  latest="$(manifest_list "$dir" | head -1)"
  [ -n "$latest" ] || return 1
  printf '%s\n' "$latest"
}

# manifest_count <path> - number of action rows in a manifest.
manifest_count() {
  local path="$1"
  manifest_rows "$path" | grep -c . || true
}

# target_is_link_to <target> <source> - true when <target> is a symlink that
# still resolves to <source>.
target_is_link_to() {
  local target="$1" source="$2"
  [ -L "$target" ] || return 1
  local resolved desired
  resolved="$(readlink -f "$target" 2>/dev/null || true)"
  desired="$(readlink -f "$source" 2>/dev/null || true)"
  [ -n "$resolved" ] && [ "$resolved" = "$desired" ]
}

# manifest_owns_target <dir> <target> [action] - true when a manifest in
# <dir> recorded <target>. When <action> is given, only rows with that
# action count ('link', 'copy' or 'remove').
manifest_owns_target() {
  local dir="$1" target="$2" action="${3:-}"
  [ -d "$dir" ] || return 1
  [ -n "$target" ] || return 1

  local manifest
  while IFS= read -r manifest; do
    [ -n "$manifest" ] || continue
    if manifest_rows "$manifest" |
      awk -F'\t' -v t="$target" -v a="$action" '
        $2 == t && (a == "" || $1 == a) { found = 1 }
        END { exit found ? 0 : 1 }
      '; then
      return 0
    fi
  done < <(manifest_list "$dir")

  return 1
}

# manifest_source_for <dir> <target> [action] - print the source recorded
# for <target> by the most recent matching manifest row.
manifest_source_for() {
  local dir="$1" target="$2" action="${3:-}"
  [ -d "$dir" ] || return 1
  [ -n "$target" ] || return 1

  local manifest source=""
  while IFS= read -r manifest; do
    [ -n "$manifest" ] || continue
    source="$(manifest_rows "$manifest" |
      awk -F'\t' -v t="$target" -v a="$action" '
        $2 == t && (a == "" || $1 == a) { s = $3 }
        END { print s }
      ')"
    if [ -n "$source" ]; then
      printf '%s\n' "$source"
      return 0
    fi
  done < <(manifest_list "$dir")

  return 1
}

# rollback_restore <manifest> - undo the actions in a manifest, newest first.
#
# Only paths the manifest records are touched, and a path is only removed when
# it still holds the content the manifest installed. A file the user edited
# after the install is left alone and reported.
rollback_restore() {
  local manifest="$1"
  local restored=0 skipped=0

  local rows
  rows="$(manifest_rows "$manifest" | tac)"

  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    IFS=$'\t' read -r MANIFEST_ACTION MANIFEST_TARGET MANIFEST_SOURCE MANIFEST_BACKUP <<<"$line"

    case "$MANIFEST_ACTION" in
      link | copy)
        if [ -n "$MANIFEST_BACKUP" ] && [ -e "$MANIFEST_BACKUP" ]; then
          # The previous content is still parked in the backup. Put it back.
          if ((ROLLBACK_DRY_RUN)); then
            printf 'would restore %s (from %s)\n' "$MANIFEST_TARGET" "$MANIFEST_BACKUP"
          else
            rm -f "$MANIFEST_TARGET"
            mv "$MANIFEST_BACKUP" "$MANIFEST_TARGET"
            printf 'restore %s\n' "$MANIFEST_TARGET"
          fi
          restored=$((restored + 1))
        elif [ -n "$MANIFEST_SOURCE" ] && target_is_link_to "$MANIFEST_TARGET" "$MANIFEST_SOURCE"; then
          if ((ROLLBACK_DRY_RUN)); then
            printf 'would remove  %s\n' "$MANIFEST_TARGET"
          else
            rm -f "$MANIFEST_TARGET"
            printf 'remove  %s\n' "$MANIFEST_TARGET"
          fi
          restored=$((restored + 1))
        elif [ "$MANIFEST_ACTION" = "copy" ] && [ -f "$MANIFEST_SOURCE" ] &&
          cmp -s "$MANIFEST_SOURCE" "$MANIFEST_TARGET"; then
          # A file we copied, still holding the content we copied. The user
          # did not touch it, so the install can be undone.
          if ((ROLLBACK_DRY_RUN)); then
            printf 'would remove  %s\n' "$MANIFEST_TARGET"
          else
            rm -f "$MANIFEST_TARGET"
            printf 'remove  %s\n' "$MANIFEST_TARGET"
          fi
          restored=$((restored + 1))
        else
          printf 'skip    %s (changed since the install)\n' "$MANIFEST_TARGET"
          skipped=$((skipped + 1))
        fi
        ;;
      remove)
        if [ -n "$MANIFEST_SOURCE" ] && [ ! -e "$MANIFEST_TARGET" ]; then
          if ((ROLLBACK_DRY_RUN)); then
            printf 'would restore %s -> %s\n' "$MANIFEST_TARGET" "$MANIFEST_SOURCE"
          else
            mkdir -p "$(dirname "$MANIFEST_TARGET")"
            ln -s "$MANIFEST_SOURCE" "$MANIFEST_TARGET"
            printf 'restore %s\n' "$MANIFEST_TARGET"
          fi
          restored=$((restored + 1))
        else
          printf 'skip    %s (already present)\n' "$MANIFEST_TARGET"
          skipped=$((skipped + 1))
        fi
        ;;
      *)
        printf 'skip    %s (unknown action %s)\n' "$MANIFEST_TARGET" "$MANIFEST_ACTION"
        skipped=$((skipped + 1))
        ;;
    esac
  done <<<"$rows"

  printf 'rollback: %d restored, %d skipped\n' "$restored" "$skipped"
  return 0
}
