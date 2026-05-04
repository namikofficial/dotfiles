#!/usr/bin/env sh
set -eu

if pgrep -x wayle >/dev/null 2>&1; then
  echo true
else
  echo false
fi
