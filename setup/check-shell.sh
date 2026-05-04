#!/usr/bin/env bash
set -euo pipefail

command -v shellcheck >/dev/null 2>&1 || {
  printf 'Missing command: shellcheck\n' >&2
  exit 1
}

command -v shfmt >/dev/null 2>&1 || {
  printf 'Missing command: shfmt\n' >&2
  exit 1
}

find setup system hypr/scripts -type f -name '*.sh' -print0 |
  xargs -0 shellcheck

find setup system hypr/scripts -type f -name '*.sh' -print0 |
  xargs -0 shfmt -d -i 2 -ci
