#!/usr/bin/env sh
set -eu

if systemctl --user is-active --quiet wayle.service 2>/dev/null; then
  echo true
else
  echo false
fi
