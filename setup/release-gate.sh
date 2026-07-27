#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

failed=0
check() {
  local name="$1"; shift
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
    qmllint -I shell/noxflow "$file" || return 1
  done < <(find shell/noxflow -name '*.qml' -print | sort)
  node shell/noxflow/tests/test_protocol.js
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
  local changed
  changed="$(git diff --name-only -- core/noxflow-ipc shell/noxflow/Protocol.js)"
  if [[ -n "$changed" ]] && ! git diff --name-only -- docs/IPC_PROTOCOL.md | rg -q .; then
    echo "IPC implementation changed without docs/IPC_PROTOCOL.md" >&2
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
check "QML syntax and protocol fixtures" check_qml
check "systemd unit validity" check_units
check "required configuration" check_config
check "fallback shell" bash -n hypr/scripts/panel-switch.sh
check "no hard-coded home paths" check_paths
check "documented IPC changes" check_ipc_docs
check "live shell integration" check_live

rm -f /tmp/noxflow-release-gate.out /tmp/noxflow-release-gate.err
if (( failed )); then
  echo "NoxFlow release gate: FAILED" >&2
  exit 1
fi
echo "NoxFlow release gate: PASSED"
