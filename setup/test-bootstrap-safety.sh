#!/usr/bin/env bash
# Regression tests for the installer safety contract.
#
# The installer manages the user's home directory, so the rules it has to
# keep are worth pinning down in a test:
#
#   * a dry run writes nothing at all;
#   * a dry run never aborts on a missing optional step;
#   * a real install records a manifest of everything it touched;
#   * a rollback undoes exactly that manifest;
#   * a path this repository does not own is never deleted, and never
#     deleted recursively.
#
# Every case runs against a throwaway HOME, so the test never touches the
# real workstation configuration.
set -uo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap="$repo_dir/setup/bootstrap.sh"
rollback="$repo_dir/setup/rollback.sh"

failures=0

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

ok() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" = "$actual" ]; then
    ok "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

assert_true() {
  local label="$1"
  shift
  if "$@"; then
    ok "$label"
  else
    fail "$label"
  fi
}

# The flags that keep the install local, offline and fast.
install_flags=(--no-local-ai --no-zsh-plugins --no-tmux-plugins)

run_bootstrap() {
  local home="$1"
  shift
  HOME="$home" XDG_STATE_HOME="$home/.local/state" \
    bash "$bootstrap" "${install_flags[@]}" "$@"
}

printf '== dry run ==\n'

home="$tmp_root/dry"
mkdir -p "$home"
out="$(HOME="$home" XDG_STATE_HOME="$home/.local/state" \
  bash "$bootstrap" --dry-run --no-local-ai 2>&1)"
code=$?
assert_eq 0 "$code" "dry run exits successfully"
assert_eq 0 "$(find "$home" -mindepth 1 | wc -l | tr -d ' ')" \
  "dry run creates nothing under HOME"

home="$tmp_root/dry-default"
mkdir -p "$home"
HOME="$home" XDG_STATE_HOME="$home/.local/state" \
  bash "$bootstrap" --dry-run >/dev/null 2>&1
code=$?
assert_eq 0 "$code" "dry run with the default option set exits successfully"
assert_eq 0 "$(find "$home" -mindepth 1 | wc -l | tr -d ' ')" \
  "dry run with the default option set creates nothing under HOME"

printf '== install and manifest ==\n'

home="$tmp_root/install"
mkdir -p "$home"
run_bootstrap "$home" >/dev/null 2>&1
code=$?
assert_eq 0 "$code" "install succeeds"

manifest="$(ls "$home"/.local/state/dotfiles/manifests/manifest-*.tsv 2>/dev/null | head -1)"
if [ -n "$manifest" ]; then
  ok "install writes a manifest"
else
  fail "install writes a manifest"
fi

rows=0
if [ -n "$manifest" ]; then
  rows="$(grep -vc '^#' "$manifest" 2>/dev/null || echo 0)"
fi
if [ "$rows" -gt 0 ]; then
  ok "manifest records actions ($rows)"
else
  fail "manifest records actions"
fi

assert_true "install links the managed files" test -L "$home/.zshrc"

printf '== rollback ==\n'

if [ -n "$manifest" ]; then
  HOME="$home" bash "$rollback" --manifest "$manifest" >/dev/null 2>&1
  code=$?
  assert_eq 0 "$code" "rollback succeeds"

  # Every link the manifest records must be gone. The check is driven by
  # the manifest rather than by a directory scan: ~/.ssh/config is owned by
  # setup/install-ssh-config.sh, which has its own restore path and is not
  # part of the bootstrap manifest.
  remaining=0
  while IFS=$'\t' read -r action target source backup; do
    [ "$action" = "link" ] || continue
    [ -n "$target" ] || continue
    if [ -L "$target" ]; then
      remaining=$((remaining + 1))
      printf '     still linked: %s\n' "$target" >&2
    fi
  done < <(grep -v '^#' "$manifest" 2>/dev/null)
  assert_eq 0 "$remaining" "rollback removes every link recorded in the manifest"

  HOME="$home" bash "$rollback" --manifest "$manifest" --dry-run >/dev/null 2>&1
  assert_eq 0 "$?" "rollback dry run succeeds"
fi

printf '== unmanaged targets are preserved ==\n'

home="$tmp_root/user-file"
mkdir -p "$home"
printf 'user zshrc\n' >"$home/.zshrc"
run_bootstrap "$home" >/dev/null 2>&1
code=$?
assert_eq 0 "$code" "install over a user file succeeds"
backup="$(ls "$home"/.zshrc.bak.* 2>/dev/null | head -1)"
if [ -n "$backup" ] && [ "$(cat "$backup")" = "user zshrc" ]; then
  ok "a user file is moved aside, not deleted"
else
  fail "a user file is moved aside, not deleted"
fi

home="$tmp_root/user-dir"
mkdir -p "$home/.config/nvim/lua"
printf 'mine\n' >"$home/.config/nvim/lua/mine.lua"
run_bootstrap "$home" >/dev/null 2>&1
code=$?
assert_eq 0 "$code" "install over a user directory succeeds"
kept="$(ls -d "$home"/.config/nvim.bak.*/lua/mine.lua 2>/dev/null | head -1)"
if [ -n "$kept" ] && [ "$(cat "$kept")" = "mine" ]; then
  ok "a user directory is moved aside, never deleted recursively"
else
  fail "a user directory is moved aside, never deleted recursively"
fi

home="$tmp_root/user-link"
mkdir -p "$home/real-file"
printf 'data\n' >"$home/real-file/data.txt"
ln -s "$home/real-file" "$home/.zshrc"
run_bootstrap "$home" >/dev/null 2>&1
code=$?
assert_eq 0 "$code" "install over a user symlink succeeds"
if [ -f "$home/real-file/data.txt" ] && [ "$(cat "$home/real-file/data.txt")" = "data" ]; then
  ok "a user symlink is never followed and its target is untouched"
else
  fail "a user symlink is never followed and its target is untouched"
fi

printf '== --no-backup refuses unmanaged targets ==\n'

home="$tmp_root/no-backup"
mkdir -p "$home"
printf 'user zshrc\n' >"$home/.zshrc"
run_bootstrap "$home" --no-backup >/dev/null 2>&1
code=$?
assert_eq 1 "$code" "--no-backup fails on an unmanaged target"
if [ -f "$home/.zshrc" ] && [ "$(cat "$home/.zshrc")" = "user zshrc" ]; then
  ok "--no-backup leaves the unmanaged target untouched"
else
  fail "--no-backup leaves the unmanaged target untouched"
fi

printf '== obsolete override is removable and restorable ==\n'

home="$tmp_root/legacy"
mkdir -p "$home/.config/systemd/user/wayland-wm@hyprland.desktop.service.d"
ln -s "$repo_dir/systemd/user/noxflow-shell.service" \
  "$home/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf"
run_bootstrap "$home" >/dev/null 2>&1
code=$?
assert_eq 0 "$code" "install with the legacy override present succeeds"
assert_true "the obsolete override is removed" \
  test ! -e "$home/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf"

manifest="$(ls "$home"/.local/state/dotfiles/manifests/manifest-*.tsv 2>/dev/null | head -1)"
if [ -n "$manifest" ]; then
  HOME="$home" bash "$rollback" --manifest "$manifest" >/dev/null 2>&1
  assert_true "rollback restores the obsolete override" \
    test -L "$home/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf"
fi

printf '\n'
if [ "$failures" -eq 0 ]; then
  printf 'bootstrap safety: ok\n'
  exit 0
fi
printf 'bootstrap safety: %d failure(s)\n' "$failures" >&2
exit 1
