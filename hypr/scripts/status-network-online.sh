#!/usr/bin/env sh
set -eu

if ! command -v networkctl >/dev/null 2>&1; then
  echo false
  exit 0
fi

networkctl status --no-pager 2>/dev/null | grep -Eq 'Online state: online|State: routable' && echo true || echo false
