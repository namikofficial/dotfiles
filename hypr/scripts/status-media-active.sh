#!/usr/bin/env sh
set -eu

out="$(wayle media status 2>/dev/null || echo '')"
case "$out" in
  *idle*|*no\ player*|'') echo false ;;
  *) echo true ;;
esac
