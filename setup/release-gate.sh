#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

failed=0
check() {
  local name="$1"
  shift
  printf '[gate] %-38s' "$name"
  if "$@" >/tmp/noxflow-release-gate.out 2>/tmp/noxflow-release-gate.err; then
    echo PASS
  else
    echo FAIL
    sed -n '1,24p' /tmp/noxflow-release-gate.err >&2
    failed=1
  fi
}

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

check_units() {
  systemd-analyze verify \
    systemd/user/noxd.service \
    systemd/user/noxflow-shell.service \
    systemd/user/noxflow-fallback.service \
    systemd/user/noxflow-session-optional.service
}

check_paths() {
  ! rg -n '/home/namik' \
    cli/noxctl core/noxd core/noxflow-config core/noxflow-ipc core/noxflow-state \
    shell/noxflow systemd/user hypr/scripts/panel-switch.sh config/default.toml \
    wayle/config.toml setup/install-noxflow-foundation.sh setup/bootstrap.sh \
    docs/IPC_PROTOCOL.md docs/NOXCTL.md docs/MILESTONE_1_RELEASE_REPORT.md
}

check_config() {
  cargo test --manifest-path core/noxflow-config/Cargo.toml --test integration
}

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
    normalised="$(mktemp)" current="$(mktemp)"
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
    rm -f "$normalised" "$current"
  done < <(git diff --name-only -- core/noxflow-ipc shell/noxflow/Protocol.js)

  if [[ -n "${changed// /}" ]] && ! git diff --name-only -- docs/IPC_PROTOCOL.md | rg -q .; then
    echo "IPC implementation changed without docs/IPC_PROTOCOL.md" >&2
    echo "Changed:$changed" >&2
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

check "Rust format, lint, and tests" check_rust
check "QML syntax" check_qml
# qmllint passes a config whose components cannot instantiate (it cannot resolve
# the Quickshell C++ module imports), so the shell is also loaded for real.
check "NoxFlow config loads" bash setup/check-noxflow-load.sh
check "NoxFlow shell test suites" check_shell_tests
check "external program registry" bash setup/check-noxflow-binaries.sh
check "required shell runtime" check_required_runtime
check "optional QML modules" check_optional_runtime
check "systemd unit validity" check_units
check "required configuration" check_config
check "fallback shell" bash -n hypr/scripts/panel-switch.sh
check "no hard-coded home paths" check_paths
check "documented IPC changes" check_ipc_docs
check "Quickshell launch" check_shell_launch
check "Quickshell-to-noxd IPC" check_shell_ipc
check "live shell integration" check_live

rm -f /tmp/noxflow-release-gate.out /tmp/noxflow-release-gate.err
if ((failed)); then
  echo "NoxFlow release gate: FAILED" >&2
  exit 1
fi
echo "NoxFlow release gate: PASSED"
