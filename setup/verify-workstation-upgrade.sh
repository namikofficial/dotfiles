#!/usr/bin/env bash
set -euo pipefail

# Read-only verification after a system/package upgrade.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ok_count=0
warn_count=0

ok() {
  ok_count=$((ok_count + 1))
  printf '[OK]   %s\n' "$*"
}

warn() {
  warn_count=$((warn_count + 1))
  printf '[WARN] %s\n' "$*"
}

check_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$command_name is available"
  else
    warn "$command_name is missing"
  fi
}

printf '=== Workstation upgrade verification ===\n'
printf 'repo: %s\n\n' "$REPO_DIR"

printf '%s\n' '-- Package versions --'
if command -v pacman >/dev/null 2>&1; then
  pacman -Q kitty scrcpy neovim onetbb virt-manager libvirt 2>/dev/null || true
else
  warn 'pacman is unavailable; package versions skipped'
fi

printf '%s\n' '-- Kitty and terminal --'
check_command kitty
if command -v kitty >/dev/null 2>&1; then
  kitty --config "$REPO_DIR/kitty/kitty.conf" --dump-commands >/tmp/noxflow-kitty-debug-config.$$ 2>&1 || true
  if [ -f /tmp/noxflow-kitty-debug-config.$$ ]; then
    if rg -n -i 'unknown config key|ignoring unknown config key|invalid' /tmp/noxflow-kitty-debug-config.$$; then
      warn 'Kitty reported configuration problems'
    else
      ok 'Kitty configuration has no obvious invalid entries'
    fi
    rm -f /tmp/noxflow-kitty-debug-config.$$
  fi
fi
if [ "${TERM:-}" = 'xterm-kitty' ]; then
  ok 'TERM is xterm-kitty'
else
  warn "TERM is ${TERM:-unset}; run this check inside Kitty for terminal validation"
fi
if infocmp xterm-kitty >/dev/null 2>&1; then
  ok 'xterm-kitty terminfo is installed'
else
  warn 'xterm-kitty terminfo is unavailable'
fi

printf '%s\n' '-- Shell and editor --'
check_command zsh
check_command nvim
if command -v zsh >/dev/null 2>&1 && zsh -n "$REPO_DIR/zshrc"; then
  ok 'zshrc syntax is valid'
else
  warn 'zshrc syntax check failed'
fi
if command -v nvim >/dev/null 2>&1 && nvim --headless '+qa' >/tmp/noxflow-nvim-check.$$ 2>&1; then
  ok 'Neovim starts headlessly'
else
  warn 'Neovim headless startup failed'
fi
rm -f /tmp/noxflow-nvim-check.$$

printf '%s\n' '-- Android and scrcpy --'
check_command adb
check_command scrcpy
if command -v scrcpy >/dev/null 2>&1; then
  if scrcpy --list-encoders >/tmp/noxflow-scrcpy-encoders.$$ 2>&1; then
    ok 'scrcpy encoder listing works'
    rg -n 'h265|vp9|vp8' /tmp/noxflow-scrcpy-encoders.$$ || true
  else
    warn 'scrcpy encoder listing failed'
  fi
  rm -f /tmp/noxflow-scrcpy-encoders.$$
fi
if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
  ok "Android SDK exists at $ANDROID_SDK_ROOT"
else
  warn 'ANDROID_SDK_ROOT is unset or missing'
fi

printf '%s\n' '-- Virtualization --'
check_command virsh
check_command virt-manager
if command -v virsh >/dev/null 2>&1; then
  virsh list --all >/dev/null 2>&1 && ok 'libvirt domains are readable' || warn 'libvirt domains are unavailable'
  virsh net-list --all >/dev/null 2>&1 && ok 'libvirt networks are readable' || warn 'libvirt networks are unavailable'
  virsh pool-list --all >/dev/null 2>&1 && ok 'libvirt storage pools are readable' || warn 'libvirt storage pools are unavailable'
fi
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  ok '/dev/kvm is accessible'
else
  warn '/dev/kvm is unavailable or inaccessible'
fi

printf '\nSummary: ok=%d warn=%d\n' "$ok_count" "$warn_count"
if ((warn_count > 0)); then
  printf 'RESULT: WARN\n'
else
  printf 'RESULT: PASS\n'
fi
