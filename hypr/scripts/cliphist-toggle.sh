#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
daemon_ctl="$script_dir/cliphist-daemon.sh"
ipc="$script_dir/cliphist-ipc.py"

if python3 "$ipc" toggle >/dev/null 2>&1; then
  exit 0
fi

[ -x "$daemon_ctl" ] || exit 0
"$daemon_ctl" start >/dev/null 2>&1 || exit 0
python3 "$ipc" toggle >/dev/null 2>&1 || true
