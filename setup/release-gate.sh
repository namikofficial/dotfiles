#!/usr/bin/env bash
# The NoxFlow release gate.
#
# The gate used to run everything in one pass, which meant a check that needs
# a running desktop was inseparable from a check that only reads the tree. A
# CI runner therefore had to have a logged-in Hyprland session, a live
# noxd and an installed Quickshell, or the gate could not be trusted.
#
# The gate is split into three modes:
#
#   verify-static       Reads the repository tree. Needs no compiler, no
#                       package manager and no desktop session.
#   verify-integration  Builds and runs the code on this machine. Needs the
#                       toolchain, but no logged-in session.
#   verify-live         Needs a logged-in Hyprland session: the installed
#                       packages, the running services and the shell-to-daemon
#                       IPC link.
#
# CI runs 'verify-static' and 'verify-integration'. 'verify-live' belongs to
# the workstation itself.
#
# Usage:
#   setup/release-gate.sh [verify-static|verify-integration|verify-live|all]
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

usage() {
  cat <<USAGE
Usage: $0 [mode]

Modes:
  verify-static       Repository-only checks; no toolchain, no session.
  verify-integration  Builds and runs the code; needs the toolchain, no session.
  verify-live         Needs a logged-in Hyprland session and running services.
  all                 Every mode, in order (the historical behaviour).

With no argument the gate runs 'all'.
USAGE
}

mode="all"
case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  verify-static | verify-integration | verify-live | all) mode="$1" ;;
  *)
    echo "Unknown mode: $1" >&2
    usage >&2
    exit 2
    ;;
esac

# The gate keeps its own output in an isolated directory. A shared path in
# /tmp let two concurrent gates overwrite each other's output, and left a
# stale file from a previous run available to be reported as this run's
# failure.
gate_tmp="$(mktemp -d "${TMPDIR:-/tmp}/noxflow-release-gate.XXXXXXXX")"
cleanup() {
  rm -rf "$gate_tmp"
}
trap cleanup EXIT

failed=0
check() {
  local name="$1"
  shift
  printf '[gate] %-38s' "$name"
  if "$@" >"$gate_tmp/out" 2>"$gate_tmp/err"; then
    echo PASS
  else
    echo FAIL
    sed -n '1,24p' "$gate_tmp/err" >&2
    failed=1
  fi
}

# ── static checks ─────────────────────────────────────────────────────────
# These read the repository and the tools that read it. Nothing here talks to
# systemd, pacman or a compositor.

check_ipc_docs() {
  local file changed=""
  # Only a semantic change needs a doc update. Whitespace-only edits — which
  # `cargo fmt` produces routinely — do not change the protocol, and demanding
  # an IPC doc edit for a re-indented assertion trains people to ignore this
  # check. Compare each changed file against its rustfmt-normalised form to
  # tell formatting apart from meaning.
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    local normalised current
    normalised="$gate_tmp/normalised" current="$gate_tmp/current"
    # `--emit stdout` prints a "<path>:" header when reading a named file but
    # not when reading stdin, so feed the content through stdin on both sides
    # to get comparable output.
    if rustfmt --emit stdout --edition 2021 <"$file" >"$normalised" 2>/dev/null &&
      git show "HEAD:$file" 2>/dev/null | rustfmt --emit stdout --edition 2021 >"$current" 2>/dev/null; then
      if ! diff -q "$current" "$normalised" >/dev/null 2>&1; then
        changed="$changed $file"
      fi
    else
      # No rustfmt for this file type: fall back to whitespace-insensitive diff.
      if ! diff -q -w -B "$file" <(git show "HEAD:$file" 2>/dev/null) >/dev/null 2>&1; then
        changed="$changed $file"
      fi
    fi
  done < <(git diff --name-only -- core/noxflow-ipc shell/noxflow/Protocol.js)

  if [[ -n "${changed// /}" ]] && ! git diff --name-only -- docs/IPC_PROTOCOL.md | rg -q .; then
    echo "IPC implementation changed without docs/IPC_PROTOCOL.md" >&2
    echo "Changed:$changed" >&2
    return 1
  fi
}

check_paths() {
  # The pattern is written with a character class so that this file, which
  # holds the pattern itself, does not match its own search. It matches any
  # account's home directory, not just one.
  ! rg -n '/home/[a-zA-Z0-9_-]+/' \
    cli/noxctl core/noxd core/noxflow-config core/noxflow-ipc core/noxflow-state \
    shell/noxflow systemd/user hypr/scripts/panel-switch.sh config/default.toml \
    wayle/config.toml setup/install-noxflow-foundation.sh setup/bootstrap.sh \
    setup/install-llama-router.sh setup/download-local-models.sh setup/test-local-models.sh \
    setup/lib/install-manifest.sh setup/rollback.sh setup/release-gate.sh \
    system/llama-router AGENTS.md git/gitconfig bashrc zshrc aliases.local.zsh \
    android/android-env.conf android/android-env.sh \
    configs/claude/mcp.json configs/opencode/chrome-devtools-mcp.sh \
    ai/mcp \
    docs/IPC_PROTOCOL.md docs/NOXCTL.md docs/MILESTONE_1_RELEASE_REPORT.md
}

run_static() {
  check "shell script lint and format" bash setup/check-shell.sh --all
  check "no hard-coded home paths" check_paths
  check "installed defaults" bash setup/test-installed-defaults.sh
  check "systemd user units" bash setup/test-systemd-units.sh
  check "documented IPC changes" check_ipc_docs
  # The plan quotes line counts and an acceptance verdict. Prose goes stale;
  # this asserts those quotes against the tree, so a stale figure is caught
  # rather than read as current.
  check "repair plan matches the tree" bash setup/check-noxflow-plan.sh
  check "fallback shell" bash -n hypr/scripts/panel-switch.sh
}

# ── integration checks ────────────────────────────────────────────────────
# These build and run the code. They need the toolchain, but not a session.

check_rust() {
  while IFS= read -r manifest; do
    cargo fmt --manifest-path "$manifest" --all -- --check || return 1
    cargo clippy --manifest-path "$manifest" --all-targets --all-features -- -D warnings || return 1
    cargo test --manifest-path "$manifest" --all-targets || return 1
  done < <(find core cli -name Cargo.toml -print | sort)
}

check_qml() {
  command -v qmllint >/dev/null
  while IFS= read -r file; do
    if ! qmllint -I shell/noxflow "$file"; then
      echo "FAIL: invalid QML: $file" >&2
      return 1
    fi
  done < <(find shell/noxflow -name '*.qml' -print | sort)
}

# Every NoxFlow shell suite, not just test_protocol.js. run-all.js discovers
# and runs all of them and fails on the first regression.
check_shell_tests() {
  node shell/noxflow/tests/run-all.js
}

check_units() {
  systemd-analyze verify \
    systemd/user/noxd.service \
    systemd/user/noxflow-shell.service \
    systemd/user/noxflow-fallback.service \
    systemd/user/noxflow-session-optional.service
}

check_config() {
  cargo test --manifest-path core/noxflow-config/Cargo.toml --test integration
}

run_integration() {
  check "Rust format, lint, and tests" check_rust
  check "QML syntax" check_qml
  check "NoxFlow shell test suites" check_shell_tests
  check "systemd unit validity" check_units
  check "required configuration" check_config
  # The installer contract: a dry run writes nothing, a rollback undoes
  # exactly what an install recorded, and a path the repository does not own
  # is never deleted. Both run against a throwaway HOME.
  check "bootstrap safety" bash setup/test-bootstrap-safety.sh
  check "local model root" bash setup/test-llama-router-paths.sh
  # The standalone setup suites. They were never wired into anything, so a
  # stale expectation in one of them went unnoticed.
  check "keybind documentation" bash setup/test-keybind-docs.sh
  check "MCP profile" bash setup/test-mcp-profile.sh
  check "node runtime bridge" bash setup/test-node-runtime-bridge.sh
  check "pnpm runtime bridge" bash setup/test-pnpm-bridge.sh
  check "project resume" bash setup/test-project-resume.sh
  check "desktop launch" bash setup/test-desktop-launch.sh
  check "project profile" bash setup/test-project-profile.sh
  check "AI configuration" bash setup/test-ai-config.sh
}

# ── live checks ───────────────────────────────────────────────────────────
# These need a logged-in Hyprland session: the installed packages, the
# running services and the shell-to-daemon link.

check_required_runtime() {
  if ! command -v quickshell >/dev/null 2>&1; then
    echo 'FAIL: required NoxFlow shell runtime `quickshell` is not installed' >&2
    echo 'Fix: sudo pacman -S --needed quickshell' >&2
    return 1
  fi
  if ! pacman -Q quickshell >/dev/null 2>&1; then
    echo 'FAIL: required NoxFlow shell runtime `quickshell` is not owned by pacman' >&2
    echo 'Fix: sudo pacman -S --needed quickshell' >&2
    return 1
  fi
}

check_optional_runtime() {
  local imports="$(rg -n '^import (QtMultimedia|Qt5Compat)' shell/noxflow || true)"
  local package
  for package in qt6-imageformats qt6-multimedia qt6-5compat; do
    if [[ -n "$imports" && "$package" != qt6-imageformats ]]; then
      if ! pacman -Q "$package" >/dev/null 2>&1; then
        echo "FAIL: optional QML module required by the shell is missing: $package" >&2
        echo "Fix: sudo pacman -S --needed $package" >&2
        return 1
      fi
    fi
  done
}

check_shell_launch() {
  if ! systemctl --user is-active noxflow-shell.service >/dev/null 2>&1; then
    echo 'FAIL: Quickshell is installed but the NoxFlow shell is unable to launch' >&2
    echo 'Fix: journalctl --user -u noxflow-shell.service -n 80 --no-pager' >&2
    return 1
  fi
}

check_shell_ipc() {
  local recent start
  start="$(systemctl --user show noxflow-shell.service -p ActiveEnterTimestamp --value 2>/dev/null || true)"
  recent="$(journalctl --user -u noxflow-shell.service --since "${start:-'-2 minutes'}" --no-pager -o cat 2>/dev/null || true)"
  if ! grep -q 'noxd IPC subscribed' <<<"$recent"; then
    echo 'FAIL: Quickshell launched but did not connect to `noxd`' >&2
    echo 'Fix: journalctl --user -u noxflow-shell.service -n 80 --no-pager' >&2
    return 1
  fi
}

check_live() {
  command -v systemctl >/dev/null
  command -v quickshell >/dev/null
  systemctl --user daemon-reload
  systemctl --user is-enabled noxd.service noxflow-shell.service >/dev/null
  systemctl --user is-active noxd.service >/dev/null
  systemctl --user is-active noxflow-shell.service >/dev/null
  "$repo_dir/setup/measure-noxflow.sh" --check
}

run_live() {
  # The config-load check restarts the running shell when the unit is
  # installed, so it belongs here and not in the session-free modes.
  check "NoxFlow config loads" bash setup/check-noxflow-load.sh
  check "external program registry" bash setup/check-noxflow-binaries.sh
  check "required shell runtime" check_required_runtime
  check "optional QML modules" check_optional_runtime
  check "Quickshell launch" check_shell_launch
  check "Quickshell-to-noxd IPC" check_shell_ipc
  check "live shell integration" check_live
}

case "$mode" in
  verify-static) run_static ;;
  verify-integration) run_integration ;;
  verify-live) run_live ;;
  all)
    run_static
    run_integration
    run_live
    ;;
esac

if ((failed)); then
  echo "NoxFlow release gate ($mode): FAILED" >&2
  exit 1
fi
echo "NoxFlow release gate ($mode): PASSED"
