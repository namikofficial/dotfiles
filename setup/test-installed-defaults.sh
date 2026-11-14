#!/usr/bin/env bash
# Regression test for the installed defaults.
#
# The public repository is installed into a user's home directory, so a file
# that hard-codes one account's home path breaks the install for everyone
# else: the symlink resolves, the path inside it does not exist.
#
# Two things are checked:
#
#   1. No tracked file carries an absolute home path, except the documented
#      exceptions below.
#   2. The managed git and ssh settings still resolve after the home path
#      was replaced by '~'. A portable value that the tool does not expand
#      is worse than the hard-coded path it replaced.
set -uo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

failures=0

ok() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Files that are allowed to keep an absolute home path, each with a reason.
#
#   historical records  a transcript of what the machine actually did
#   opencode config     a live, symlinked config whose path resolution for
#                       'mcp.servers.*.command' cannot be verified offline
#   vscode settings     points into the optional private submodule, whose
#                       location the installer resolves at run time
exceptions=(
  'docs/archive/'
  'docs/audits/'
  'docs/SPRINT_1_AUDIT.md'
  'configs/opencode/agent-lab/results/'
  'configs/opencode/opencode.local-llamacpp.json'
  'code/vscode-user-settings.json'
)

# Home directories that are not an account: a test fixture uses '/home/user',
# and the server layout uses '/home/apps' for a container mount.
allowed_segments=(user apps)

printf '== no absolute home path in tracked files ==\n'

matches="$(git grep -nE '/home/[a-zA-Z0-9_-]+/' -- . 2>/dev/null || true)"
remaining=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  file="${line%%:*}"
  segment="$(grep -oE '/home/[a-zA-Z0-9_-]+' <<<"$line" | head -1 | sed -E 's#^/home/##')"

  skip=0
  for allowed in "${allowed_segments[@]}"; do
    if [ "$segment" = "$allowed" ]; then
      skip=1
      break
    fi
  done
  if [ "$skip" -eq 0 ]; then
    for exception in "${exceptions[@]}"; do
      case "$file" in
        "$exception"*)
          skip=1
          break
          ;;
      esac
    done
  fi
  [ "$skip" -eq 0 ] && remaining="$remaining$line\n"
done <<<"$matches"

if [ -z "$remaining" ]; then
  ok "no tracked file outside the documented exceptions carries a home path"
else
  fail "tracked files still carry an absolute home path"
  printf '%s' "$remaining" | head -20 >&2
fi

printf '== the managed git settings still resolve ==\n'

gitconf="$repo_dir/git/gitconfig"
read_git_conf() {
  git -c include.path="$gitconf" config --path --get "$1" 2>/dev/null || true
}

hooks_path="$(read_git_conf core.hooksPath)"
signing_key="$(read_git_conf user.signingkey)"
allowed_signers="$(read_git_conf gpg.ssh.allowedSignersFile)"

home_dir="$HOME"

for pair in \
  "core.hooksPath:$hooks_path" \
  "user.signingkey:$signing_key" \
  "gpg.ssh.allowedSignersFile:$allowed_signers"; do
  label="${pair%%:*}"
  value="${pair#*:}"
  if [ -z "$value" ]; then
    fail "$label is set in the managed gitconfig"
  elif [ "${value#"$home_dir"/}" != "$value" ]; then
    ok "$label expands to the current home directory"
  else
    fail "$label expands to the current home directory (got '$value')"
  fi
done

printf '== the managed ssh command stays portable ==\n'

ssh_command="$(git -c include.path="$gitconf" config --get core.sshCommand 2>/dev/null || true)"
if [ -z "$ssh_command" ]; then
  fail "core.sshCommand is set in the managed gitconfig"
elif grep -qE '/home/[a-zA-Z0-9_-]+/' <<<"$ssh_command"; then
  fail "core.sshCommand carries no absolute home path (got '$ssh_command')"
else
  ok "core.sshCommand carries no absolute home path"
fi

# Git runs core.sshCommand through the shell, so a leading '~' in the
# identity path is expanded there. Prove it rather than assume it.
identity="${ssh_command##* }"
expanded="$(sh -c "echo $identity" 2>/dev/null || true)"
if [ -n "$expanded" ] && [ "${expanded#"$home_dir"/}" != "$expanded" ]; then
  ok "the shell expands the identity path git hands to ssh"
else
  fail "the shell expands the identity path git hands to ssh (got '${expanded:-<none>}')"
fi

printf '\n'
if [ "$failures" -eq 0 ]; then
  printf 'installed defaults: ok\n'
  exit 0
fi
printf 'installed defaults: %d failure(s)\n' "$failures" >&2
exit 1
