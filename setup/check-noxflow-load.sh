#!/usr/bin/env bash
# check-noxflow-load.sh — prove the shell config actually loads.
#
# Why this exists: `qmllint` passes a shell whose every component fails to
# instantiate. It cannot resolve the Quickshell C++ module imports, so it
# reports nothing and exits 0 — during the Phase 3 split, `bar/TrayCapsule.qml`
# declared `SystemTray { }` (a non-creatable singleton),
# `island/IslandEngagement.qml` defined `function escape()` (an illegal method
# name) and `IslandCard.qml` had an upper-case `ICONS` property. The shell did
# not start, and all 14 static suites still passed.
#
# `quickshell -p` exits 0 even when the config fails to load, so this greps the
# output for the load failure instead of trusting the status.
#
# IMPORTANT — never run this while the live shell is up. `quickshell -p` starts
# a *second* shell process, which registers its own layer-shell surface and
# draws a second top bar over the running one until it is killed. An earlier
# version of this script did exactly that. When the systemd unit is running,
# this restarts it instead and reads the result from the journal; there is then
# exactly one shell on screen at every moment.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${1:-$repo_dir/shell/noxflow/shell.qml}"

if ! command -v quickshell >/dev/null 2>&1; then
  echo 'FAIL: quickshell is not installed; cannot verify the config loads' >&2
  exit 1
fi

if [[ ! -f "$config" ]]; then
  echo "FAIL: config not found: $config" >&2
  exit 1
fi

# The one benign warning: a first-run read of generated clipboard state.
# See shell/noxflow/AGENTS.md.
benign='ClipboardModel.qml.*Read of .*clipboard.json failed'

# ── Live path: the systemd unit is already running ───────────────────────────
# Restart it and judge the result from its own journal, so the screen never has
# two shells at once.
# Use the systemd path whenever the unit exists, not only when it happens to be
# active. A failed unit is inactive, and taking the isolated path there started
# a second quickshell next to a possibly-recovered fallback — the double top
# bar this script exists to avoid. The isolated path is for CI, where the unit
# is not installed at all.
if systemctl --user cat noxflow-shell.service >/dev/null 2>&1; then
  systemctl --user restart noxflow-shell.service

  # Wait for the new instance to finish loading instead of sleeping a guessed
  # interval. A fixed sleep raced the service start and read an empty journal,
  # which then looked like "quickshell neither loaded nor reported a failure".
  loaded=0
  for _ in $(seq 1 30); do
    sleep 1
    since="$(systemctl --user show noxflow-shell.service -p ActiveEnterTimestamp --value 2>/dev/null || true)"
    [ -n "$since" ] || continue
    out="$(journalctl --user -u noxflow-shell.service --since "$since" --no-pager -o cat 2>/dev/null || true)"
    if grep -q 'Configuration Loaded' <<<"$out" || grep -q 'Failed to load configuration' <<<"$out"; then
      loaded=1
      break
    fi
  done
  # Read only the new instance's journal. A fixed `--since '-15s'` window also
  # caught the outgoing process's tail, so a warning from the run being
  # replaced failed the check for the run that replaced it. `_BOOT_ID` is no
  # use here: it is the *system* boot, identical for every instance this boot.
  if [ "$loaded" -eq 0 ]; then
    echo 'FAIL: noxflow-shell.service did not report a load verdict within 30s' >&2
    journalctl --user -u noxflow-shell.service -n 30 --no-pager -o cat >&2 || true
    exit 1
  fi

  mode='live restart of noxflow-shell.service'
else
  # ── Offline path: nothing is running, a short-lived instance is safe ───────
  out="$(mktemp)"
  trap 'rm -f "$out"' EXIT
  # 20s is enough to construct every component and reach "Configuration Loaded".
  # The config keeps running afterwards, so the timeout is expected; the verdict
  # comes from the log text, not the exit status.
  timeout 20 quickshell -p "$config" >"$out" 2>&1 || true
  mode="isolated load of $config"
fi

if grep -q 'Failed to load configuration' <<<"$out"; then
  echo "FAIL: the shell config does not load: $config" >&2
  grep -E 'ERROR' <<<"$out" | head -20 >&2
  exit 1
fi

if ! grep -q 'Configuration Loaded' <<<"$out"; then
  echo "FAIL: quickshell neither loaded nor reported a failure for $config" >&2
  tail -20 <<<"$out" >&2
  exit 1
fi

# A component that fails at instantiation after load still prints warnings.
# Treat any scene WARN as a failure, with the documented first-run exception.
violations="$(grep -E 'WARN' <<<"$out" | grep -vE "$benign" || true)"
if [[ -n "$violations" ]]; then
  echo "FAIL: the shell loaded but reported warnings:" >&2
  echo "$violations" | head -20 >&2
  exit 1
fi

printf 'noxflow config loads cleanly (%s)\n' "$mode"
